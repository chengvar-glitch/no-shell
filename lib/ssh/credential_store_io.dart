import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'credential_store.dart';
import 'ssh_credentials.dart';

/// 基于 flutter_secure_storage 的凭据存储：
/// macOS / iOS 走钥匙串，Android 走 Keystore，Windows 走 DPAPI，Linux 走 libsecret。
///
/// 读写一律兜底：底层不可用（如钥匙串权限被拒、插件未注册）时按「无凭据」
/// 降级为正常弹窗输入，绝不打断连接流程。
final class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyPrefix = 'ssh_cred_';

  static String _key(String serverId) => '$_keyPrefix$serverId';

  /// 钥匙串条目不跟随备份迁移到新设备。
  ///
  /// Apple 端的默认值是 `unlocked`（`kSecAttrAccessibleWhenUnlocked`），
  /// 那种条目会随加密备份搬到新机器上——SSH 密码不该跟着走。
  /// `unlocked_this_device` 只在能被本机解锁时读出，且明确不参与迁移。
  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.unlocked_this_device,
  );
  static const _macosOptions = MacOsOptions(
    accessibility: KeychainAccessibility.unlocked_this_device,
  );

  @override
  bool get supported => true;

  @override
  Future<SshCredentials?> read(String serverId) async {
    try {
      return SshCredentials.tryDecode(
        await _storage.read(
          key: _key(serverId),
          iOptions: _iosOptions,
          mOptions: _macosOptions,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String serverId, SshCredentials credentials) async {
    try {
      await _storage.write(
        key: _key(serverId),
        value: credentials.encode(),
        iOptions: _iosOptions,
        mOptions: _macosOptions,
      );
    } catch (_) {
      // 保存失败时静默降级：本次会话仍可正常使用内存凭据。
    }
  }

  @override
  Future<void> delete(String serverId) async {
    try {
      await _storage.delete(
        key: _key(serverId),
        iOptions: _iosOptions,
        mOptions: _macosOptions,
      );
    } catch (_) {
      // 键本就不存在或底层不可用都视为已删除。
    }
  }
}

CredentialStore createCredentialStore() => SecureCredentialStore();
