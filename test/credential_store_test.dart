/// 真实凭据存储（`SecureCredentialStore`）的失败契约。
///
/// 调用方一侧早就测过「写失败要提示用户」（`FakeCredentialStore.failWrite`），
/// 但真正的实现这一层没有：钥匙串不可用（权限被拒、插件未注册）时到底是
/// 返回 false、降级为 null，还是把异常抛给连接流程，只有这里能钉住。
/// AGENTS.md 里那句「静默失败曾让『记住凭据』形同虚设」说的就是这条契约。
@TestOn('vm')
library;

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/ssh/credential_store.dart';
import 'package:no_shell/ssh/credential_store_io.dart'
    show SecureCredentialStore;
import 'package:no_shell/ssh/ssh_credentials.dart';

/// 底层一律抛错：模拟钥匙串 / libsecret 不可用。
final class _ThrowingPlatform extends FlutterSecureStoragePlatform {
  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => throw PlatformException(code: 'unavailable');

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async => throw PlatformException(code: 'unavailable');

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => throw PlatformException(code: 'unavailable');

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => throw PlatformException(code: 'unavailable');

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => throw PlatformException(code: 'unavailable');

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      throw PlatformException(code: 'unavailable');
}

/// 内存实现：验证真实存储这一层的编解码往返。
final class _MemoryPlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> values = {};

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => values.containsKey(key);

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async => values[key] = value;

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => values[key];

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async => values.remove(key);

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map.of(values);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      values.clear();
}

void main() {
  const serverId = 'srv-1';

  group('SecureCredentialStore 底层不可用', () {
    setUp(() {
      FlutterSecureStoragePlatform.instance = _ThrowingPlatform();
    });

    test('read 降级为「没有凭据」，不把异常甩给连接流程', () async {
      expect(await SecureCredentialStore().read(serverId), isNull);
    });

    test('write 返回 false，界面据此提示「没存上」', () async {
      final saved = await SecureCredentialStore().write(
        serverId,
        const SshCredentials(password: 'pw'),
      );
      expect(saved, isFalse, reason: '写失败必须如实回报，绝不静默');
    });

    test('delete 不抛：键本就不存在与底层不可用都算已删除', () async {
      await SecureCredentialStore().delete(serverId);
    });
  });

  group('SecureCredentialStore 正常路径', () {
    late _MemoryPlatform platform;

    setUp(() {
      platform = _MemoryPlatform();
      FlutterSecureStoragePlatform.instance = platform;
    });

    test('写进去读得回来，删掉之后读不到', () async {
      final store = SecureCredentialStore(singleItem: false);
      expect(
        await store.write(
          serverId,
          const SshCredentials(password: 'pw', passphrase: 'kp'),
        ),
        isTrue,
      );
      // 值经插件存的是字符串，读回时由 SshCredentials.tryDecode 解析。
      expect(platform.values.keys.single, contains(serverId));

      final loaded = await store.read(serverId);
      expect(loaded?.password, 'pw');
      expect(loaded?.passphrase, 'kp');

      await store.delete(serverId);
      expect(await store.read(serverId), isNull);
      expect(platform.values, isEmpty);
    });

    test('存进去的串解不出来时按「没有凭据」处理，而不是抛异常', () async {
      platform.values['ssh_cred_$serverId'] = 'not-a-credential-payload';
      expect(
        await SecureCredentialStore(singleItem: false).read(serverId),
        isNull,
      );
    });
  });

  group('SecureCredentialStore macOS 聚合档', () {
    late _MemoryPlatform platform;

    setUp(() {
      platform = _MemoryPlatform();
      FlutterSecureStoragePlatform.instance = platform;
    });

    test('多台主机共用同一个钥匙串条目，且读改写互不覆盖', () async {
      final store = SecureCredentialStore(singleItem: true);
      expect(
        await store.write('srv-1', const SshCredentials(password: 'pw-1')),
        isTrue,
      );
      expect(
        await store.write('srv-2', const SshCredentials(privateKey: 'key-2')),
        isTrue,
      );
      expect(platform.values.keys.single, 'ssh_credentials_v1');

      expect((await store.read('srv-1'))?.password, 'pw-1');
      expect((await store.read('srv-2'))?.privateKey, 'key-2');
    });

    test('旧分条档按需迁移，之后读取只走聚合档', () async {
      platform.values['ssh_cred_old'] = const SshCredentials(password: 'legacy')
          .encode();
      final store = SecureCredentialStore(singleItem: true);

      expect((await store.read('old'))?.password, 'legacy');
      expect(platform.values.keys.single, 'ssh_credentials_v1');
      expect((await store.read('old'))?.password, 'legacy');
    });

    test('删除最后一台主机时清掉聚合档，其它主机只删除对应成员', () async {
      final store = SecureCredentialStore(singleItem: true);
      await store.write('srv-1', const SshCredentials(password: 'pw-1'));
      await store.write('srv-2', const SshCredentials(password: 'pw-2'));

      await store.delete('srv-1');
      expect(platform.values.keys.single, 'ssh_credentials_v1');
      expect(await store.read('srv-1'), isNull);
      expect((await store.read('srv-2'))?.password, 'pw-2');

      await store.delete('srv-2');
      expect(platform.values, isEmpty);
    });
  });

  test('supported 为真：原生端一定走系统安全存储，没有「悄悄不存」的分支', () {
    expect(SecureCredentialStore().supported, isTrue);
    expect(createCredentialStore(), isA<SecureCredentialStore>());
  });
}
