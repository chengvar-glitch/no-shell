import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/mobile/server_edit_page.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/store.dart';

import 'support/credential_store_fake.dart';

SshServer _server({AuthMethod authMethod = AuthMethod.password}) => SshServer(
  id: 'srv-cred',
  group: '默认分组',
  name: 'cred-host',
  host: '10.0.0.2',
  username: 'root',
  authMethod: authMethod,
);

Future<ServerStore> _pumpEditPage(
  WidgetTester tester, {
  required FakeCredentialStore credentials,
}) async {
  final store = ServerStore(seed: [_server()]);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ServerEditPage(
                    store: store,
                    credentials: credentials,
                    initial: store.byId('srv-cred'),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  // 凭据段在认证方式之后，可能落在 ListView 缓存区外，先滚到它。
  await tester.dragUntilVisible(
    find.text('记住的凭据'),
    find.byType(ListView),
    const Offset(0, -80),
  );
  await tester.pumpAndSettle();
  return store;
}

/// 弹窗内的输入框与确认键（文案是「保存」）；页面表单还有别的输入框和
/// 同名的主保存键，必须按 AlertDialog 范围收窄。
Finder _dialogField() => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(TextFormField),
);

Finder _dialogSaveButton() => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(FilledButton, '保存'),
);

void main() {
  testWidgets('已存密码：显示状态，更换后保存落盘新密码', (tester) async {
    final credentials = FakeCredentialStore();
    await credentials.write(
      'srv-cred',
      const SshCredentials(password: 'old-pw'),
    );
    await _pumpEditPage(tester, credentials: credentials);

    expect(find.text('已记住：密码'), findsOneWidget);

    await tester.tap(find.text('更换…'));
    await tester.pumpAndSettle();
    // 更换弹窗：预填旧密码、没有「记住凭据」开关、确认键是「保存」。
    expect(
      find.descendant(of: _dialogField(), matching: find.text('old-pw')),
      findsOneWidget,
    );
    expect(find.text('记住凭据'), findsNothing);
    await tester.enterText(_dialogField(), 'new-pw');
    await tester.tap(_dialogSaveButton());
    await tester.pumpAndSettle();

    // 待定状态可见，但还没落盘。
    expect(find.text('保存后记住：密码'), findsOneWidget);
    expect(credentials['srv-cred']?.password, 'old-pw');

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(credentials['srv-cred']?.password, 'new-pw');
  });

  testWidgets('更换凭据后取消表单 → 存储里的凭据不动', (tester) async {
    final credentials = FakeCredentialStore();
    await credentials.write(
      'srv-cred',
      const SshCredentials(password: 'old-pw'),
    );
    await _pumpEditPage(tester, credentials: credentials);

    await tester.tap(find.text('更换…'));
    await tester.pumpAndSettle();
    await tester.enterText(_dialogField(), 'new-pw');
    await tester.tap(_dialogSaveButton());
    await tester.pumpAndSettle();
    expect(find.text('保存后记住：密码'), findsOneWidget);

    // 不点页面保存，直接退出。
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(credentials['srv-cred']?.password, 'old-pw');
  });

  testWidgets('清除记住的凭据：保存后从安全存储删除', (tester) async {
    final credentials = FakeCredentialStore();
    await credentials.write(
      'srv-cred',
      const SshCredentials(password: 'old-pw'),
    );
    await _pumpEditPage(tester, credentials: credentials);

    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    expect(find.text('保存后清除记住的凭据'), findsOneWidget);
    expect(credentials['srv-cred'], isNotNull);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(credentials['srv-cred'], isNull);
  });

  testWidgets('未记住凭据：入口是「记住…」，保存后落入安全存储', (tester) async {
    final credentials = FakeCredentialStore();
    await _pumpEditPage(tester, credentials: credentials);

    expect(find.text('未记住凭据'), findsOneWidget);
    await tester.tap(find.text('记住…'));
    await tester.pumpAndSettle();
    await tester.enterText(_dialogField(), 'fresh-pw');
    await tester.tap(_dialogSaveButton());
    await tester.pumpAndSettle();
    expect(find.text('保存后记住：密码'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(credentials['srv-cred']?.password, 'fresh-pw');
  });

  testWidgets('写入失败：如实提示凭据没存上，主机元数据照常保存', (tester) async {
    final credentials = FakeCredentialStore()..failWrite = true;
    final store = await _pumpEditPage(tester, credentials: credentials);

    await tester.tap(find.text('记住…'));
    await tester.pumpAndSettle();
    await tester.enterText(_dialogField(), 'fresh-pw');
    await tester.tap(_dialogSaveButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('凭据保存失败'), findsOneWidget);
    expect(store.byId('srv-cred'), isNotNull);
  });
}
