import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:no_shell/host_portable.dart';
import 'package:no_shell/host_transfer.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/ssh/local_files.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/store.dart';

import 'support/credential_store_fake.dart';
import 'support/sftp_fakes.dart';

void main() {
  group('文本解析：中英文 key 均可识别', () {
    test('用户示例格式（中文 key）', () {
      final drafts = parseHostsText(
        '名称: fofo\n地址: 192.0.2.10\n端口: 22\n用户: root\n密码: demo-pass-123',
        defaultGroup: '导入',
      );
      expect(drafts, hasLength(1));
      expect(drafts.first.name, 'fofo');
      expect(drafts.first.host, '192.0.2.10');
      expect(drafts.first.port, 22);
      expect(drafts.first.username, 'root');
      expect(drafts.first.password, 'demo-pass-123');
      expect(drafts.first.group, '导入');
    });

    test('英文 key 大小写不敏感', () {
      final drafts = parseHostsText(
        'Name: web\nAddress: 10.0.0.1\nPort: 2222\nUser: deploy\nPASSWORD: p1',
        defaultGroup: 'g',
      );
      expect(drafts, hasLength(1));
      expect(drafts.first.name, 'web');
      expect(drafts.first.host, '10.0.0.1');
      expect(drafts.first.port, 2222);
      expect(drafts.first.username, 'deploy');
      expect(drafts.first.password, 'p1');
    });

    test('全角冒号与多余空白', () {
      final drafts = parseHostsText(
        '名称： web2\n地址： 192.168.1.1 ： ',
        defaultGroup: 'g',
      );
      expect(drafts, hasLength(1));
      expect(drafts.first.name, 'web2');
      // 值中的全角冒号不再切分，整段保留。
      expect(drafts.first.host, '192.168.1.1 ：');
    });

    test('空行分块 + 注释行 + 缺省值', () {
      final drafts = parseHostsText(
        '# 服务器清单\n'
        '地址: 10.0.0.2\n'
        '端口: abc\n'
        '\n'
        'Name: db\nHost: 10.0.0.3\nUser: postgres\n',
        defaultGroup: '默认分组',
      );
      expect(drafts, hasLength(2));
      // 缺名称/用户名回退为地址，端口非法回落 22。
      expect(drafts[0].name, '10.0.0.2');
      expect(drafts[0].username, '10.0.0.2');
      expect(drafts[0].port, 22);
      expect(drafts[0].password, isNull);
      expect(drafts[0].group, '默认分组');
      expect(drafts[1].port, 22);
    });

    test('分组 key 与端口越界', () {
      final drafts = parseHostsText(
        '地址: 10.0.0.4\n分组: 生产环境\n端口: 99999',
        defaultGroup: 'g',
      );
      expect(drafts.single.group, '生产环境');
      expect(drafts.single.port, 22);
    });

    test('没有地址的块被忽略', () {
      final drafts = parseHostsText('名称: 孤块\n端口: 22', defaultGroup: 'g');
      expect(drafts, isEmpty);
    });
  });

  group('导出编码与回环', () {
    test('固定中文 key 导出，无密码不出密码行，可再解析回来', () {
      final text = encodeHostsText([
        (
          server: SshServer(
            id: 'a',
            group: '生产',
            name: 'fofo',
            host: '192.0.2.10',
            username: 'root',
          ),
          password: null,
        ),
        (
          server: SshServer(
            id: 'b',
            group: '',
            name: 'api',
            host: '10.0.1.20',
            port: 2222,
            username: 'ops',
          ),
          password: 'secret',
        ),
      ]);

      expect(text.contains('密码: secret'), isTrue);
      expect(text.contains('密码: null'), isFalse);
      expect(text.contains('分组: 生产'), isTrue);
      // 空分组不输出分组行。
      expect('分组:'.allMatches(text), hasLength(1));

      final drafts = parseHostsText(text, defaultGroup: '导入');
      expect(drafts, hasLength(2));
      expect(drafts[0].host, '192.0.2.10');
      // 分组随导出保留，不落到默认分组。
      expect(drafts[0].group, '生产');
      expect(drafts[0].password, isNull);
      expect(drafts[1].port, 2222);
      expect(drafts[1].password, 'secret');
    });
  });

  group('ServerStore.importServers', () {
    test('新增去重：与列表、与批次内部重复都跳过，无新增不通知', () {
      final store = ServerStore(
        seed: [
          SshServer(
            id: 'a',
            group: 'g',
            name: 'a',
            host: '10.0.0.1',
            username: 'root',
          ),
        ],
      );
      var notifications = 0;
      store.addListener(() => notifications++);

      final added = store.importServers([
        SshServer(
          id: 'b',
          group: 'g',
          name: 'b',
          host: '10.0.0.1',
          username: 'root',
        ),
        SshServer(
          id: 'c',
          group: 'g',
          name: 'c',
          host: '10.0.0.2',
          port: 22,
          username: 'ops',
        ),
        SshServer(
          id: 'd',
          group: 'g',
          name: 'd',
          host: '10.0.0.2',
          port: 22,
          username: 'ops',
        ),
      ]);

      expect(added.map((s) => s.id), ['c']);
      expect(store.serverCount, 2);
      expect(notifications, 1);

      expect(store.importServers(const []), isEmpty);
      expect(notifications, 1);
    });
  });

  group('导入 / 导出流程', () {
    late ServerStore store;
    late FakeCredentialStore credentials;
    late FakeLocalFileGateway gateway;
    late BuildContext context;

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (builderContext) {
                context = builderContext;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    }

    setUp(() {
      // 空列表起步，不掺入默认播种的示例主机。
      store = ServerStore(seed: const []);
      credentials = FakeCredentialStore();
      gateway = FakeLocalFileGateway();
    });

    LocalUpload textUpload(String content) {
      final bytes = Uint8List.fromList(utf8.encode(content));
      return LocalUpload(
        name: 'hosts.txt',
        length: bytes.length,
        openRead: () => Stream.value(bytes),
      );
    }

    testWidgets('导入：写入主机与记住的密码，汇报新增数', (tester) async {
      await pump(tester);
      gateway.uploads = [
        textUpload(
          '名称: fofo\n地址: 192.0.2.10\n端口: 22\n用户: root\n密码: demo-pass-123',
        ),
      ];

      await importHostsFlow(
        context,
        store: store,
        credentials: credentials,
        localFiles: gateway,
      );
      await tester.pump();

      expect(store.serverCount, 1);
      final imported = store.servers.single;
      expect(imported.host, '192.0.2.10');
      expect(imported.authMethod, AuthMethod.password);
      expect(credentials[imported.id]?.password, 'demo-pass-123');
      expect(find.text('已导入 1 台主机'), findsOneWidget);
    });

    testWidgets('导入：重复条目跳过并汇报', (tester) async {
      store.upsert(
        SshServer(
          id: 'a',
          group: 'g',
          name: 'old',
          host: '192.0.2.10',
          username: 'root',
        ),
      );
      await pump(tester);
      gateway.uploads = [textUpload('地址: 192.0.2.10\n用户: root')];

      await importHostsFlow(
        context,
        store: store,
        credentials: credentials,
        localFiles: gateway,
      );
      await tester.pump();

      expect(store.serverCount, 1);
      expect(find.text('已跳过 1 台重复主机'), findsOneWidget);
    });

    testWidgets('导入：无可识别条目给出提示', (tester) async {
      await pump(tester);
      gateway.uploads = [textUpload('随便写点什么')];

      await importHostsFlow(
        context,
        store: store,
        credentials: credentials,
        localFiles: gateway,
      );
      await tester.pump();

      expect(store.serverCount, 0);
      expect(find.text('未识别到有效主机条目，请检查文件格式'), findsOneWidget);
    });

    testWidgets('导出：含记住的密码写入所选文件', (tester) async {
      final server = SshServer(
        id: 'srv-1',
        group: 'g',
        name: 'fofo',
        host: '192.0.2.10',
        username: 'root',
      );
      store.upsert(server);
      await credentials.write(
        'srv-1',
        const SshCredentials(password: 'demo-pass-123'),
      );
      await pump(tester);
      gateway.downloadTarget = const LocalTarget(
        path: '/tmp/hosts.txt',
        name: 'hosts.txt',
      );

      await exportHostsFlow(
        context,
        store: store,
        credentials: credentials,
        localFiles: gateway,
      );
      await tester.pump();

      final text = utf8.decode(gateway.bytesOf('/tmp/hosts.txt'));
      expect(text, contains('名称: fofo'));
      expect(text, contains('地址: 192.0.2.10'));
      expect(text, contains('用户: root'));
      expect(text, contains('密码: demo-pass-123'));
      expect(find.text('已导出 1 台主机'), findsOneWidget);
    });

    testWidgets('导出：取消保存位置时不写文件', (tester) async {
      store.upsert(
        SshServer(
          id: 'a',
          group: 'g',
          name: 'a',
          host: '10.0.0.1',
          username: 'root',
        ),
      );
      await pump(tester);
      gateway.downloadTarget = null;

      await exportHostsFlow(
        context,
        store: store,
        credentials: credentials,
        localFiles: gateway,
      );
      await tester.pump();

      expect(gateway.written, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
