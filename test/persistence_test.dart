import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/server_persistence.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/store.dart';

/// 内存落盘通道假实现：记录保存次数，供断言「变更后落盘」。
final class FakeServerPersistence implements ServerPersistence {
  List<SshServer>? stored;
  int saveCount = 0;

  @override
  Future<List<SshServer>?> load() async => stored;

  @override
  Future<void> save(List<SshServer> servers) async {
    saveCount++;
    stored = List.of(servers);
  }
}

SshServer _fullServer() => SshServer(
  id: 'srv-x',
  group: '生产环境',
  name: 'web-1',
  host: '10.0.0.1',
  username: 'deploy',
  port: 2222,
  authMethod: AuthMethod.password,
  tags: const ['web', 'nginx'],
  notes: '示例备注',
  lastConnectedAt: DateTime.parse('2026-01-02T03:04:05.000'),
);

void main() {
  group('SshCredentials 序列化', () {
    test('完整字段 roundtrip', () {
      const credentials = SshCredentials(
        password: 'pw',
        privateKey: '---KEY---',
        passphrase: 'pp',
      );
      final restored = SshCredentials.tryDecode(credentials.encode());
      expect(restored?.password, 'pw');
      expect(restored?.privateKey, '---KEY---');
      expect(restored?.passphrase, 'pp');
    });

    test('空凭据与损坏输入安全兜底', () {
      expect(SshCredentials.tryDecode(null), isNull);
      expect(SshCredentials.tryDecode('not-json'), isNull);
      final empty = SshCredentials.tryDecode('{}');
      expect(empty?.password, isNull);
      expect(empty?.privateKey, isNull);
      expect(empty?.passphrase, isNull);
    });
  });

  group('SshServer 序列化', () {
    test('全字段 roundtrip，status 不入档', () {
      final json = _fullServer().toJson();
      expect(json.containsKey('status'), isFalse);

      final restored = SshServer.fromJson(json);
      expect(restored.id, 'srv-x');
      expect(restored.group, '生产环境');
      expect(restored.name, 'web-1');
      expect(restored.host, '10.0.0.1');
      expect(restored.username, 'deploy');
      expect(restored.port, 2222);
      expect(restored.authMethod, AuthMethod.password);
      expect(restored.tags, ['web', 'nginx']);
      expect(restored.notes, '示例备注');
      expect(
        restored.lastConnectedAt,
        DateTime.parse('2026-01-02T03:04:05.000'),
      );
      // 运行时状态载入后统一回到 idle。
      expect(restored.status, ServerStatus.idle);
    });

    test('缺省键回落默认值', () {
      final server = SshServer.fromJson({
        'id': 'srv-min',
        'group': 'g',
        'name': 'n',
        'host': 'h',
        'username': 'u',
      });
      expect(server.port, 22);
      expect(server.authMethod, AuthMethod.privateKey);
      expect(server.tags, isEmpty);
      expect(server.notes, isNull);
      expect(server.lastConnectedAt, isNull);
      expect(server.status, ServerStatus.idle);
    });
  });

  group('SharedPreferencesServerPersistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('无存档时 load 返回 null', () async {
      final persistence = SharedPreferencesServerPersistence();
      expect(await persistence.load(), isNull);
    });

    test('save → load roundtrip', () async {
      final persistence = SharedPreferencesServerPersistence();
      const second = SshServer(
        id: 'srv-01',
        group: 'g',
        name: 'n',
        host: 'h',
        username: 'u',
      );
      await persistence.save([_fullServer(), second]);

      final loaded = await persistence.load();
      expect(loaded, hasLength(2));
      expect(loaded?[0].toJson(), _fullServer().toJson());
      expect(loaded?[1].id, 'srv-01');
    });

    test('存档损坏时 load 返回 null（下次保存覆盖）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ssh_servers_v1': 'not-json',
      });
      final persistence = SharedPreferencesServerPersistence();
      expect(await persistence.load(), isNull);
    });

    test('单条记录损坏只跳过该条，其余照常读回', () async {
      final good = _fullServer().toJson();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ssh_servers_v1': jsonEncode([
          good,
          {'host': '缺 id 的坏记录'},
          'not-a-map',
        ]),
      });
      final persistence = SharedPreferencesServerPersistence();
      final loaded = await persistence.load();
      expect(loaded, hasLength(1));
      expect(loaded?[0].toJson(), good);
    });
  });

  group('ServerStore 持久化', () {
    test('默认构造不落盘，load 为 no-op', () async {
      final store = ServerStore();
      await store.load();
      store.upsert(_fullServer());
      expect(store.serverCount, 1);
      store.remove('srv-x');
      expect(store.serverCount, 0);
    });

    test('首次运行（无存档）写入空列表基线', () async {
      final persistence = FakeServerPersistence();
      final store = ServerStore(persistence: persistence);

      await store.load();

      expect(store.serverCount, 0);
      expect(persistence.saveCount, 1);
      expect(persistence.stored, hasLength(0));
    });

    test('有存档时以存档替换内存列表', () async {
      final persistence = FakeServerPersistence()..stored = [_fullServer()];
      final store = ServerStore(persistence: persistence);

      await store.load();

      expect(store.serverCount, 1);
      expect(store.byId('srv-x')?.name, 'web-1');
      expect(store.byId('srv-x')?.status, ServerStatus.idle);
    });

    test('增删改后异步落盘', () async {
      final persistence = FakeServerPersistence();
      final store = ServerStore(persistence: persistence);
      await store.load();

      store.upsert(_fullServer());
      await pumpEventQueue();
      expect(persistence.saveCount, greaterThan(1));
      expect(persistence.stored?.any((s) => s.id == 'srv-x'), isTrue);

      store.remove('srv-x');
      await pumpEventQueue();
      expect(persistence.stored?.any((s) => s.id == 'srv-x'), isFalse);

      store.restore(_fullServer(), 0);
      await pumpEventQueue();
      expect(persistence.stored?.first.id, 'srv-x');
    });

    test('markConnected 记录的最近连接时间会落盘', () async {
      final persistence = FakeServerPersistence();
      final store = ServerStore(
        persistence: persistence,
        seed: [_fullServer()],
      );
      await store.load();

      store.markConnected('srv-x');
      await pumpEventQueue();

      expect(persistence.stored?.first.lastConnectedAt, isNotNull);
    });
  });
}
