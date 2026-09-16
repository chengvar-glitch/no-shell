import 'credential_store.dart';
import 'ssh_credentials.dart';

/// web 桩：浏览器没有安全存储通道，且 SSH 本就无法在 web 建连，
/// 直接不提供保存能力（UI 据此隐藏「记住凭据」）。
final class UnsupportedCredentialStore implements CredentialStore {
  const UnsupportedCredentialStore();

  @override
  bool get supported => false;

  @override
  Future<SshCredentials?> read(String serverId) async => null;

  @override
  Future<void> write(String serverId, SshCredentials credentials) async {}

  @override
  Future<void> delete(String serverId) async {}
}

CredentialStore createCredentialStore() => const UnsupportedCredentialStore();
