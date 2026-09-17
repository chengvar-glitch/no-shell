import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:no_shell/main.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/server_persistence.dart';
import 'package:no_shell/store.dart';
import 'package:no_shell/widgets/sidebar.dart';

import 'support/credential_store_fake.dart';
import 'support/demo_servers.dart';

SshServer _server(String id, String group) => SshServer(
  id: id,
  group: group,
  name: id,
  host: '10.0.0.$id',
  username: 'root',
);

void main() {
  group('ServerStore 分组', () {
    test('播种数据里的分组按出现次序入册', () {
      final store = ServerStore(
        seed: [_server('a', '生产'), _server('b', '开发'), _server('c', '生产')],
      );
      expect(store.groupNames, ['生产', '开发']);
    });

    test('新建空分组立刻可见；重名与空名被拒', () {
      final store = ServerStore(seed: [_server('a', '生产')]);

      expect(store.createGroup(' 预发 '), isTrue);
      expect(store.groupNames, ['生产', '预发']);
      final groups = store.groups();
      expect(groups.map((group) => group.name), ['生产', '预发']);
      expect(groups.last.servers, isEmpty);

      expect(store.createGroup('生产'), isFalse);
      expect(store.createGroup('   '), isFalse);
      expect(store.groupNames, ['生产', '预发']);
    });

    test('重命名分组：成员与折叠态一起跟着走，重名被拒', () {
      final store = ServerStore(seed: [_server('a', '生产'), _server('b', '开发')]);
      store.setGroupCollapsed('生产', true);

      expect(store.renameGroup('生产', '线上'), isTrue);
      expect(store.groupNames, ['线上', '开发']);
      expect(store.byId('a')?.group, '线上');
      expect(store.groups().first.collapsed, isTrue);
      // 折叠态跟着改名走，旧名字不再残留。
      store.setGroupCollapsed('线上', false);
      store.setGroupCollapsed('生产', true);
      expect(store.groups().first.collapsed, isFalse);

      expect(store.renameGroup('线上', '开发'), isFalse);
      expect(store.renameGroup('线上', '  '), isFalse);
      expect(store.renameGroup('线上', '线上'), isTrue);
      expect(store.groupNames, ['线上', '开发']);
    });

    test('删除分组：有成员时必须给出去向，给出后成员整体迁移', () {
      final store = ServerStore(
        seed: [_server('a', '生产'), _server('b', '生产'), _server('c', '开发')],
      );

      // 有成员却给不出（或给了不存在的）目的地：拒绝删除。
      expect(store.deleteGroup('生产'), isFalse);
      expect(store.deleteGroup('生产', moveTo: '不存在的分组'), isFalse);
      expect(store.deleteGroup('生产', moveTo: '生产'), isFalse);
      expect(store.groupNames, ['生产', '开发']);

      expect(store.deleteGroup('生产', moveTo: '开发'), isTrue);
      expect(store.groupNames, ['开发']);
      expect(store.byId('a')?.group, '开发');
      expect(store.groups().single.servers, hasLength(3));

      // 空分组不需要目的地。
      store.createGroup('空组');
      expect(store.deleteGroup('空组'), isTrue);
      expect(store.groupNames, ['开发']);
    });

    test('分组排序到头即停', () {
      final store = ServerStore(
        seed: [_server('a', '一'), _server('b', '二'), _server('c', '三')],
      );

      expect(store.moveGroup('三', -1), isTrue);
      expect(store.groupNames, ['一', '三', '二']);
      expect(store.moveGroup('一', -1), isFalse);
      expect(store.moveGroup('二', 1), isFalse);
      expect(store.moveGroup('不存在', -1), isFalse);
      expect(store.groupNames, ['一', '三', '二']);
    });

    test('搜索时只留有命中的分组，空分组平时照常显示', () {
      final store = ServerStore(seed: [_server('a', '生产')]);
      store.createGroup('预发');

      expect(store.groups().map((g) => g.name), ['生产', '预发']);
      expect(store.groups(query: '10.0.0.a').map((g) => g.name), ['生产']);
      expect(store.groups(query: '预发'), isEmpty);
      expect(store.groups(query: '没有这个'), isEmpty);
    });

    test('导入的主机自带的分组会入册', () {
      final store = ServerStore();

      store.importServers([_server('a', '导入分组')]);

      expect(store.groupNames, ['导入分组']);
      expect(store.groups().single.servers, hasLength(1));
    });
  });

  group('分组落盘', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('分组顺序与折叠态 roundtrip', () async {
      final persistence = SharedPreferencesServerPersistence();
      await persistence.save(
        ServerArchive(
          servers: [_server('a', '生产')],
          groupOrder: const ['生产', '预发'],
          collapsedGroups: const {'预发'},
        ),
      );

      final loaded = await persistence.load();
      expect(loaded, isA<ServerArchiveLoaded>());
      final archive = (loaded as ServerArchiveLoaded).archive;
      expect(archive.servers.single.group, '生产');
      expect(archive.groupOrder, ['生产', '预发']);
      expect(archive.collapsedGroups, {'预发'});
    });

    test('旧档只有主机数组时按出现次序重建分组，折叠态为空', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ssh_servers_v1':
            '[{"id":"a","group":"生产","name":"a","host":"h","username":"u"},'
            '{"id":"b","group":"开发","name":"b","host":"h","username":"u"}]',
      });
      final store = ServerStore(
        persistence: SharedPreferencesServerPersistence(),
      );

      await store.load();

      expect(store.groupNames, ['生产', '开发']);
      expect(store.groups().every((group) => !group.collapsed), isTrue);
    });

    test('分组布局损坏只丢布局，主机照常读回', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ssh_servers_v1':
            '[{"id":"a","group":"生产","name":"a","host":"h","username":"u"}]',
        'ssh_groups_v1': 'not-json',
      });
      final store = ServerStore(
        persistence: SharedPreferencesServerPersistence(),
      );

      await store.load();

      expect(store.serverCount, 1);
      expect(store.groupNames, ['生产']);
    });

    test('折叠与顺序变更会落盘', () async {
      final store = ServerStore(
        persistence: SharedPreferencesServerPersistence(),
        seed: [_server('a', '生产')],
      );
      store.createGroup('预发');
      store.setGroupCollapsed('预发', true);
      store.moveGroup('预发', -1);
      await pumpEventQueue();

      final loaded = await SharedPreferencesServerPersistence().load();
      final archive = (loaded as ServerArchiveLoaded).archive;
      expect(archive.groupOrder, ['预发', '生产']);
      expect(archive.collapsedGroups, {'预发'});
    });
  });

  group('桌面端分组交互', () {
    Future<ServerStore> pumpDesktop(WidgetTester tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('zh')];
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final store = ServerStore(seed: demoServers);
      await tester.pumpWidget(
        NoShellApp(
          store: store,
          credentials: FakeCredentialStore(),
          agentKeysProbe: () async => false,
        ),
      );
      await tester.pumpAndSettle();
      return store;
    }

    /// 桌面端分组头的「⋯」悬停才出现：先把鼠标挪到该分组那一行，再点它自己的
    /// 那一枚按钮（[index] 是分组在侧边栏里的显示位次）。
    Future<void> openGroupMenu(
      WidgetTester tester,
      String group,
      int index,
    ) async {
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(find.text(group)));
      await tester.pumpAndSettle();

      // 三个分组各有一枚「⋯」；最下面那个在 800x600 的测试窗口里可能已经
      // 滚出视口，所以不要求在台上，只按位次点当前分组那一枚。
      final menus = find.descendant(
        of: find.byType(Sidebar),
        matching: find.byIcon(Icons.more_horiz_rounded, skipOffstage: false),
        skipOffstage: false,
      );
      expect(menus, findsNWidgets(3));
      await tester.tap(menus.at(index));
      await tester.pumpAndSettle();
    }

    testWidgets('新建连接时可以直接输入一个新分组名', (tester) async {
      final store = await pumpDesktop(tester);

      await tester.tap(find.byTooltip('新建连接'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '名称'),
        'staging-1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '主机'),
        '10.0.3.9',
      );
      await tester.enterText(find.widgetWithText(TextFormField, '用户名'), 'ops');
      // 桌面端旧版只有下拉，建不出第二个分组——这里回归的正是这条路径。
      await tester.enterText(
        find.descendant(
          of: find.byType(DropdownMenu<String>),
          matching: find.byType(TextField),
        ),
        '预发环境',
      );
      // 输入下拉框会展开候选菜单，先收起来再点保存。
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(store.groupNames, contains('预发环境'));
      final created = store.groups().firstWhere(
        (group) => group.name == '预发环境',
      );
      expect(created.servers.single.name, 'staging-1');
    });

    testWidgets('分组头「⋯」菜单可重命名分组，成员跟着走', (tester) async {
      final store = await pumpDesktop(tester);

      await openGroupMenu(tester, '生产环境', 0);
      await tester.tap(find.text('重命名分组'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '线上',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(store.groupNames, ['线上', '开发 / 测试', '个人服务器']);
      expect(store.byId('srv-01')?.group, '线上');
    });

    testWidgets('分组头菜单可新建空分组，重名时保存按钮不可点', (tester) async {
      final store = await pumpDesktop(tester);
      final dialogField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      final saveButton = find.widgetWithText(FilledButton, '保存');

      await openGroupMenu(tester, '生产环境', 0);
      await tester.tap(find.text('新建分组'));
      await tester.pumpAndSettle();

      // 与已有分组重名：不给保存，避免建出两个同名分组。
      await tester.enterText(dialogField, '开发 / 测试');
      await tester.pumpAndSettle();
      expect(find.text('同名分组已存在'), findsOneWidget);
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);

      await tester.enterText(dialogField, '预发环境');
      await tester.pumpAndSettle();
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(store.groupNames.last, '预发环境');
      expect(store.groups().last.servers, isEmpty);
    });

    testWidgets('空分组在侧边栏里照样占一行，等着往里放主机', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('zh')];
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final store = ServerStore(seed: [_server('a', '生产')]);
      store.createGroup('预发');
      await tester.pumpWidget(
        NoShellApp(
          store: store,
          credentials: FakeCredentialStore(),
          agentKeysProbe: () async => false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('预发'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('点分组头折叠后主机行收起来，状态记在 store 里', (tester) async {
      final store = await pumpDesktop(tester);
      expect(find.text('db-primary'), findsOneWidget);

      await tester.tap(find.text('开发 / 测试'));
      await tester.pumpAndSettle();

      expect(find.text('db-primary'), findsNothing);
      expect(
        store.groups().firstWhere((group) => group.name == '开发 / 测试').collapsed,
        isTrue,
      );
    });
  });
}
