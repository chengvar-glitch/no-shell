import 'dart:async';

import 'package:xterm/core.dart';

import '../models.dart';
import 'dartssh2_transport.dart';
import 'forward.dart';
import 'host_key_store.dart';
import 'jump_host.dart';
import 'sftp.dart';
import 'ssh_credentials.dart';

/// 转发相关的公共类型（通道 / 监听 / 代理 / 错误归类）随传输层一起对外暴露，
/// 调用方只需这一个 import。
export 'forward.dart';

/// SSH 传输层：负责建立连接，把远端输出写入 [Terminal]，
/// 并把终端的键盘输入与尺寸变化转发给远端。
/// 生命周期事件通过回调上报，状态机由上层 [TerminalSession] 维护。
///
/// 端口转发复用同一个已认证的连接（与 SFTP 同样的取舍）：转发通道是这条
/// 连接上的新 channel，不另建 TCP、不重复认证，会话一断转发自然失效。
abstract interface class SshTransport {
  Future<void> attach(
    Terminal terminal, {
    required void Function() onConnected,
    required void Function() onClosed,
  });

  /// 在同一条连接上开启 SFTP 通道（dartssh2 会复用已认证的连接，
  /// 不额外建 TCP、不重复认证）。连接未建立或服务端未启用 sftp 子系统时
  /// 抛 [SftpException]。
  Future<SftpFileSystem> openSftp();

  /// 打开一条到 [host]:[port] 的直连通道（本地转发的每个入站连接调一次）。
  /// 目标地址是**服务端视角**的地址。
  Future<DuplexChannel> openDirectChannel(String host, int port);

  /// 请求服务端监听 [host]:[port] 并把入站连接交回来（远程转发）。
  /// [port] 为 0 时由服务端分配，实际端口见返回的
  /// [RemoteForwardListener.port]。服务端拒绝监听时抛 [ForwardException]。
  Future<RemoteForwardListener> openRemoteForward({
    required String host,
    required int port,
  });

  /// 在本地起一个 SOCKS5 代理（动态转发）；浏览器没有原始 TCP，
  /// web 上抛 [ForwardException]（kind 为 [ForwardErrorKind.unsupported]）。
  Future<DynamicForwardProxy> openDynamicProxy({
    required String host,
    required int port,
  });

  /// 关闭连接并释放资源，可安全重复调用。
  void dispose();
}

/// [hostKeys] 为空时不做主机密钥校验，仅测试场景使用。
/// [allowLegacyHostKeys] 见 [DartSsh2Transport]。
/// [jumps] 为由外到内的跳板机链路（不含目标主机本身），见 [resolveJumpChain]。
SshTransport createSshTransport(
  SshServer server,
  SshCredentials credentials,
  HostKeyStore? hostKeys, {
  bool allowLegacyHostKeys = false,
  List<SshHop> jumps = const [],
}) => DartSsh2Transport(
  server,
  credentials,
  hostKeys,
  allowLegacyHostKeys,
  jumps,
);

/// 私钥解不出来：PEM 格式不受支持（典型是 PKCS#8 的 `BEGIN PRIVATE KEY`）
/// 或口令不对。
///
/// 必须与 [UnsupportedError] 严格区分：后者在 web 上表示「浏览器没有原始
/// TCP」，而前者换一份密钥就能解决。混在一起会把 macOS 上的密钥格式问题
/// 报成「本平台不支持 SSH」。
final class PrivateKeyUnsupportedException implements Exception {
  const PrivateKeyUnsupportedException(this.detail);

  final String detail;

  @override
  String toString() => 'PrivateKeyUnsupportedException($detail)';
}
