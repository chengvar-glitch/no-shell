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
enum TerminalErrorKind { auth, network, unsupported, hostKey, other }

/// 一个 SSH 终端会话：持有 xterm [Terminal] 缓冲区与生命周期状态。
/// 传输由可注入的 [SshTransport] 完成，便于测试时替换为假实现。
final class TerminalSession extends ChangeNotifier {
  TerminalSession({
    required this.server,
    required this.credentials,
    SshTransport? transport,
    this.hostKeys,
    this.localFiles = const NativeLocalFileGateway(),
  }) : _transport =
           transport ?? createSshTransport(server, credentials, hostKeys);

  final SshServer server;
  final SshCredentials credentials;

  /// TOFU 主机密钥指纹存储；注入空实现可跳过校验（测试场景）。
  final HostKeyStore? hostKeys;

  /// 本地文件交互（上传选择 / 下载落盘），测试中可替换为假实现。
  final LocalFileGateway localFiles;

  final SshTransport _transport;

  /// 终端缓冲区（含回滚行），视图层直接渲染。
  final Terminal terminal = Terminal(maxLines: 5000);

  TerminalPhase _phase = TerminalPhase.connecting;
  TerminalErrorKind _errorKind = TerminalErrorKind.other;
  String? _error;

  TerminalPhase get phase => _phase;
  TerminalErrorKind get errorKind => _errorKind;
  String? get error => _error;

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
