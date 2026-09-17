import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/core.dart';

import '../models.dart';
import 'host_key_store.dart';
import 'local_files.dart';
import 'sftp_browser.dart';
import 'ssh_credentials.dart';
import 'ssh_transport.dart';

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
  }) : _transport =
           transport ??
           createSshTransport(
             server,
             credentials,
             hostKeys,
             allowLegacyHostKeys: allowLegacyHostKeys,
           );

  final SshServer server;
  final SshCredentials credentials;

  /// TOFU 主机密钥指纹存储；注入空实现可跳过校验（测试场景）。
  final HostKeyStore? hostKeys;

  /// 本地文件交互（上传选择 / 下载落盘），测试中可替换为假实现。
  final LocalFileGateway localFiles;

  /// 是否允许 ssh-rsa（SHA-1）主机密钥；建连时由 [SshTransport] 读取。
  final bool allowLegacyHostKeys;

  final SshTransport _transport;

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
  /// 界面用其中的指纹与服务器实际指纹核对，而不是只看到一句「不匹配」。
  HostKeyChangedException? get hostKeyChanged {
    final cause = _cause;
    return cause is HostKeyChangedException ? cause : null;
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
    notifyListeners();
  }

  void _onConnected() {
    if (_phase != TerminalPhase.connecting) return;
    _phase = TerminalPhase.connected;
    notifyListeners();
  }

  void _onClosed() {
    if (_phase != TerminalPhase.connecting &&
        _phase != TerminalPhase.connected) {
      return;
    }
    _phase = TerminalPhase.closed;
    _transport.dispose();
    notifyListeners();
  }

  void _onFailed(Object error) {
    if (_phase == TerminalPhase.closed) return;
    _transport.dispose();
    _phase = TerminalPhase.failed;
    _errorKind = _classify(error);
    _cause = error;
    _error = error.toString();
    notifyListeners();
  }

  static TerminalErrorKind _classify(Object error) {
    if (error is SSHAuthFailError || error is SSHAuthAbortError) {
      return TerminalErrorKind.auth;
    }
    if (error is HostKeyChangedException) {
      return TerminalErrorKind.hostKey;
    }
    if (error is HostKeyUnavailableException) {
      return TerminalErrorKind.hostKeyStore;
    }
    if (error is PrivateKeyUnsupportedException) {
      return TerminalErrorKind.privateKey;
    }
    // 只有 web 的「浏览器没有原始 TCP」才归为平台不支持。不能把任意
    // UnsupportedError 都算进来：dartssh2 对不认识的 PEM 头也抛它。
    if (error is UnsupportedError) return TerminalErrorKind.unsupported;
    if (error is TimeoutException ||
        error is SSHSocketError ||
        error is SSHDisconnectError) {
      return TerminalErrorKind.network;
    }
    return TerminalErrorKind.other;
  }

  @override
  void dispose() {
    _sftp?.dispose();
    _sftp = null;
    _transport.dispose();
    super.dispose();
  }
}
