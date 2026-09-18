import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/settings.dart';
import 'package:no_shell/ssh/sftp.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_interactions.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/ssh/terminal_view.dart';
import 'package:no_shell/theme.dart';
import 'package:xterm/core.dart';
import 'package:xterm/ui.dart';

import 'support/forward_fakes.dart';

const _server = SshServer(
  id: 'srv-ui',
  group: 'g',
  name: 'ui-test',
  host: '10.0.0.9',
  username: 'root',
);

/// 连接成功、可捕获「发往远端」内容的假传输。
final class _ConnectedTransport with NoForwardingTransport {
  final sent = <String>[];

  @override
  Future<void> attach(
    Terminal terminal, {
    required void Function() onConnected,
    required void Function() onClosed,
  }) async {
    terminal.onOutput = sent.add;
    terminal.write('banner\n');
    onConnected();
  }

  @override
  Future<SftpFileSystem> openSftp() async =>
      throw const SftpException(SftpErrorKind.unsupported, 'fake');

  @override
  void dispose() {}
}

String _clipboardText = '';

void _installClipboardMock() {
  _clipboardText = '';
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            _clipboardText = call.arguments['text'] as String? ?? '';
            return null;
          case 'Clipboard.getData':
            return {'text': _clipboardText};
          default:
            return null;
        }
      });
}

Widget _host(
  Widget child, {
  required ValueNotifier<TerminalStylePrefs> style,
}) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: AppTheme.light(),
  home: Scaffold(body: child),
  builder: (context, navigator) => TerminalStyleScope(
    notifier: style,
    child: navigator ?? const SizedBox.shrink(),
  ),
);

Future<(TerminalSession, _ConnectedTransport)> _pumpTerminal(
  WidgetTester tester,
  ValueNotifier<TerminalStylePrefs> style,
) async {
  final transport = _ConnectedTransport();
  final session = TerminalSession(
    server: _server,
    credentials: const SshCredentials(password: 'pw'),
    transport: transport,
  );
  await session.start();
  addTearDown(session.dispose);
  await tester.pumpWidget(
    _host(SshTerminalView(session: session), style: style),
  );
  await tester.pump();
  return (session, transport);
}

