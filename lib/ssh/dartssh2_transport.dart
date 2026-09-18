import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/core.dart';

import '../models.dart';
import 'dartssh2_sftp.dart';
import 'host_key_store.dart';
import 'jump_host.dart';
import 'sftp.dart';
import 'ssh_agent.dart';
import 'ssh_credentials.dart';
import 'ssh_transport.dart';

/// dartssh2 实现。web 平台下 [SSHSocket.connect] 会在运行时抛出
/// [UnsupportedError]（浏览器没有原始 TCP），由上层统一归类为不支持。
final class DartSsh2Transport implements SshTransport {
  DartSsh2Transport(
    this._server,
    this._credentials, [
    this._hostKeys,
    this._allowLegacyHostKeys = false,
    this._jumps = const [],
  ]);

  static const _connectTimeout = Duration(seconds: 12);

  final SshServer _server;
  final SshCredentials _credentials;

  /// TOFU 指纹存储；为空时不做主机密钥校验（仅测试场景）。
  final HostKeyStore? _hostKeys;

  /// 允许只提供 `ssh-rsa`（SHA-1）主机密钥的老设备（见 SSHAlgorithms 的构造）。
  final bool _allowLegacyHostKeys;

  /// 跳板机链路，由外到内，不含目标主机本身。
  final List<SshHop> _jumps;

  /// [_verifyHostKey] 无法向 dartssh2 抛自定义异常（回调错误会在传输层
  /// 内部消化），改为记下详情，attach 里再换成更明确的错误抛出。
  HostKeyChangedException? _hostKeyMismatch;
  HostKeyUnavailableException? _hostKeyUnavailable;

  SSHClient? _client;
  SSHSession? _session;

  /// 跳板机各跳的客户端：目标连上之后它们只负责转发，不能提前关掉。
  final List<SSHClient> _jumpClients = [];

  /// Agent 认证用到的 agent 连接：签名只发生在认证期间，但连接本身要
  /// 活到认证结束，因此随传输持有，dispose（或中途失败）时一并关掉。
  final List<SshAgentClient> _agentClients = [];

  /// 已建立但还没交给 [_client] 的连接。用在握手完成到 client 建好之间的
  /// 窗口期：这期间 dispose 只能关到这个 socket，否则它就漏了。
  SSHSocket? _socket;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  bool _disposed = false;

  /// 挂上回调的终端与那份写入闭包，关闭时按原样摘掉（见 [_detachTerminal]）。
  Terminal? _terminal;
  void Function(String data)? _sendOutput;

  @override
  Future<void> attach(
    Terminal terminal, {
    required void Function() onConnected,
    required void Function() onClosed,
  }) async {
    final SSHSocket socket;
    try {
      socket = await _openSocket();
    } on Object {
      // 跳板机连不上时把已经建好的那几跳收干净再往上抛。
      _closeQuietly();
      rethrow;
    }
    // 连接是异步的：用户可能在这十几秒里已经断开了这个会话。
    // 此处的 dispose 当时只看到 _client / _session 都还是 null，
    // 什么也没关掉，所以必须在这里补一次检查——否则接下来会建成一个
    // 完全认证过、却再也没人持有的 SSH 会话，一直挂到进程退出。
    if (_disposed) {
      await socket.close();
      return;
    }
    _socket = socket;

    final SSHClient client;
    try {
      // 身份先于 client 构造解析：agent 连不上 / PEM 解不开时 socket 已经
      // 连上了，必须在这里收干净再抛。
      final identities = await _identitiesOf(_credentials);
      if (_disposed) {
        await _closeAgents();
        await socket.close();
        return;
      }
      client = _client = _createClient(
        _server,
        _credentials,
        socket,
        identities,
      );
    } on Object {
      // 私钥解析失败、agent 不可用之类会在构造 client 前后就抛，此时
      // socket 已经连上了。
      _closeQuietly();
      rethrow;
    }

    final SSHSession session;
    try {
      // shell() 返回时握手与认证已完成：known_hosts 校验失败在这里抛出。
      session = _session = await client.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );
    } on SSHHostkeyError {
      _closeQuietly();
      // 指纹读不出来时不能给「清除指纹」这条路：那会真的丢掉可信记录。
      throw _hostKeyUnavailable ??
          _hostKeyMismatch ??
          SSHHostkeyError('Hostkey verification failed');
    } on Object {
      _closeQuietly();
      rethrow;
    }

    // 认证同样要花时间，窗口期内被断开的话到这里收手。
    if (_disposed) {
      _closeQuietly();
      return;
    }

    void sendOutput(String data) => session.stdin.add(utf8.encode(data));
    _terminal = terminal;
    _sendOutput = sendOutput;
    terminal
      ..onOutput = sendOutput
      ..onResize = session.resizeTerminal;

