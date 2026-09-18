import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/ssh/credentials_dialog.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';

SshServer _server() => const SshServer(
  id: 'srv-1',
  group: 'g',
  name: 'test-host',
  host: '10.0.0.1',
  username: 'root',
  // 断言聚焦密码分支；私钥分支在「私钥预填」用例中单独覆盖。
  authMethod: AuthMethod.password,
);

/// 弹窗提交结果的回收器：闭包在 widget 树内赋值，测试在树外断言。
final class _Harness {
  CredentialsSubmission? captured;
}

Future<_Harness> _pumpDialog(
  WidgetTester tester, {
  SshCredentials? initial,
  bool allowRemember = false,
  bool rememberInitially = false,
}) async {
  final harness = _Harness();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                harness.captured = await showCredentialsDialog(
                  context,
                  _server(),
                  initial: initial,
                  allowRemember: allowRemember,
                  rememberInitially: rememberInitially,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  testWidgets('密码模式下输入并连接，返回凭据', (tester) async {
    final harness = await _pumpDialog(tester);

    await tester.enterText(find.byType(TextFormField).first, 'secret');
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();

    expect(harness.captured?.credentials.password, 'secret');
    expect(harness.captured?.credentials.privateKey, isNull);
    // 未提供「记住」入口时恒为 false。
    expect(harness.captured?.remember, isFalse);
  });

  testWidgets('initial 凭据预填输入框，且「记住」默认勾选', (tester) async {
    final harness = await _pumpDialog(
      tester,
      initial: const SshCredentials(password: 'saved-pw'),
      allowRemember: true,
      rememberInitially: true,
    );

    expect(find.text('saved-pw'), findsOneWidget);
    final checkbox = tester.widget<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(checkbox.value, isTrue);

    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();

    expect(harness.captured?.credentials.password, 'saved-pw');
    expect(harness.captured?.remember, isTrue);
  });

  testWidgets('取消勾选记住 → remember=false', (tester) async {
    final harness = await _pumpDialog(
      tester,
      initial: const SshCredentials(password: 'saved-pw'),
      allowRemember: true,
      rememberInitially: true,
    );

    await tester.tap(find.text('记住凭据'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();

    expect(harness.captured?.remember, isFalse);
  });

  testWidgets('不支持记住的平台隐藏开关', (tester) async {
    await _pumpDialog(tester, allowRemember: false);

    expect(find.text('记住凭据'), findsNothing);
  });

  testWidgets('私钥预填走密钥输入分支', (tester) async {
    final harness = await _pumpDialog(
      tester,
      initial: const SshCredentials(privateKey: '---KEY---', passphrase: 'pp'),
    );

    expect(find.widgetWithText(TextFormField, '---KEY---'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'pp'), findsOneWidget);

    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(harness.captured?.credentials.privateKey, '---KEY---');
    expect(harness.captured?.credentials.password, isNull);
  });

  testWidgets('Agent 方式：无需输入，提交 useAgent 凭据', (tester) async {
    final harness = await _pumpDialog(tester);

    await tester.tap(find.text('Agent'));
    await tester.pumpAndSettle();
    // 提示文案替代了输入框。
    expect(find.byType(TextFormField), findsNothing);
    expect(find.textContaining('ssh-add'), findsOneWidget);

    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(harness.captured?.credentials.useAgent, isTrue);
    expect(harness.captured?.credentials.password, isNull);
    expect(harness.captured?.credentials.privateKey, isNull);
  });

  testWidgets('Agent 预填凭据自动选中 Agent 方式', (tester) async {
    final harness = await _pumpDialog(
      tester,
      initial: const SshCredentials(useAgent: true),
      allowRemember: true,
    );

    expect(find.textContaining('ssh-add'), findsOneWidget);
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(harness.captured?.credentials.useAgent, isTrue);
  });
}