/// 包的复制 / 全选动作注册在 TerminalView **内部**的 TerminalActions 上，
/// 动作解析沿树向上走，所以必须从视图内部的元素发起调用。
BuildContext _terminalContext(WidgetTester tester) => tester.element(
  find
      .descendant(
        of: find.byType(TerminalView),
        matching: find.byType(Scrollable),
      )
      .first,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(_installClipboardMock);

  group('工具条复制 / 粘贴', () {
    testWidgets('复制按钮无选区时禁用，全选后可用且能复制缓冲区', (tester) async {
      final style = ValueNotifier(const TerminalStylePrefs());
      await _pumpTerminal(tester, style);

      IconButton copyButton() => tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.copy_rounded),
      );
      expect(copyButton().onPressed, isNull);

      Actions.invoke(
        _terminalContext(tester),
        const SelectAllTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pump();
      expect(copyButton().onPressed, isNotNull);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.copy_rounded));
      await tester.pump();
      expect(_clipboardText, startsWith('banner'));
    });

    testWidgets('粘贴按钮把剪贴板内容写进终端并发往远端', (tester) async {
      final style = ValueNotifier(const TerminalStylePrefs());
      final (_, transport) = await _pumpTerminal(tester, style);

      _clipboardText = 'echo hi';
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.content_paste_rounded),
      );
      await tester.pump();

      expect(transport.sent, contains('echo hi'));
    });
  });

  group('字号缩放', () {
    testWidgets('缩放意图按步进改字号并夹在合法范围，重置回默认', (tester) async {
      final style = ValueNotifier(const TerminalStylePrefs());
      await _pumpTerminal(tester, style);
      final context = tester.element(find.byType(TerminalView));

      Actions.invoke(context, const TerminalFontSizeAdjustIntent(1));
      await tester.pump();
      expect(style.value.fontSize, 14);

      Actions.invoke(context, const TerminalFontSizeAdjustIntent(-1));
      Actions.invoke(context, const TerminalFontSizeAdjustIntent(-1));
      await tester.pump();
      expect(style.value.fontSize, 12);

      style.value = const TerminalStylePrefs(
        fontSize: TerminalStylePrefs.maxFontSize,
      );
      await tester.pump();
      Actions.invoke(context, const TerminalFontSizeAdjustIntent(1));
      await tester.pump();
      expect(
        style.value.fontSize,
        TerminalStylePrefs.maxFontSize,
        reason: '越过上限应被夹住',
      );

      Actions.invoke(context, const TerminalFontSizeResetIntent());
      await tester.pump();
      expect(style.value.fontSize, TerminalStylePrefs.defaultFontSize);
    });

    testWidgets('Ctrl + 等号 / 数字 0 走键位表缩放与重置', (tester) async {
      // 强制非 Apple 平台：修饰键取 Ctrl，测试机是什么系统都不影响断言。
      // 必须在测试体内复位，foundation 的不变式检查发生在 tear down 之前。
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final style = ValueNotifier(const TerminalStylePrefs());
        await _pumpTerminal(tester, style);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        await tester.pump();
        expect(style.value.fontSize, 14);

        await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(style.value.fontSize, TerminalStylePrefs.defaultFontSize);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('右键菜单', () {
    testWidgets('右键弹出菜单，无选区时复制不生效，全选后可复制', (tester) async {
      final style = ValueNotifier(const TerminalStylePrefs());
      await _pumpTerminal(tester, style);

      Future<void> rightClick() async {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(TerminalView)),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await gesture.up();
        await tester.pumpAndSettle();
      }

      Future<void> dismissMenu() async {
        await tester.tapAt(const Offset(20, 300));
        await tester.pumpAndSettle();
      }

      await rightClick();
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('粘贴'), findsOneWidget);
      expect(find.text('全选'), findsOneWidget);

      // 无选区：复制是禁用项，点它不应写剪贴板。
      await tester.tap(find.text('复制'));
      await tester.pump();
      expect(_clipboardText, isEmpty);
      await dismissMenu();

      Actions.invoke(
        _terminalContext(tester),
        const SelectAllTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pump();

      await rightClick();
      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();
      expect(_clipboardText, startsWith('banner'));
    });
  });

  group('选中即复制', () {
    testWidgets('开启后选区落定自动复制', (tester) async {
      final style = ValueNotifier(const TerminalStylePrefs(copyOnSelect: true));
      await _pumpTerminal(tester, style);

      Actions.invoke(
        _terminalContext(tester),
        const SelectAllTextIntent(SelectionChangedCause.keyboard),
      );
      // 拖选期间选区连续变化，去抖窗口（160ms）过后才落剪贴板。
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(_clipboardText, startsWith('banner'));
    });

    testWidgets('默认关闭，选中不写剪贴板', (tester) async {
      final style = ValueNotifier(const TerminalStylePrefs());
      await _pumpTerminal(tester, style);

      Actions.invoke(
        _terminalContext(tester),
        const SelectAllTextIntent(SelectionChangedCause.keyboard),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(_clipboardText, isEmpty);
    });
  });

  group('终端样式缓存', () {
    testWidgets('偏好没变就复用同一个 TerminalStyle 实例', (tester) async {
      final style = ValueNotifier(const TerminalStylePrefs());
      await _pumpTerminal(tester, style);

      TerminalView view() =>
          tester.widget<TerminalView>(find.byType(TerminalView));
      final first = view().textStyle;

      // 父级重建（会话状态变化、尺寸变化都会走到这里）时必须还是同一个实例：
      // xterm 的 painter / render 守卫都是身份比较，新建一个内容相同的实例会
      // 重测字符宽度并清空 10240 条段落缓存，整个视口跟着重排版。
      await tester.pump();
      expect(
        identical(view().textStyle, first),
        isTrue,
        reason: '重复 build 不该换实例',
      );

      // 偏好真的变了才允许换，否则界面不跟着动。
      style.value = const TerminalStylePrefs(fontSize: 17);
      await tester.pump();
      final updated = view().textStyle;
      expect(identical(updated, first), isFalse, reason: '字号变了必须换实例');

      // 稳定之后继续复用同一个。
      await tester.pump();
      expect(identical(view().textStyle, updated), isTrue);
    });
  });
}