    // allowMalformed：坏字节显示为乱码而不是中断输出流。
    const decoder = Utf8Decoder(allowMalformed: true);
    _subscriptions
      ..add(
        session.stdout
            .cast<List<int>>()
            .transform(decoder)
            .listen(
              terminal.write,
              onDone: onClosed,
              onError: (Object _) => onClosed(),
            ),
      )
      ..add(
        session.stderr
            .cast<List<int>>()
            .transform(decoder)
            .listen(terminal.write),
      );
    // 传输层异常断开（shell 流可能还挂着）时兜底上报关闭。
    // 连接建立成功后才注册：此前的失败已经走 attach 抛错，不用抢状态。
    unawaited(
      client.done.then((_) => onClosed(), onError: (Object _) => onClosed()),
    );

    onConnected();
  }

  /// 逐跳建立到目标主机的 socket：有跳板机时，每一跳都是上一跳连接上的
  /// 一条 direct-tcpip 通道，最后一跳连的是目标主机。
  Future<SSHSocket> _openSocket() async {
    SSHClient? upstream;
    for (final hop in _jumps) {
      if (_disposed) throw const _Cancelled();
      final socket = upstream == null
          ? await SSHSocket.connect(
              hop.server.host,
              hop.server.port,
              timeout: _connectTimeout,
            )
          : await upstream.forwardLocal(
              hop.server.host,
              hop.server.port,
              localHost: _originHost,
            );
      if (_disposed) {
        await socket.close();
        throw const _Cancelled();
      }
      // 每跳各取各的身份：跳板机也可以走 Agent 认证（一跳一份凭据）。
      final hopIdentities = await _identitiesOf(hop.credentials);
      if (_disposed) {
        await socket.close();
        throw const _Cancelled();
      }
      final client = _createClient(
        hop.server,
        hop.credentials,
        socket,
        hopIdentities,
      );
      _jumpClients.add(client);
      try {
        // 跳板机必须先认证完，否则下一跳的 direct-tcpip 请求发不出去。
        await client.authenticated;
      } on SSHHostkeyError {
        throw _hostKeyError(hop.server);
      } on Object catch (error) {
        // 指明是哪一跳失败：链路上有三台机器时「认证失败」不足以定位。
        throw SshHopException(hop.server, error);
      }
      upstream = client;
    }
    if (upstream == null) {
      return SSHSocket.connect(
        _server.host,
        _server.port,
        timeout: _connectTimeout,
      );
    }
    return upstream.forwardLocal(
      _server.host,
      _server.port,
      localHost: _originHost,
    );
  }

  /// direct-tcpip 的 originator 字段，仅用于服务端日志。
  static const _originHost = '127.0.0.1';

  SSHClient _createClient(
    SshServer server,
    SshCredentials credentials,
    SSHSocket socket,
    List<SSHIdentity> identities,
  ) => SSHClient(
    socket,
    username: server.username,
    identities: identities,
    // 密码认证；OpenSSH 默认开启的 keyboard-interactive 也映射到同一密码。
    onPasswordRequest: () => credentials.password,
    onUserInfoRequest: (request) {
      final password = credentials.password;
      if (password == null) return null;
      return List.filled(request.prompts.length, password);
    },
    handshakeTimeout: _connectTimeout,
    // 算法集：默认沿用 dartssh2 的现代默认值；只有用户显式打开
    // 「兼容旧服务器」时才把 ssh-rsa（SHA-1）加回主机密钥列表。
    // 不加这一步，老设备会在握手时报 StateError('No matching host key
    // algorithm')，而那是用户看不懂的英文原文。
    algorithms: _allowLegacyHostKeys
        ? const SSHAlgorithms(
            hostkey: [
              SSHHostkeyType.ed25519,
              SSHHostkeyType.rsaSha512,
              SSHHostkeyType.rsaSha256,
              SSHHostkeyType.ecdsa521,
              SSHHostkeyType.ecdsa384,
              SSHHostkeyType.ecdsa256,
              // 追加在末尾：现代算法优先，旧算法只是兜底。
              SSHHostkeyType.rsaSha1,
            ],
          )
        : const SSHAlgorithms(),
    // known_hosts / TOFU 指纹校验：首次记录、变更拒绝（见 host_key_store.dart）。
    onVerifyHostKey: _hostKeys == null
        ? null
        : (keyType, rawFingerprint) =>
              _verifyHostKey(server, keyType, rawFingerprint),
  );

  /// 指纹回调失败后抛出的错误：指纹读不出来时不能给「清除指纹」这条路。
  Object _hostKeyError(SshServer server) =>
      _hostKeyUnavailable ??
      _hostKeyMismatch ??
      SSHHostkeyError('Hostkey verification failed (${server.host})');

  Future<bool> _verifyHostKey(
    SshServer server,
    String keyType,
    Uint8List rawFingerprint,
  ) async {
    final store = _hostKeys!;
    final fingerprint = utf8.decode(rawFingerprint);
    final decision = await verifyHostKey(
      store,
      host: server.host,
      port: server.port,
      keyType: keyType,
      fingerprint: fingerprint,
    );
    switch (decision) {
      case HostKeyDecision.trusted:
      case HostKeyDecision.firstUse:
        return true;
      case HostKeyDecision.mismatch:
        _hostKeyMismatch = HostKeyChangedException(
          host: server.host,
          port: server.port,
          keyType: keyType,
          fingerprint: fingerprint,
        );
        return false;
      case HostKeyDecision.unavailable:
        _hostKeyUnavailable = HostKeyUnavailableException(
          host: server.host,
          port: server.port,
        );
        return false;
    }
  }

  /// 目标 / 各跳的身份清单：Agent 认证从本机 agent 取，否则解析 PEM。
  /// 失败在这里抛出（agent 不可用 / 私钥格式不支持），由会话层归类文案。
  Future<List<SSHIdentity>> _identitiesOf(SshCredentials credentials) async {
    if (credentials.useAgent) {
      final agent = await connectSshAgent();
      _agentClients.add(agent);
      final keys = await agent.listIdentities();
      if (keys.isEmpty) {
        throw const SshAgentUnavailableException('agent has no loaded keys');
      }
      return agentIdentitiesAsSsh(agent, keys);
    }
    final pem = credentials.privateKey;
    if (pem == null || pem.isEmpty) return const [];
    try {
      return SSHKeyPair.fromPem(pem, credentials.passphrase);
    } on Object catch (error) {
      // dartssh2 对不认识的 PEM 头（典型的 PKCS#8 `BEGIN PRIVATE KEY`）
      // 抛 UnsupportedError，那会被上层当成「平台不支持 SSH」——报错完全
      // 指错方向。这里换成专用类型，界面才能给出「换个密钥格式」的提示。
      throw PrivateKeyUnsupportedException(error.toString());
    }
  }

  /// 关掉本条连接用过的所有 agent 连接。
  Future<void> _closeAgents() async {
    for (final agent in _agentClients) {
      await agent.close();
    }
    _agentClients.clear();
  }

  @override
  Future<SftpFileSystem> openSftp() async {
    final client = _requireClient();
    try {
      final sftp = await client.sftp();
      try {
        // 显式等待版本握手：服务端未启用 sftp 子系统时通道会被立刻拒绝，
        // 在这里失败就能直接给出「不支持 SFTP」，而不是等第一次读目录才报错。
        await sftp.handshake;
      } on Object catch (error) {
        // 连接刚建好就握手失败，几乎都是服务端没有 sftp 子系统；
        // 只有明确的套接字 / 超时故障才按网络问题上报。
        final network =
            error is SSHSocketError ||
            error is SSHDisconnectError ||
            error is TimeoutException;
        throw SftpException(
          network ? SftpErrorKind.network : SftpErrorKind.unsupported,
          error.toString(),
        );
      }
      return DartSsh2SftpFileSystem(sftp);
    } on SftpException {
      rethrow;
    } on Object catch (error) {
      throw sftpErrorFrom(error);
    }
  }

  @override
  Future<DuplexChannel> openDirectChannel(String host, int port) async {
    final client = _requireClient();
    try {
      final channel = await client.forwardLocal(
        host,
        port,
        localHost: _originHost,
      );
      return DartSsh2Channel(channel);
    } on Object catch (error) {
      throw dartSsh2ForwardError(error);
    }
  }

  @override
  Future<RemoteForwardListener> openRemoteForward({
    required String host,
    required int port,
  }) async {
    final client = _requireClient();
    try {
      // 返回 null 即服务端拒绝了 tcpip-forward 请求（端口被占 / 不允许监听）。
      final forward = await client.forwardRemote(host: host, port: port);
      if (forward == null) {
        throw const ForwardException(
          ForwardErrorKind.refused,
          'Server refused to listen on the requested port',
        );
      }
      return DartSsh2RemoteForward(client, forward);
    } on ForwardException {
      rethrow;
    } on Object catch (error) {
      throw dartSsh2ForwardError(error);
    }
  }

  @override
  Future<DynamicForwardProxy> openDynamicProxy({
    required String host,
    required int port,
  }) async {
    final client = _requireClient();
    try {
      final forward = await client.forwardDynamic(
        bindHost: host,
        bindPort: port,
      );
      return DartSsh2DynamicForward(forward);
    } on Object catch (error) {
      throw dartSsh2ForwardError(error);
    }
  }

  SSHClient _requireClient() {
    final client = _client;
    if (client == null || _disposed) {
      throw const ForwardException(
        ForwardErrorKind.notConnected,
        'SSH connection is not established',
      );
    }
    return client;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _closeQuietly();
  }

  /// 关掉当前持有的一切：已建好的 client，或只连上、还没交给 client 的 socket。
  /// 三处清理路径（dispose 与两种失败）都走它，避免漏掉中间态的 socket。
  void _closeQuietly() {
    _detachTerminal();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _session?.close();
    final client = _client;
    if (client != null) {
      client.close();
    } else {
      // client 还没建起来时，socket 是唯一持有的资源。
      unawaited(_socket?.close());
    }
    // 跳板机的连接由本对象持有，目标关掉后它们也不会再被复用。
    for (final jump in _jumpClients) {
      jump.close();
    }
    _jumpClients.clear();
    // agent 连接只服务于认证，连接结束即无用了。
    unawaited(_closeAgents());
  }

  /// 摘掉挂给终端的两个回调。
  ///
  /// 不摘的话，会话结束（断开 / 失败 / 退避等待重连）之后终端仍会把键入
  /// 与窗口尺寸变化送进这条已经关掉的传输：写入落进无人消费的 sink 里越积
  /// 越多，resize 则直接在 dartssh2 的 `sendPacket` 里抛
  /// `SSHStateError('Transport is closed')`——拖窗口、收起侧边栏都会触发，
  /// 异常最终报到控制台并中断那次布局。
  void _detachTerminal() {
    final terminal = _terminal;
    final output = _sendOutput;
    _terminal = null;
    _sendOutput = null;
    // 只摘自己挂的那一份：终端可能已经接到新的传输上了。
    if (terminal == null || !identical(terminal.onOutput, output)) return;
    terminal.onOutput = null;
    terminal.onResize = null;
  }
}

