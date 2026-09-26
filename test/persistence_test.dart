import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/server_persistence.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/store.dart';

/// 内存落盘通道假实现：记录保存次数，供断言「变更后落盘」。
final class FakeServerPersistence implements ServerPersistence {
  ServerArchive? stored;
  int saveCount = 0;

  /// 非 null 时 [load] 抛出该错误，用来验证「读失败必须停写」。
  Object? loadError;

  @override
  Future<ServerArchiveLoad> load() async {
    final error = loadError;
    if (error != null) throw error;
    final archive = stored;
    return archive == null
        ? const ServerArchiveMissing()
        : ServerArchiveLoaded(archive);
  }

  @override
  Future<void> save(ServerArchive archive) async {
    saveCount++;
    // 与真实实现一致：存快照而不是引用，避免断言到后来才被改的数据。
    stored = ServerArchive(
      servers: List.of(archive.servers),
      groupOrder: List.of(archive.groupOrder),
      collapsedGroups: Set.of(archive.collapsedGroups),
    );
  }
}

/// 取出读回的存档；结果不是「读到了」时直接失败，省得每处都写模式匹配。
ServerArchive? _loadedArchive(ServerArchiveLoad result) =>
    result is ServerArchiveLoaded ? result.archive : null;

ServerArchive _archive(
  List<SshServer> servers, {
  List<String> groups = const [],
  Set<String> collapsed = const {},
}) => ServerArchive(
  servers: servers,
  groupOrder: groups,
  collapsedGroups: collapsed,
);

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

    test('Agent 认证：凭据标记与 authMethod roundtrip', () {
      const credentials = SshCredentials(useAgent: true);
      final restored = SshCredentials.tryDecode(credentials.encode());
      expect(restored?.useAgent, isTrue);
      // 普通凭据不带这个标记。
      expect(
        SshCredentials.tryDecode(const SshCredentials(password: 'pw').encode())
            ?.useAgent,
        isFalse,
      );

      final server = SshServer.fromJson({
        ..._fullServer().toJson(),
        'authMethod': 'agent',
      });
      expect(server.authMethod, AuthMethod.agent);
      expect(server.toJson()['authMethod'], 'agent');
    });
  });

  group('SharedPreferencesServerPersistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('无存档时 load 报「从未保存过」', () async {
      final persistence = SharedPreferencesServerPersistence();
      expect(await persistence.load(), isA<ServerArchiveMissing>());
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
      await persistence.save(_archive([_fullServer(), second]));

      final loaded = _loadedArchive(await persistence.load());
      expect(loaded?.servers, hasLength(2));
      expect(loaded?.servers[0].toJson(), _fullServer().toJson());
      expect(loaded?.servers[1].id, 'srv-01');
    });

    test('存档损坏时报「读不出来」，不再冒充首次运行', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ssh_servers_v1': 'not-json',
      });
      final persistence = SharedPreferencesServerPersistence();
      // 关键区别：null 会被调用方当成首次运行、进而写空列表覆盖掉，
      // 所以损坏必须有自己的结果类型。
      expect(await persistence.load(), isA<ServerArchiveUnreadable>());
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
      final loaded = _loadedArchive(await persistence.load());
      expect(loaded?.servers, hasLength(1));
      expect(loaded?.servers[0].toJson(), good);
    });

    test('一条转发规则字段类型损坏只跳过该条，主机照常保留', () async {
      // localPort 是字符串：PortForwardRule.fromJson 里的强转会抛 TypeError。
      // 这个 TypeError 必须在 SshServer.fromJson 内部被接住，否则会一路
      // 穿到 server_persistence 的逐主机 catch——整台主机从列表里消失。
      final good = _fullServer().toJson();
      final withForwards = {...good}
        ..['forwards'] = [
          {'id': 'r1', 'mode': 'local', 'localPort': 'abc'},
          {'id': 'r2', 'mode': 'local', 'localPort': 8080},
        ];
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ssh_servers_v1': jsonEncode([withForwards]),
      });
      final persistence = SharedPreferencesServerPersistence();
      final loaded = _loadedArchive(await persistence.load());
      expect(loaded?.servers, hasLength(1));
      expect(loaded?.servers[0].forwards.map((rule) => rule.id), ['r2']);
    });

    test('JSON 存档的端口越界退回 22，与文本格式对齐', () async {
      final badPort = {..._fullServer().toJson()}..['port'] = 99999;
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ssh_servers_v1': jsonEncode([badPort]),
      });
      final persistence = SharedPreferencesServerPersistence();
      final loaded = _loadedArchive(await persistence.load());
      expect(loaded?.servers.single.port, 22);
    });

    test('tags 里的非字符串元素被丢弃，不再带走整台主机', () async {
      final badTags = {..._fullServer().toJson()}..['tags'] = ['ok', 42];
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ssh_servers_v1': jsonEncode([badTags]),
      });
      final persistence = SharedPreferencesServerPersistence();
      final loaded = _loadedArchive(await persistence.load());
      expect(loaded?.servers.single.tags, ['ok']);
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
      // 写入在队列里异步执行，等它跑完再断言。
      await pumpEventQueue();

      expect(store.serverCount, 0);
      expect(persistence.saveCount, 1);
      expect(persistence.stored?.servers, hasLength(0));
    });

    test('有存档时以存档替换内存列表', () async {
      final persistence = FakeServerPersistence()
        ..stored = _archive([_fullServer()], groups: ['生产环境']);
      final store = ServerStore(persistence: persistence);

      await store.load();

      expect(store.serverCount, 1);
      expect(store.byId('srv-x')?.name, 'web-1');
      expect(store.byId('srv-x')?.status, ServerStatus.idle);
    });

    test('存档读不出来时停写，绝不拿残缺列表覆盖', () async {
      final persistence = FakeServerPersistence()
        ..stored = _archive([_fullServer()], groups: ['生产环境']);
      final store = ServerStore(persistence: persistence);
      // 磁盘上的存档解开时炸了（或存档只丢了一半）。
      persistence.loadError = const FormatException('corrupt');

      await store.load();
      expect(store.archiveUnreadable, isTrue);
      final savesBefore = persistence.saveCount;

      // 用户照常操作；这些改动只留在内存里，不能落盘。
      store.upsert(_fullServer());
      store.createGroup('新分组');
      store.remove('srv-x');
      await pumpEventQueue();

      expect(persistence.saveCount, savesBefore, reason: '存档不可读期间一次都不该写盘');
      expect(
        persistence.stored?.servers,
        hasLength(1),
        reason: '磁盘上的原存档必须原封不动',
      );
    });

    test('主机记录损坏时同样停写（不是首次运行）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ssh_servers_v1': 'not-json',
      });
      final store = ServerStore(
        persistence: SharedPreferencesServerPersistence(),
      );

      await store.load();
      expect(store.archiveUnreadable, isTrue);

      store.upsert(_fullServer());
      await pumpEventQueue();

      // 损坏的原档还在，没有被空列表顶掉。
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ssh_servers_v1'), 'not-json');
    });

    test('增删改后异步落盘', () async {
      final persistence = FakeServerPersistence();
      final store = ServerStore(persistence: persistence);
      await store.load();

      store.upsert(_fullServer());
      await pumpEventQueue();
      expect(persistence.saveCount, greaterThan(1));
      expect(persistence.stored?.servers.any((s) => s.id == 'srv-x'), isTrue);

      store.remove('srv-x');
      await pumpEventQueue();
      expect(persistence.stored?.servers.any((s) => s.id == 'srv-x'), isFalse);

      store.restore(_fullServer(), 0);
      await pumpEventQueue();
      expect(persistence.stored?.servers.first.id, 'srv-x');
    });

    test('flush 等到排队中的落盘全部完成', () async {
      final persistence = FakeServerPersistence();
      final store = ServerStore(persistence: persistence);
      await store.load();
      await pumpEventQueue();
      final before = persistence.saveCount;

      // 连着改三次：三次快照串在同一条 future 链上，都还没跑完。
      store.upsert(_fullServer());
      store.createGroup('新分组');
      store.setGroupCollapsed('新分组', true);

      await store.flush();

      expect(persistence.saveCount, greaterThan(before));
      expect(persistence.stored?.collapsedGroups, contains('新分组'));
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

      expect(persistence.stored?.servers.first.lastConnectedAt, isNotNull);
    });
  });
}
