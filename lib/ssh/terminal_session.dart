import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/core.dart';

import '../models.dart';
import 'host_key_store.dart';
import 'jump_host.dart';
import 'local_files.dart';
import 'port_forward_runtime.dart';
import 'sftp_browser.dart';
import 'ssh_credentials.dart';
import 'ssh_transport.dart';
import 'tunnel_gateway.dart';

enum TerminalPhase { connecting, connected, failed, closed }

/// 会话失败原因归类，供视图层挑选本地化文案；原始错误串随 [TerminalSession.error] 暴露。
enum TerminalErrorKind {
  auth,
  network,
  unsupported,

  /// 主机密钥与已记录指纹不一致（疑似中间人）。
  hostKey,

  /// 已记录的指纹读不出来：存储层故障，不是密钥变了。
  hostKeyStore,

  /// 私钥格式不受支持或口令不对。
  privateKey,

  /// 跳板机链路本身不成立（环、深度超限、跳板机已被删除）。
  /// 与 network / auth 分开：这类问题重试多少次都一样，得去改配置。
  jumpChain,
  other,
}

/// 一个 SSH 终端会话：持有 xterm [Terminal] 缓冲区与生命周期状态。
/// 传输由可注入的 [SshTransport] 完成，便于测试时替换为假实现。
final class TerminalSession extends ChangeNotifier {
  TerminalSession({
    required this.server,
    required this.credentials,
    SshTransport? transport,
    this.hostKeys,
    this.localFiles = const NativeLocalFileGateway(),
    this.allowLegacyHostKeys = false,
    this.jumps = const [],
    TunnelGateway? tunnelGateway,
  }) : _transport =
           transport ??
           createSshTransport(
             server,
             credentials,
             hostKeys,
             allowLegacyHostKeys: allowLegacyHostKeys,
             jumps: jumps,
           ) {
    forwards = PortForwardManager(_transport, gateway: tunnelGateway);
  }

  final SshServer server;
  final SshCredentials credentials;

  /// 跳板机链路（由外到内，不含目标主机本身）；重连时原样复用。
  final List<SshHop> jumps;

  /// TOFU 主机密钥指纹存储；注入空实现可跳过校验（测试场景）。
  final HostKeyStore? hostKeys;

  /// 本地文件交互（上传选择 / 下载落盘），测试中可替换为假实现。
  final LocalFileGateway localFiles;

  /// 是否允许 ssh-rsa（SHA-1）主机密钥；建连时由 [SshTransport] 读取。
  final bool allowLegacyHostKeys;

  final SshTransport _transport;

  /// 端口转发运行时；与 SFTP 一样复用本会话已认证的连接，
  /// 会话结束即随之失效（见 [PortForwardManager]）。
  late final PortForwardManager forwards;

  /// 终端缓冲区（含回滚行），视图层直接渲染。
  final Terminal terminal = Terminal(maxLines: 5000);

  TerminalPhase _phase = TerminalPhase.connecting;
  TerminalErrorKind _errorKind = TerminalErrorKind.other;
  String? _error;

  TerminalPhase get phase => _phase;
  TerminalErrorKind get errorKind => _errorKind;
  String? get error => _error;

  Object? _cause;

  /// 失败原因本体（未字符串化），供界面取结构化信息。
  Object? get cause => _cause;

  /// 主机密钥不一致的详情；仅 [errorKind] 为 hostKey 时非空。
  /// 界面用其中的指纹与服务器实际核对，而不是只看到一句「不匹配」。
  /// 跳板机链路上的不一致被 [SshHopException] 包着，这里一并剥出来——
  /// 不然用户只被告知「失败了」，却拿不到该核对哪台机器的指纹。
  HostKeyChangedException? get hostKeyChanged {
    final cause = _cause;
    if (cause == null) return null;
    final inner = unwrapHopError(cause);
    return inner is HostKeyChangedException ? inner : null;
  }