/// attach 期间发现会话已被用户断开时的内部信号：不展示给用户
/// （[TerminalSession.terminate] 已经把状态置为 closed，错误分支会被忽略）。
final class _Cancelled implements Exception {
  const _Cancelled();
}

/// 把 dartssh2 的转发错误归类；界面据此挑选文案。
/// 通用类型（[ForwardException] / [UnsupportedError] / 超时）交给
/// [forwardErrorFrom]，这里只补 dartssh2 自己的错误类型。
ForwardException dartSsh2ForwardError(Object error) {
  if (error is SSHChannelOpenError || error is SSHChannelRequestError) {
    return ForwardException(ForwardErrorKind.refused, error.toString());
  }
  if (error is SSHSocketError || error is SSHDisconnectError) {
    return ForwardException(ForwardErrorKind.network, error.toString());
  }
  return forwardErrorFrom(error);
}

/// [SSHForwardChannel] → [DuplexChannel] 的薄适配：通道的写入端是个
/// [StreamSink]，对端关掉后再 add 会抛 StateError，这里吞掉——连接结束
/// 由 stream 的 done 上报，不该在写入路径上再抛一次。
class DartSsh2Channel implements DuplexChannel {
  DartSsh2Channel(this._channel);

  final SSHForwardChannel _channel;

