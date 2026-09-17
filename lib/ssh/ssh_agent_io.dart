/// SSH agent 的原生实现：连 `SSH_AUTH_SOCK` 指向的 Unix 域套接字。
///
/// 范围是 macOS / Linux。Windows 的 OpenSSH agent 是命名管道
/// （`\\.\pipe\openssh-ssh-agent`），dart:io 的 Socket 连不上（需要 FFI
/// 自己走 overlapped I/O），第一版不做——`sshAgentSupported` 对 Windows
/// 返回 false，入口不展示，避免用户选了一个必然失败的认证方式。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'ssh_agent.dart';

/// 本平台是否有可用的 agent 生态（只决定 UI 要不要展示入口）。
bool get sshAgentSupported => Platform.isMacOS || Platform.isLinux;

/// agent 套接字路径；未配置 / 本平台没有 agent 时为 null。
String? get sshAgentSocketPath {
  if (!sshAgentSupported) return null;
  return Platform.environment['SSH_AUTH_SOCK'];
}

/// 连接本机 agent。[socketPath] 供测试显式指定；缺省读 `SSH_AUTH_SOCK`。
Future<SshAgentClient> connectSshAgent({String? socketPath}) async {
  final path = socketPath ?? sshAgentSocketPath;
  if (path == null || path.isEmpty) {
    throw const SshAgentUnavailableException('SSH_AUTH_SOCK is not set');
  }
  final Socket socket;
  try {
    socket = await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
      timeout: const Duration(seconds: 5),
    );
  } on Object catch (error) {
    throw SshAgentUnavailableException('cannot connect to $path: $error');
  }
  return createSshAgentClient(_SocketAgentChannel(socket));
}

final class _SocketAgentChannel implements SshAgentChannel {
  _SocketAgentChannel(this._socket);

  final Socket _socket;

  @override
  Stream<Uint8List> get stream => _socket;

  @override
  void add(List<int> data) {
    try {
      _socket.add(data);
    } on Object {
      // 对端已关：写入失败由 stream 的错误 / done 上报，这里不二次抛。
    }
  }

  @override
  Future<void> close() async {
    _socket.destroy();
  }
}
