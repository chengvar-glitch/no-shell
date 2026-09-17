import 'package:flutter/foundation.dart';
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

  /// macOS 必须走经典登录钥匙串：插件的「数据保护钥匙串」（iOS 式）要求
  /// application-identifier（团队签名）才能访问，ad-hoc 本地签名下写入
  /// 一律报 -34018——凭据会静默存不进去。
  static const _macosOptions = MacOsOptions(
    accessibility: KeychainAccessibility.unlocked_this_device,
    usesDataProtectionKeychain: false,
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
    } catch (error) {
      // 读不到按「无凭据」降级为弹窗输入；错误打到控制台供诊断，
      // 不然用户会以为存档还在。
      debugPrint('CredentialStore.read($serverId) failed: $error');
      return null;
    }
  }

  @override
  Future<bool> write(String serverId, SshCredentials credentials) async {
    try {
      await _storage.write(
        key: _key(serverId),
        value: credentials.encode(),
        iOptions: _iosOptions,
        mOptions: _macosOptions,
      );
      return true;
    } catch (error) {
      // 写失败不打断连接（本次会话仍可用内存凭据），但必须如实回报
      // 「没存上」，由界面提示用户——静默失败曾让「记住凭据」形同虚设。
      debugPrint('CredentialStore.write($serverId) failed: $error');
      return false;
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
