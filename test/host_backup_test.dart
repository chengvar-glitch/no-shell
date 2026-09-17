import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:no_shell/host_backup.dart';
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
  const hostsText =
      '名称: prod\n'
      '地址: 192.0.2.10\n'
      '端口: 2222\n'
      '用户: deploy\n'
      '密码: s3cret-pass\n'
      '分组: 生产\n'
      '\n'
      '名称: dev\n'
      '地址: 198.51.100.7\n'
      '端口: 22\n'
      '用户: root\n'
      '分组: 测试\n';

  group('备份信封', () {
    test('往返：解出来的清单文本与原文一致', () async {
      final contents = encodeHostsBackup(hostsText, 'correct horse battery');

      expect(decodeHostsBackup(contents, 'correct horse battery'), hostsText);
    });

    test('信封只带密文，明文与口令都不出现在文件里', () async {
      final contents = encodeHostsBackup(hostsText, 'correct horse battery');
      final decoded = jsonDecode(contents) as Map<String, Object?>;

      expect(decoded.keys, containsAll(['scheme', 'version', 'salt', 'nonce']));
      expect(contents, isNot(contains('s3cret-pass')));
      expect(contents, isNot(contains('192.0.2.10')));
      expect(contents, isNot(contains('correct horse battery')));
    });

    test('每次加密都用新的盐与随机数', () async {
      final first = jsonDecode(encodeHostsBackup(hostsText, 'pw-123456'));
      final second = jsonDecode(encodeHostsBackup(hostsText, 'pw-123456'));

      expect(first['salt'], isNot(second['salt']));
      expect(first['nonce'], isNot(second['nonce']));
      expect(first['payload'], isNot(second['payload']));
    });

    test('口令不对报 wrongPassword', () {
      final contents = encodeHostsBackup(hostsText, 'right-password');

      expect(
        () => decodeHostsBackup(contents, 'wrong-password'),
        throwsA(
          isA<BackupFormatException>().having(
            (error) => error.problem,
            'problem',
            BackupProblem.wrongPassword,
          ),
        ),
      );
    });

    test('被改动的密文解不出来', () {
      final decoded = jsonDecode(encodeHostsBackup(hostsText, 'pw-123456'));
      final payload = base64.decode(decoded['payload'] as String);
      payload[0] ^= 0xff;
      decoded['payload'] = base64.encode(payload);

      // 认证标签对不上：和口令不对是同一种失败，不会解出乱码。
      expect(
        () => decodeHostsBackup(jsonEncode(decoded), 'pw-123456'),
        throwsA(
          isA<BackupFormatException>().having(
            (error) => error.problem,
            'problem',
            BackupProblem.wrongPassword,
          ),
        ),
      );
    });

    test('文件识别：备份认得出，主机清单与空文件认不出', () async {
      expect(isHostsBackup(encodeHostsBackup(hostsText, 'pw-123456')), isTrue);
      expect(isHostsBackup(hostsText), isFalse);
      expect(isHostsBackup(''), isFalse);
      expect(isHostsBackup('{}'), isFalse);
      expect(isHostsBackup('[1, 2, 3]'), isFalse);
      expect(isHostsBackup('{"scheme":"no-shell-hosts"}'), isFalse);
    });

    test('版本、迭代次数与字段长度不合规一律判为不可读', () async {
      final base = jsonDecode(
        encodeHostsBackup(hostsText, 'pw-123456'),
      ) as Map<String, Object?>;
      Map<String, Object?> clone() => Map<String, Object?>.of(base);

      final oddVersion = clone()..['version'] = 99;
      final hugeIterations = clone()..['iterations'] = 50000000;
      final tinyIterations = clone()..['iterations'] = 1;
      final shortSalt = clone()..['salt'] = base64.encode(const [1, 2, 3]);
      final emptyPayload = clone()..['payload'] = '';

      for (final broken in [
        oddVersion,
        hugeIterations,
        tinyIterations,
        shortSalt,
        emptyPayload,
      ]) {
        expect(isHostsBackup(jsonEncode(broken)), isFalse);
      }
    });

    test('空清单也能往返：解出来是空文本', () async {
      final contents = encodeHostsBackup('', 'pw-123456');
      expect(decodeHostsBackup(contents, 'pw-123456'), '');
    });
  });

  group('加密备份流程', () {
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

    LocalUpload uploadOf(String content) {
      final bytes = utf8.encode(content);
      return LocalUpload(
        name: 'no-shell-hosts-backup.nsbak',
        length: bytes.length,
        openRead: () => Stream.value(bytes),
      );
    }

    /// 导出：在口令弹窗里填口令并确认。
    Future<void> confirmExportDialog(
      WidgetTester tester,
      String password,
    ) async {
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, password);
      await tester.enterText(find.byType(TextFormField).last, password);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '导出'));
      await tester.pumpAndSettle();
    }

    /// 导入：在口令弹窗里填口令并确认。
    Future<void> confirmImportDialog(
      WidgetTester tester,
      String password,
    ) async {
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, password);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '导入'));
      await tester.pumpAndSettle();
    }

    setUp(() {
      store = ServerStore(seed: const []);
      credentials = FakeCredentialStore();
      gateway = FakeLocalFileGateway();
      gateway.downloadTarget = const LocalTarget(
        path: '/tmp/backup.nsbak',
        name: 'backup.nsbak',
      );
    });

    testWidgets('导出：写出加密文件，明文密码不落地', (tester) async {
      final plain = SshServer(
        id: 'srv-1',
        group: '生产',
        name: 'prod',
        host: '192.0.2.10',
        username: 'deploy',
        port: 2222,
        authMethod: AuthMethod.password,
      );
      store.upsert(plain);
      await credentials.write(plain.id, const SshCredentials(password: 'pw'));

      await pump(tester);
      final exporting = exportHostsBackupFlow(
        context,
        store: store,
        credentials: credentials,
        localFiles: gateway,
      );
      await confirmExportDialog(tester, 'file-password');
      await exporting;

      final written = utf8.decode(gateway.bytesOf('/tmp/backup.nsbak'));
      expect(written, isNot(contains('pw')));
      expect(written, isNot(contains('192.0.2.10')));
      expect(isHostsBackup(written), isTrue);
      expect(find.text('已导出 1 台主机'), findsOneWidget);

      // 用同一个口令解密后就是原本的清单。
      final text = decodeHostsBackup(written, 'file-password');
      final drafts = parseHostsText(text, defaultGroup: '默认');
      expect(drafts, hasLength(1));
      expect(drafts.single.host, '192.0.2.10');
      expect(drafts.single.port, 2222);
      expect(drafts.single.username, 'deploy');
      expect(drafts.single.group, '生产');
      expect(drafts.single.password, 'pw');
    });

    testWidgets('导出：两次口令不一致时留在弹窗里，不写文件', (tester) async {
      store.upsert(
        const SshServer(
          id: 'srv-1',
          group: 'g',
          name: 'prod',
          host: '192.0.2.10',
          username: 'deploy',
        ),
      );
      await pump(tester);

      final exporting = exportHostsBackupFlow(
        context,
        store: store,
        credentials: credentials,
        localFiles: gateway,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'one-password');
      await tester.enterText(find.byType(TextFormField).last, 'other-password');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '导出'));
      await tester.pumpAndSettle();

      expect(find.text('两次输入的口令不一致'), findsOneWidget);
      expect(gateway.written, isEmpty);
      expect(find.widgetWithText(FilledButton, '导出'), findsOneWidget);

      // 改成一致后可以正常导出。
      await tester.enterText(find.byType(TextFormField).last, 'one-password');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '导出'));
      await tester.pumpAndSettle();
      await exporting;
      expect(gateway.written, isNotEmpty);
    });

    testWidgets('导出：取消口令弹窗就不产出文件', (tester) async {
      store.upsert(
        const SshServer(
          id: 'srv-1',
          group: 'g',
          name: 'prod',
          host: '192.0.2.10',
          username: 'deploy',
        ),
      );
      await pump(tester);

      final exporting = exportHostsBackupFlow(
        context,
        store: store,
        credentials: credentials,
        localFiles: gateway,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      await exporting;

      expect(gateway.written, isEmpty);
      expect(gateway.discarded, isEmpty);
    });

    testWidgets('导入：解密后写入主机与密码，重复条目跳过', (tester) async {
      await pump(tester);
      final contents = encodeHostsBackup(hostsText, 'file-password');
      gateway.uploads = [uploadOf(contents)];

      final importing = importHostsBackupFlow(
        context,
        store: store,
        credentials: credentials,
        localFiles: gateway,
      );
      await confirmImportDialog(tester, 'file-password');
      await importing;

      expect(store.serverCount, 2);
      final prod = store.servers.first;
      expect(prod.host, '192.0.2.10');
      expect(prod.port, 2222);
      expect(prod.username, 'deploy');
      expect(prod.group, '生产');
      expect(prod.authMethod, AuthMethod.password);
      expect(credentials[prod.id]?.password, 's3cret-pass');
      final dev = store.servers.last;
      expect(dev.host, '198.51.100.7');
      expect(dev.authMethod, AuthMethod.privateKey);
      expect(find.text('已导入 2 台主机'), findsOneWidget);

      // 同一份备份再导一次：两台都是重复，列表不变。
      gateway.uploads = [uploadOf(contents)];
      final second = importHostsBackupFlow(
        context,
        store: store,
        credentials: credentials,
        localFiles: gateway,
      );
      await confirmImportDialog(tester, 'file-password');
      await second;

      expect(store.serverCount, 2);
      expect(find.text('已跳过 2 台重复主机'), findsOneWidget);
    });

    testWidgets('导入：口令不对时提示且不改动列表', (tester) async {
      await pump(tester);
      gateway.uploads = [uploadOf(encodeHostsBackup(hostsText, 'right-one'))];

      final importing = importHostsBackupFlow(
        context,
        store: store,
        credentials: credentials,
        localFiles: gateway,
      );
      await confirmImportDialog(tester, 'wrong-one');
      await importing;

      expect(store.serverCount, 0);
      expect(find.text('备份口令不正确，未导入任何主机'), findsOneWidget);
    });

    testWidgets('导入：不认识的文本文件直接拒绝，不弹口令框', (tester) async {
      await pump(tester);
      gateway.uploads = [uploadOf('名称: prod\n地址: 192.0.2.10\n')];

      await importHostsBackupFlow(
        context,
        store: store,
        credentials: credentials,
        localFiles: gateway,
      );
      await tester.pumpAndSettle();

      expect(store.serverCount, 0);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('该文件不是可读取的 NoShell 备份'), findsOneWidget);
    });

    testWidgets('导入：取消选择文件则什么都不发生', (tester) async {
      await pump(tester);
      gateway.uploads = const [];

      await importHostsBackupFlow(
        context,
        store: store,
        credentials: credentials,
        localFiles: gateway,
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsNothing);
      expect(store.serverCount, 0);
    });

    testWidgets('导出：没有主机时提示且不弹口令框', (tester) async {
      await pump(tester);

      await exportHostsBackupFlow(
        context,
        store: store,
        credentials: credentials,
        localFiles: gateway,
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsNothing);
      expect(gateway.written, isEmpty);
      expect(find.text('没有可导出的主机'), findsOneWidget);
    });

    testWidgets('导出：落盘失败时清掉半成品文件', (tester) async {
      store.upsert(
        const SshServer(
          id: 'srv-1',
          group: 'g',
          name: 'prod',
          host: '192.0.2.10',
          username: 'deploy',
        ),
      );
      gateway.writeError = StateError('disk full');
      await pump(tester);

      final exporting = exportHostsBackupFlow(
        context,
        store: store,
        credentials: credentials,
        localFiles: gateway,
      );
      await confirmExportDialog(tester, 'file-password');
      await exporting;

      expect(gateway.discarded, ['/tmp/backup.nsbak']);
      expect(gateway.written, isEmpty);
      expect(find.text('导出失败，请重试'), findsOneWidget);
    });
  });
}
