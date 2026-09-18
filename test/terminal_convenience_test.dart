import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/settings.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_interactions.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/ssh/terminal_view.dart';
import 'package:no_shell/theme.dart';
import 'package:xterm/ui.dart';

import 'support/transport_fakes.dart';

const _server = SshServer(
  id: 'srv-ui',
  group: 'g',
  name: 'ui-test',
  host: '10.0.0.9',
  username: 'root',
);

/// 连接成功、可捕获「发往远端」内容的假传输。
FakeTransport _connected({List<String> lines = const ['banner\n']}) =>
    FakeTransport(lines: lines)..captureOutput = true;

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

Future<(TerminalSession, FakeTransport)> _pumpTerminal(
  WidgetTester tester,
  ValueNotifier<TerminalStylePrefs> style, {
  String output = 'banner\n',
  Future<bool> Function(Uri uri)? openLink,
}) async {
  final transport = _connected(lines: [output]);
  final session = TerminalSession(
    server: _server,
    credentials: const SshCredentials(password: 'pw'),
    transport: transport,
  );
  await session.start();
  addTearDown(session.dispose);
  await tester.pumpWidget(
    _host(
      SshTerminalView(
        session: session,
        openLink: openLink ?? (uri) async => true,
      ),
      style: style,
    ),
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

  group('链接点击（Cmd/Ctrl+单击）', () {
    // 测试 VM 里 defaultTargetPlatform 不是 macOS / iOS，因此修饰键是 Ctrl
    // ——与 Linux 同一支。Cmd 那支只是同一个平台判断的另一分支。
    /// 第 0 行第 0 列的全局坐标。RenderTerminal 的 padding 是 10，
    /// 因此「左上角往里 12 像素」稳稳落在第一格，也就是链接的开头。
    Offset firstCell(WidgetTester tester) => tester
        .state<TerminalViewState>(find.byType(TerminalView))
        .renderTerminal
        .localToGlobal(const Offset(12, 12));

    Future<void> click(WidgetTester tester, Offset at, {Offset? dragTo}) async {
      final gesture = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
      );
      if (dragTo != null) await gesture.moveTo(dragTo);
      await gesture.up();
      await tester.pumpAndSettle();
      // 单击会让 xterm 的手势层挂一个 kDoubleTapTimeout（300ms）的双击判定
      // 定时器；不放它跑完，测试结束时会因「还有 Timer 挂着」而失败。
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('Ctrl+单击链接交给系统打开', (tester) async {
      final opened = <Uri>[];
      final style = ValueNotifier(const TerminalStylePrefs());
      await _pumpTerminal(
        tester,
        style,
        output: 'https://example.com/a?b=1 and more\n',
        openLink: (uri) async {
          opened.add(uri);
          return true;
        },
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await click(tester, firstCell(tester));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(opened, [Uri.parse('https://example.com/a?b=1')]);
    });

    testWidgets('没按修饰键时只是普通点击', (tester) async {
      final opened = <Uri>[];
      final style = ValueNotifier(const TerminalStylePrefs());
      await _pumpTerminal(
        tester,
        style,
        output: 'https://example.com\n',
        openLink: (uri) async {
          opened.add(uri);
          return true;
        },
      );

      await click(tester, firstCell(tester));

      expect(opened, isEmpty);
    });

    testWidgets('Ctrl+拖动是选字，松手不打开链接', (tester) async {
      final opened = <Uri>[];
      final style = ValueNotifier(const TerminalStylePrefs());
      await _pumpTerminal(
        tester,
        style,
        output: 'https://example.com\n',
        openLink: (uri) async {
          opened.add(uri);
          return true;
        },
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      final at = firstCell(tester);
      await click(tester, at, dragTo: at + const Offset(60, 0));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(opened, isEmpty);
    });

    testWidgets('打不开时给提示', (tester) async {
      final style = ValueNotifier(const TerminalStylePrefs());
      await _pumpTerminal(
        tester,
        style,
        output: 'https://example.com\n',
        openLink: (uri) async => false,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await click(tester, firstCell(tester));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(find.text('无法打开链接'), findsOneWidget);
    });
  });

  group('链接下划线（按住 Cmd/Ctrl 悬停）', () {
    Offset firstCell(WidgetTester tester) => tester
        .state<TerminalViewState>(find.byType(TerminalView))
        .renderTerminal
        .localToGlobal(const Offset(12, 12));

    /// 终端自己的鼠标光标形状：xterm 把 MouseRegion 挂在 TerminalView 里面。
    MouseCursor cursorOf(WidgetTester tester) => tester
        .widget<MouseRegion>(
          find
              .descendant(
                of: find.byType(TerminalView),
                matching: find.byType(MouseRegion),
              )
              .first,
        )
        .cursor;

    /// 下划线浮层拿到的链接；没有该画的时候其 link 为 null。
    LinkUnderlinePainter? underlineOf(WidgetTester tester) {
      for (final paint in tester.widgetList<CustomPaint>(
        find.descendant(
          of: find.byType(SshTerminalView),
          matching: find.byType(CustomPaint),
        ),
      )) {
        final painter = paint.painter;
        if (painter is LinkUnderlinePainter) return painter;
      }
      return null;
    }

    testWidgets('按住 Ctrl 悬停到链接上：下划线与手型光标同时出现', (tester) async {
      final style = ValueNotifier(const TerminalStylePrefs());
      await _pumpTerminal(
        tester,
        style,
        output: 'https://example.com/a?b=1 and more\n',
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      // 没按修饰键：停在链接上也不给提示。
      await mouse.moveTo(firstCell(tester));
      await tester.pump();
      expect(cursorOf(tester), SystemMouseCursors.text);
      expect(underlineOf(tester)?.link, isNull);

      // 按住 Ctrl（指针没动）：下划线补上，跨度正好是链接那一段。
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(cursorOf(tester), SystemMouseCursors.click);
      expect(
        underlineOf(tester)?.link,
        const TerminalLink(
          url: 'https://example.com/a?b=1',
          row: 0,
          startCell: 0,
          endCell: 25,
        ),
      );

      // 松开修饰键：提示收回。
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(cursorOf(tester), SystemMouseCursors.text);
      expect(underlineOf(tester)?.link, isNull);
    });

    testWidgets('按住 Ctrl 悬停在非链接文字上不给提示', (tester) async {
      final style = ValueNotifier(const TerminalStylePrefs());
      await _pumpTerminal(tester, style, output: 'https://example.com plain\n');

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      // 第一格是链接，往右挪过空格，落到「plain」上。
      final render = tester
          .state<TerminalViewState>(find.byType(TerminalView))
          .renderTerminal;
      await mouse.moveTo(
        firstCell(tester) + Offset(render.cellSize.width * 21, 0),
      );
      await tester.pump();

      expect(cursorOf(tester), SystemMouseCursors.text);
      expect(underlineOf(tester)?.link, isNull);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    testWidgets('指针移出终端后提示消失', (tester) async {
      final style = ValueNotifier(const TerminalStylePrefs());
      await _pumpTerminal(tester, style, output: 'https://example.com\n');

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await mouse.moveTo(firstCell(tester));
      await tester.pump();
      expect(cursorOf(tester), SystemMouseCursors.click);

      await mouse.moveTo(const Offset(-40, -40));
      await tester.pump();
      expect(cursorOf(tester), SystemMouseCursors.text);
      expect(underlineOf(tester)?.link, isNull);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });
  });
}
