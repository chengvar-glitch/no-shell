import 'dart:convert';
import 'dart:io';

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
  SecureCredentialStore({FlutterSecureStorage? storage, bool? singleItem})
    : _storage = storage ?? const FlutterSecureStorage(),
      _singleItem = singleItem ?? Platform.isMacOS;

  final FlutterSecureStorage _storage;

  /// macOS 的钥匙串 ACL 是「每个条目一份」。ad-hoc 签名的新构建会被钥匙串
  /// 当成陌生应用；如果每台主机各占一个条目，就要逐台点授权。macOS 把所有
  /// 主机放进同一个条目，新构建最多只授权一次。
  ///
  /// 其它平台没有这个 ACL 行为（Android / Windows / Linux 不逐条目弹授权），
  /// 继续按主机分条存取，避免一次读写牵动所有凭据。
  final bool _singleItem;

  /// 上一版每台主机一个 key。macOS 会懒迁移：用到哪台就把那一台搬进聚合
  /// 条目，不去一次性碰所有旧条目（那会又变成逐条目弹授权）。
  static const _legacyKeyPrefix = 'ssh_cred_';
  static const _bundleKey = 'ssh_credentials_v1';

  static String _legacyKey(String serverId) => '$_legacyKeyPrefix$serverId';

  /// 串行排队聚合档的读改写。凭据弹窗与跳板机链路可能连续写多台主机，
  /// 聚合档是单个 JSON 对象，并发读改写会让后写的一方覆盖掉先写的一方。
  Future<void> _queue = Future.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final operation = _queue.then((_) => action());
    _queue = operation.then((_) {}, onError: (_) {});
    return operation;
  }

  /// 诊断输出：只在 debug 构建里打。异常串是第三方插件给的、内容不受本仓库
  /// 控制，release 下不该把与凭据相关的调试信息写进系统日志。
  static void _log(String message) {
    if (kDebugMode) debugPrint('CredentialStore.$message');
  }

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

  /// 读聚合档；返回 `null` 表示「没有聚合档」，与 JSON 损坏共用同一兜底。
  Future<Map<String, String>?> _readBundle() async {
    final raw = await _storage.read(
      key: _bundleKey,
      iOptions: _iosOptions,
      mOptions: _macosOptions,
    );
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('credential bundle is not an object');
    }
    return decoded.map(
      (key, value) => MapEntry(key as String, value as String),
    );
  }

  Future<void> _writeBundle(Map<String, String> entries) async {
    await _storage.write(
      key: _bundleKey,
      value: jsonEncode(entries),
      iOptions: _iosOptions,
      mOptions: _macosOptions,
    );
  }

  @override
  Future<SshCredentials?> read(String serverId) {
    return _serialized(() async {
      try {
        final entries = await _readBundle();
        if (entries != null && entries.containsKey(serverId)) {
          return SshCredentials.tryDecode(entries[serverId]);
        }

        // 旧版分条档只在当前主机要用到时才读一次；读到后搬进聚合档，让
        // 「以后每个新构建只授权一次」对这台主机立即生效。
        final raw = await _storage.read(
          key: _legacyKey(serverId),
          iOptions: _iosOptions,
          mOptions: _macosOptions,
        );
        final credentials = SshCredentials.tryDecode(raw);
        if (credentials == null || !_singleItem) return credentials;

        final nextEntries = <String, String>{...?entries};
        nextEntries[serverId] = credentials.encode();
        await _writeBundle(nextEntries);
        try {
          await _storage.delete(
            key: _legacyKey(serverId),
            iOptions: _iosOptions,
            mOptions: _macosOptions,
          );
        } catch (_) {
          // 聚合档已写入；旧条目删不掉只是留在钥匙串里，不影响后续读取。
        }
        return credentials;
      } catch (error) {
        // 读不到按「无凭据」降级为弹窗输入；错误打到控制台供诊断，
        // 不然用户会以为存档还在。只在 debug 下打：异常串来自第三方插件，
        // release 下不该让平台日志里出现与凭据相关的调试输出。
        _log('read($serverId) failed: $error');
        return null;
      }
    });
  }

  @override
  Future<bool> write(String serverId, SshCredentials credentials) async {
    if (!_singleItem) {
      try {
        await _storage.write(
          key: _legacyKey(serverId),
          value: credentials.encode(),
          iOptions: _iosOptions,
          mOptions: _macosOptions,
        );
        return true;
      } catch (error) {
        _log('write($serverId) failed: $error');
        return false;
      }
    }

    return _serialized(() async {
      try {
        final entries = await _readBundle() ?? <String, String>{};
        entries[serverId] = credentials.encode();
        await _writeBundle(entries);
        try {
          await _storage.delete(
            key: _legacyKey(serverId),
            iOptions: _iosOptions,
            mOptions: _macosOptions,
          );
        } catch (_) {
          // 新档是权威数据；旧条目删不掉时不把本次保存判为失败。
        }
        return true;
      } catch (error) {
        // 写失败不打断连接（本次会话仍可用内存凭据），但必须如实回报
        // 「没存上」，由界面提示用户——静默失败曾让「记住凭据」形同虚设。
        _log('write($serverId) failed: $error');
        return false;
      }
    });
  }

  @override
  Future<void> delete(String serverId) {
    return _serialized(() async {
      if (!_singleItem) {
        try {
          await _storage.delete(
            key: _legacyKey(serverId),
            iOptions: _iosOptions,
            mOptions: _macosOptions,
          );
        } catch (_) {
          // 键本就不存在或底层不可用都视为已删除。
        }
        return;
      }

      try {
        final entries = await _readBundle();
        if (entries != null && entries.containsKey(serverId)) {
          entries.remove(serverId);
          if (entries.isEmpty) {
            await _storage.delete(
              key: _bundleKey,
              iOptions: _iosOptions,
              mOptions: _macosOptions,
            );
          } else {
            await _writeBundle(entries);
          }
        }
      } catch (error) {
        _log('delete bundle entry($serverId) failed: $error');
      }

      try {
        await _storage.delete(
          key: _legacyKey(serverId),
          iOptions: _iosOptions,
          mOptions: _macosOptions,
        );
      } catch (_) {
        // 键本就不存在或底层不可用都视为已删除。
      }
    });
  }
}

CredentialStore createCredentialStore() => SecureCredentialStore();
