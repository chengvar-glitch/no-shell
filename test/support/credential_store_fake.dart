import 'package:no_shell/ssh/credential_store.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';

/// 内存凭据仓库假实现：记录读写次数，供断言「记住 / 清除」行为。
final class FakeCredentialStore implements CredentialStore {
  final Map<String, SshCredentials> _storage = {};

  int writeCount = 0;
  int deleteCount = 0;

  /// 置 true 模拟底层写失败（如钥匙串 entitlement 缺失）。
  bool failWrite = false;

  SshCredentials? operator [](String serverId) => _storage[serverId];

  @override
  bool get supported => true;

  @override
  Future<SshCredentials?> read(String serverId) async => _storage[serverId];

  @override
  Future<bool> write(String serverId, SshCredentials credentials) async {
    writeCount++;
    if (failWrite) return false;
    _storage[serverId] = credentials;
    return true;
  }

  @override
  Future<void> delete(String serverId) async {
    deleteCount++;
    _storage.remove(serverId);
  }
}
