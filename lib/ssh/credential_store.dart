/// 凭据安全存储抽象：按主机 id 存取「记住凭据」勾选后落盘的认证信息。
/// 实现按平台条件导出 —— 原生端走系统安全存储（钥匙串 / Keystore / DPAPI /
/// libsecret），web 无安全存储由桩兜底（web 也无法建立 SSH 连接）。
/// 与 local_write.dart 相同的条件导出模式，保证 `lib/` 不直接触碰平台通道。
library;

export 'credential_store_stub.dart'
    if (dart.library.io) 'credential_store_io.dart';

import 'ssh_credentials.dart';

abstract interface class CredentialStore {
  /// 当前平台是否支持持久化凭据；不支持时 UI 隐藏「记住凭据」入口。
  bool get supported;

  /// 读取某主机已保存的凭据；无存档或存档损坏返回 null。
  Future<SshCredentials?> read(String serverId);

  Future<void> write(String serverId, SshCredentials credentials);

  Future<void> delete(String serverId);
}
