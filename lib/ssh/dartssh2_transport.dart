import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/core.dart';

import '../models.dart';
import 'dartssh2_sftp.dart';
import 'host_key_store.dart';
import 'sftp.dart';
import 'ssh_credentials.dart';
import 'ssh_transport.dart';

/// dartssh2 实现。web 平台下 [SSHSocket.connect] 会在运行时抛出
/// [UnsupportedError]（浏览器没有原始 TCP），由上层统一归类为不支持。
final class DartSsh2Transport implements SshTransport {
  DartSsh2Transport(this._server, this._credentials, [this._hostKeys]);

  static const _connectTimeout = Duration(seconds: 12);

  final SshServer _server;
  final SshCredentials _credentials;

  /// TOFU 指纹存储；为空时不做主机密钥校验（仅测试场景）。
  final HostKeyStore? _hostKeys;

  /// [_verifyHostKey] 无法向 dartssh2 抛自定义异常（回调错误会在传输层
  /// 内部消化），改为记下详情，attach 里再换成更明确的错误抛出。
  HostKeyChangedException? _hostKeyMismatch;

  SSHClient? _client;
  SSHSession? _session;

  /// 已建立但还没交给 [_client] 的连接。用在握手完成到 client 建好之间的
  /// 窗口期：这期间 dispose 只能关到这个 socket，否则它就漏了。
  SSHSocket? _socket;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  bool _disposed = false;

  @override
  Future<void> attach(
    Terminal terminal, {
    required void Function() onConnected,
    required void Function() onClosed,
  }) async {
    final socket = await SSHSocket.connect(
      _server.host,
      _server.port,
      timeout: _connectTimeout,
    );
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
      client = _client = SSHClient(
        socket,
        username: _server.username,
        identities: _identities,
        // 密码认证；OpenSSH 默认开启的 keyboard-interactive 也映射到同一密码。
        onPasswordRequest: () => _credentials.password,
        onUserInfoRequest: (request) {
          final password = _credentials.password;
          if (password == null) return null;
          return List.filled(request.prompts.length, password);
        },
        handshakeTimeout: _connectTimeout,
        // known_hosts / TOFU 指纹校验：首次记录、变更拒绝（见 host_key_store.dart）。
        onVerifyHostKey: _hostKeys == null ? null : _verifyHostKey,
      );
    } on Object {
      // 私钥解析失败之类会在构造 client 时就抛，此时 socket 已经连上了。
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
      throw _hostKeyMismatch ?? SSHHostkeyError('Hostkey verification failed');
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

  Future<bool> _verifyHostKey(String keyType, Uint8List rawFingerprint) async {
    final store = _hostKeys!;
    final fingerprint = utf8.decode(rawFingerprint);
    final decision = await verifyHostKey(
      store,
      host: _server.host,
      port: _server.port,
      keyType: keyType,
      fingerprint: fingerprint,
    );
    if (decision == HostKeyDecision.mismatch) {
      _hostKeyMismatch = HostKeyChangedException(
        host: _server.host,
        port: _server.port,
        keyType: keyType,
        fingerprint: fingerprint,
      );
      return false;
    }
    return true;
  }

  List<SSHIdentity> get _identities {
    final pem = _credentials.privateKey;
    if (pem == null || pem.isEmpty) return const [];
    return SSHKeyPair.fromPem(pem, _credentials.passphrase);
  }

  @override
  Future<SftpFileSystem> openSftp() async {
    final client = _client;
    if (client == null || _disposed) {
      throw const SftpException(
        SftpErrorKind.network,
        'SSH connection is not established',
      );
    }
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
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _closeQuietly();
  }

  /// 关掉当前持有的一切：已建好的 client，或只连上、还没交给 client 的 socket。
  /// 三处清理路径（dispose 与两种失败）都走它，避免漏掉中间态的 socket。
  void _closeQuietly() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _session?.close();
    final client = _client;
    if (client != null) {
      client.close();
      return;
    }
    // client 还没建起来时，socket 是唯一持有的资源。
    unawaited(_socket?.close());
  }
}
