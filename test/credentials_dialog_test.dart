import 'package:flutter/foundation.dart';
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
  String? title,
  String? confirmLabel,
  bool lockRemember = false,
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
                  title: title,
                  confirmLabel: confirmLabel,
                  lockRemember: lockRemember,
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

  testWidgets('密钥方式：选择文件灌入内容，提交返回私钥凭据', (tester) async {
    pickPrivateKeyFile = (confirmLabel) async {
      // 弹窗必须把本地化的确认按钮文案传给选择器。
      expect(confirmLabel, '选择密钥文件');
      return const PickedKeyFile(name: 'id_ed25519', text: '---FILE KEY---');
    };
    addTearDown(() => pickPrivateKeyFile = pickPrivateKeyFileViaSelector);
    final harness = await _pumpDialog(tester);

    await tester.tap(find.text('SSH 密钥'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择密钥文件'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextFormField, '---FILE KEY---'),
      findsOneWidget,
    );
    expect(find.text('id_ed25519'), findsOneWidget);

    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();
    expect(harness.captured?.credentials.privateKey, '---FILE KEY---');
    expect(harness.captured?.credentials.password, isNull);
    expect(harness.captured?.credentials.passphrase, isNull);
  });

  testWidgets('密钥方式：手改内容后文件名提示消失', (tester) async {
    pickPrivateKeyFile = (confirmLabel) async =>
        const PickedKeyFile(name: 'id_rsa', text: '---FILE KEY---');
    addTearDown(() => pickPrivateKeyFile = pickPrivateKeyFileViaSelector);
    await _pumpDialog(tester);

    await tester.tap(find.text('SSH 密钥'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择密钥文件'));
    await tester.pumpAndSettle();
    expect(find.text('id_rsa'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '---EDITED---');
    await tester.pumpAndSettle();
    expect(find.text('id_rsa'), findsNothing);
  });

  testWidgets('密钥方式：选择器取消 → 字段保持原状', (tester) async {
    pickPrivateKeyFile = (confirmLabel) async => null;
    addTearDown(() => pickPrivateKeyFile = pickPrivateKeyFileViaSelector);
    await _pumpDialog(tester);

    await tester.tap(find.text('SSH 密钥'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '---PASTED---');
    await tester.tap(find.text('选择密钥文件'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, '---PASTED---'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('密钥方式：读取失败 → 说明框给出替代做法，且保留已贴内容', (tester) async {
    // 显式钉住非 Android：测试环境把 defaultTargetPlatform 强行报成 android
    // （FLUTTER_TEST，见 foundation/_platform_io.dart），不钉住就测不到
    // 「其余平台」的那条文案。
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    pickPrivateKeyFile = (confirmLabel) async => throw StateError('boom');
    addTearDown(() => pickPrivateKeyFile = pickPrivateKeyFileViaSelector);
    await _pumpDialog(tester);

    await tester.tap(find.text('SSH 密钥'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '---PASTED---');
    await tester.tap(find.text('选择密钥文件'));
    await tester.pumpAndSettle();
    // 说明框已经建好，先把平台恢复，免得 foundation 变量被动过被兜底断言抓走。
    debugDefaultTargetPlatformOverride = null;

    // 凭据弹窗之上再叠一个说明框：用户得读到「怎么办」，不能一闪而过。
    expect(find.byType(AlertDialog), findsNWidgets(2));
    expect(find.text('无法读取所选的密钥文件。'), findsOneWidget);
    expect(find.textContaining('复制全部内容'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '---PASTED---'), findsOneWidget);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '---PASTED---'), findsOneWidget);
  });

  testWidgets('密钥方式：Android 上失败说明框点名澎湃「安全访问」并声明权限边界', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    pickPrivateKeyFile = (confirmLabel) async => throw StateError('boom');
    addTearDown(() => pickPrivateKeyFile = pickPrivateKeyFileViaSelector);
    await _pumpDialog(tester);

    await tester.tap(find.text('SSH 密钥'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择密钥文件'));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;

    expect(find.textContaining('安全访问'), findsOneWidget);
    expect(find.textContaining('不申请整机存储的访问权限'), findsOneWidget);
  });

  testWidgets('lockRemember：无「记住凭据」开关，标题与确认键可定制，恒为 remember', (tester) async {
    // 编辑表单的「更换记住的凭据」复用本弹窗：语义是「这次输入就是要记住的」。
    final harness = await _pumpDialog(
      tester,
      allowRemember: true,
      lockRemember: true,
      title: '「test-host」的凭据',
      confirmLabel: '保存',
    );

    expect(find.text('「test-host」的凭据'), findsOneWidget);
    expect(find.text('记住凭据'), findsNothing);

    await tester.enterText(find.byType(TextFormField).first, 'new-secret');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(harness.captured?.credentials.password, 'new-secret');
    expect(harness.captured?.remember, isTrue);
  });

  group('密钥文件类型过滤', () {
    test('Android 一次给足三个 MIME，才会带上 EXTRA_MIME_TYPES', () {
      final groups = keyFileTypeGroups(
        platform: TargetPlatform.android,
        isWeb: false,
      );

      expect(groups, hasLength(1));
      final mimeTypes = groups.single.mimeTypes;
      expect(
        mimeTypes,
        containsAll(<String>['*/*', 'application/octet-stream', 'text/plain']),
      );
      // file_selector 的 Android 端只在过滤条件 ≥2 项时才写 EXTRA_MIME_TYPES；
      // 收成一项（哪怕就是 `*/*`）等于什么都没做。
      expect(mimeTypes, hasLength(3));
      expect(groups.single.extensions, isNull);
      expect(groups.single.uniformTypeIdentifiers, isNull);
    });

    test('其余平台一律不过滤：macOS / iOS 只认 extensions / UTI', () {
      for (final platform in <TargetPlatform>[
        TargetPlatform.macOS,
        TargetPlatform.iOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          keyFileTypeGroups(platform: platform, isWeb: false),
          isEmpty,
          reason: '$platform 不该收到 MIME 过滤',
        );
      }
      // web 走的是浏览器 input，Android 的那套 MIME 集合对它没有意义。
      expect(
        keyFileTypeGroups(platform: TargetPlatform.android, isWeb: true),
        isEmpty,
      );
    });
  });
}