  /// 失败发生在哪一跳（跳板机的主机名）；不在跳板链路上时为 null。
  /// 界面把它拼进错误文案，用户才知道是三台机器里的哪一台出了问题。
  String? get failedHop {
    final cause = _cause;
    return cause is SshHopException ? cause.hop.name : null;
  }

  /// connecting / connected 视为活跃会话。
  bool get isActive =>
      _phase == TerminalPhase.connecting || _phase == TerminalPhase.connected;

  /// SFTP 面板状态。按需创建：只在用户首次进入 SFTP Tab 时才开通道，
  /// 建立后一直由会话持有，切换 Tab 不会丢失浏览位置或打断传输。
  SftpBrowserController get sftp => _sftp ??= SftpBrowserController(
    openFileSystem: _transport.openSftp,
    localFiles: localFiles,
  );

  SftpBrowserController? _sftp;

  bool _disposed = false;

  Future<void> start() async {
    if (_phase != TerminalPhase.connecting) return;
    try {
      await _transport.attach(
        terminal,
        onConnected: _onConnected,
        onClosed: _onClosed,
      );
    } catch (error) {
      _onFailed(error);
    }
  }

  /// 用户主动断开并结束会话。
  void terminate() {
    if (_phase == TerminalPhase.closed || _phase == TerminalPhase.failed) {
      return;
    }
    _phase = TerminalPhase.closed;
    _transport.dispose();
    forwards.stopAll();
    _notify();
  }

  void _onConnected() {
    if (_disposed || _phase != TerminalPhase.connecting) return;
    _phase = TerminalPhase.connected;
    // 自动启动的转发在连接可用之后才开：传输层没认证完，通道建不起来。
    forwards.startAutoRules(server.forwards);
    _notify();
  }

  void _onClosed() {
    if (_phase != TerminalPhase.connecting &&
        _phase != TerminalPhase.connected) {
      return;
    }
    _phase = TerminalPhase.closed;
    _transport.dispose();
    forwards.stopAll();
    _notify();
  }

  void _onFailed(Object error) {
    if (_phase == TerminalPhase.closed) return;
    _transport.dispose();
    forwards.stopAll();
    _phase = TerminalPhase.failed;
    _errorKind = _classify(error);
    _cause = error;
    _error = error.toString();
    _notify();
  }

  /// dispose 之后不许再通知：传输层关闭连接是异步的，`client.done` 可能在
  /// 会话已经被回收之后才回调进来，那时 notifyListeners() 会直接断言失败
  /// （正是「刚退出登录 / 刚关掉详情页」这种时序）。状态本身照旧更新，
  /// 只是不再往外广播。
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  static TerminalErrorKind _classify(Object error) {
    // 跳板机链路上的失败按真正的原因归类：链路配置本身不成立时才走
    // jumpChain，否则「跳板机认证失败」应当照样给用户「重新输密码」的路。
    if (error is JumpChainException) return TerminalErrorKind.jumpChain;
    final cause = unwrapHopError(error);
    if (cause is SSHAuthFailError || cause is SSHAuthAbortError) {
      return TerminalErrorKind.auth;
    }
    if (cause is HostKeyChangedException) {
      return TerminalErrorKind.hostKey;
    }
    if (cause is HostKeyUnavailableException) {
      return TerminalErrorKind.hostKeyStore;
    }
    if (cause is PrivateKeyUnsupportedException) {
      return TerminalErrorKind.privateKey;
    }
    // 只有 web 的「浏览器没有原始 TCP」才归为平台不支持。不能把任意
    // UnsupportedError 都算进来：dartssh2 对不认识的 PEM 头也抛它。
    if (cause is UnsupportedError) return TerminalErrorKind.unsupported;
    if (cause is TimeoutException ||
        cause is SSHSocketError ||
        cause is SSHDisconnectError) {
      return TerminalErrorKind.network;
    }
    return TerminalErrorKind.other;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sftp?.dispose();
    _sftp = null;
    forwards.dispose();
    _transport.dispose();
    super.dispose();
  }
}
