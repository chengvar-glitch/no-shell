import 'package:xterm/core.dart';

import '../models.dart';
import 'dartssh2_transport.dart';
import 'host_key_store.dart';
import 'sftp.dart';
import 'ssh_credentials.dart';

/// SSH 传输层：负责建立连接，把远端输出写入 [Terminal]，
/// 并把终端的键盘输入与尺寸变化转发给远端。
/// 生命周期事件通过回调上报，状态机由上层 [TerminalSession] 维护。
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

  /// 关闭连接并释放资源，可安全重复调用。
  void dispose();
}

/// [hostKeys] 为空时不做主机密钥校验，仅测试场景使用。
SshTransport createSshTransport(
  SshServer server,
  SshCredentials credentials,
  HostKeyStore? hostKeys,
) => DartSsh2Transport(server, credentials, hostKeys);