  @override
  Stream<List<int>> get stream => _channel.stream;

  @override
  void write(List<int> data) {
    try {
      _channel.sink.add(data);
    } on Object {
      // 对端已关闭，丢弃这一段。连接结束由 stream 的 done 上报。
    }
  }

  @override
  Future<void> close() => _channel.close();

  @override
  void destroy() => _channel.destroy();
}

/// 服务端监听型转发的适配。
class DartSsh2RemoteForward implements RemoteForwardListener {
  DartSsh2RemoteForward(this._client, this._forward);

  final SSHClient _client;
  final SSHRemoteForward _forward;

  @override
  String get host => _forward.host;

  @override
  int get port => _forward.port;

  @override
  Stream<DuplexChannel> get connections =>
      _forward.connections.map(DartSsh2Channel.new);

  /// 先自己 await 一次取消请求，再关句柄。
  ///
  /// dartssh2 的 [SSHRemoteForward.close] 内部直接 fire-and-forget 了
  /// `cancelForwardRemote`：如果连接紧接着被关掉（用户断开、会话回收），
  /// 那个没人接的 future 会以 `SSHStateError(SSH client closed)` 结束，
  /// 变成一条未处理异常打到 zone 上（测试里直接判失败，应用里是控制台噪声）。
  /// 这里显式等一次，错误就落在自己的 try 里。
  @override
  Future<void> close() async {
    try {
      await _client.cancelForwardRemote(_forward);
    } on Object {
      // 连接已经断了：取消监听的成败都不影响「转发不存在了」这个结果。
    }
    _forward.close();
  }
}

/// 本地 SOCKS5 代理的适配。
class DartSsh2DynamicForward implements DynamicForwardProxy {
  DartSsh2DynamicForward(this._forward);

  final SSHDynamicForward _forward;

  @override
  String get host => _forward.host;

  @override
  int get port => _forward.port;

  @override
  Future<void> close() => _forward.close();
}
