import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/settings.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_input_modifiers.dart';
import 'package:no_shell/ssh/terminal_key_bar.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/ssh/terminal_view.dart';
import 'package:no_shell/theme.dart';
import 'package:xterm/core.dart';
import 'package:xterm/ui.dart';

import 'support/transport_fakes.dart';

const _server = SshServer(
  id: 'srv-keys',
  group: 'g',
  name: 'keys-test',
  host: '10.0.0.9',
  username: 'root',
);

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
  WidgetTester tester, {
  String output = 'banner\n',
  Future<bool> Function(Uri uri)? openLink,
  ValueNotifier<TerminalStylePrefs>? style,
}) async {
  final transport = FakeTransport(lines: [output])..captureOutput = true;
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
      style: style ?? ValueNotifier(const TerminalStylePrefs()),
    ),
  );
  await tester.pump();
  return (session, transport);
}

/// 第一格（第 0 行第 0 列）的全局坐标；RenderTerminal 的 padding 是 10。
Offset _firstCell(WidgetTester tester) => tester
    .state<TerminalViewState>(find.byType(TerminalView))
    .renderTerminal
    .localToGlobal(const Offset(12, 12));

/// 触屏点一下：按下与抬起之间不超过 [_linkTapSlop]。
Future<TestGesture> _touch(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(at, kind: PointerDeviceKind.touch);
  await gesture.up();
  return gesture;
}

/// 放掉所有延迟判定：xterm 的双击窗口 300ms 与本视图的单击窗口 260ms。
Future<void> _settleWindows(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(_installClipboardMock);

  group('修饰键变换（纯函数）', () {
    test('Ctrl + 字母 → 控制码，大小写等价', () {
      expect(controlCodeOf('c'), '\x03');
      expect(controlCodeOf('C'), '\x03');
      expect(controlCodeOf('a'), '\x01');
      expect(controlCodeOf('z'), '\x1a');
      expect(controlCodeOf('['), '\x1b');
      expect(controlCodeOf('_'), '\x1f');
      expect(controlCodeOf(' '), '\x00');
      expect(controlCodeOf('?'), '\x7f');
    });

    test('Ctrl 认不出来的输入原样返回，不吞字符', () {
      expect(controlCodeOf('中'), isNull);
      expect(controlCodeOf('ab'), isNull);
      expect(controlCodeOf('1'), isNull);
      expect(applyTerminalModifiers('中', ctrl: true, alt: false), '中');
      expect(applyTerminalModifiers('ab', ctrl: true, alt: false), 'ab');
    });

    test('Alt 加 ESC 前缀，两者可叠加', () {
      expect(applyTerminalModifiers('b', ctrl: false, alt: true), '\x1bb');
      expect(applyTerminalModifiers('c', ctrl: true, alt: true), '\x1b\x03');
      expect(applyTerminalModifiers('c', ctrl: false, alt: false), 'c');
    });

    test('待命状态取走一次就熄灭', () {
      final modifiers = TerminalInputModifiers();
      var notified = 0;
      modifiers.addListener(() => notified++);

      modifiers.toggleCtrl();
      expect(modifiers.ctrl, isTrue);
      expect(modifiers.isArmed, isTrue);

      final taken = modifiers.take();
      expect((taken.ctrl, taken.alt), (true, false));
      expect(modifiers.isArmed, isFalse, reason: '一次输入只吃一次');

      // 没有变化就不该再发通知：下游是整条键条。
      final before = notified;
      modifiers.take();
      expect(notified, before);
      modifiers.dispose();
    });
  });

  group('粘滞修饰键接进终端输入', () {
    testWidgets('待命 Ctrl 后，软键盘敲下的字符变成控制码', (tester) async {
      final (session, transport) = await _pumpTerminal(tester);

      session.inputModifiers.toggleCtrl();
      session.terminal.textInput('c');
      expect(transport.sent, ['\x03'], reason: 'Ctrl+C 必须是 0x03');

      // 只生效一次：下一个字符照常发出去。
      session.terminal.textInput('c');
      expect(transport.sent, ['\x03', 'c']);
    });

    testWidgets('待命修饰键也能组合键条上的方向键', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final (session, transport) = await _pumpTerminal(tester);

        session.inputModifiers.toggleCtrl();
        session.terminal.keyInput(TerminalKey.arrowLeft);

        // keytab 把 Ctrl 编进 CSI 的修饰位（\x1b[1;5D），不是裸的 \x1b[D。
        expect(transport.sent.single, '\x1b[1;5D');
        expect(session.inputModifiers.isArmed, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('粘贴不吃修饰键，并且会清掉待命状态', (tester) async {
      final (session, transport) = await _pumpTerminal(tester);

      session.inputModifiers.toggleCtrl();
      session.terminal.paste('echo hi');
      expect(transport.sent, ['echo hi']);
      expect(session.inputModifiers.isArmed, isFalse);
    });
  });

  group('快捷键条（触屏平台）', () {
    testWidgets('Android 上挂载，Esc / Tab / 方向键按键即发', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final (_, transport) = await _pumpTerminal(tester);

        expect(find.byType(TerminalKeyBar), findsOneWidget);
        for (final label in ['esc', 'tab', 'ctrl', 'alt', '←', '↑', '↓', '→']) {
          expect(find.text(label), findsOneWidget, reason: '缺了 $label 键');
        }

        await tester.tap(find.text('esc'));
        await tester.pump();
        await tester.tap(find.text('tab'));
        await tester.pump();
        await tester.tap(find.text('↓'));
        await tester.pump();

        expect(transport.sent, ['\x1b', '\t', '\x1b[B']);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('点 ctrl 点亮待命，再点一次取消', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final (session, _) = await _pumpTerminal(tester);

        await tester.tap(find.text('ctrl'));
        await tester.pump();
        expect(session.inputModifiers.ctrl, isTrue);
        expect(
          find.text('Ctrl 待命 · 只对下一个按键生效'),
          findsOneWidget,
          reason: '粘滞语义得说清楚，触屏上没有「按住」这回事',
        );

        await tester.tap(find.text('ctrl'));
        await tester.pump();
        expect(session.inputModifiers.ctrl, isFalse);
        expect(find.text('Ctrl 待命 · 只对下一个按键生效'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('键条里的 A- / A+ 直接改全局字号，到界置灰', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final style = ValueNotifier(const TerminalStylePrefs());
        await _pumpTerminal(tester, style: style);
        addTearDown(style.dispose);

        await tester.tap(find.text('A+'));
        await tester.pump();
        expect(style.value.fontSize, TerminalStylePrefs.defaultFontSize + 1);

        await tester.tap(find.text('A-'));
        await tester.tap(find.text('A-'));
        await tester.pump();
        expect(style.value.fontSize, TerminalStylePrefs.defaultFontSize - 1);

        // 到顶之后 A+ 置灰：点了不再涨，也不会发出无变化的通知。
        style.value = const TerminalStylePrefs(
          fontSize: TerminalStylePrefs.maxFontSize,
        );
        await tester.pump();
        await tester.tap(find.text('A+'));
        await tester.pump();
        expect(style.value.fontSize, TerminalStylePrefs.maxFontSize);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('折叠后只剩一颗展开键，再点回来', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _pumpTerminal(tester);

        await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
        await tester.pump();
        expect(find.text('esc'), findsNothing);
        expect(find.text('快捷键'), findsOneWidget);

        await tester.tap(find.text('快捷键'));
        await tester.pump();
        expect(find.text('esc'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('桌面平台不挂键条', (tester) async {
      // widget 测试默认平台是 android，这里必须显式压成桌面端。
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final (_, transport) = await _pumpTerminal(tester);
        expect(find.byType(TerminalKeyBar), findsNothing);
        expect(transport.sent, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('窄屏 320 不溢出：键位横向滚动，折叠键留在右端', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _pumpTerminal(tester);

        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('触屏长按菜单', () {
    testWidgets('长按弹出复制 / 粘贴 / 全选，全选后可复制', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _pumpTerminal(tester);

        final gesture = await tester.startGesture(
          _firstCell(tester) + const Offset(2, 2),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump(const Duration(milliseconds: 600));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(find.text('复制'), findsOneWidget);
        expect(find.text('粘贴'), findsOneWidget);
        expect(find.text('全选'), findsOneWidget);

        await tester.tap(find.text('全选'));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(20, 300));
        await tester.pumpAndSettle();

        // 长按处不是链接，所以没有「打开链接」这一项。
        expect(find.text('打开链接'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('长按在链接上多给一项「打开链接」', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final opened = <Uri>[];
        await _pumpTerminal(
          tester,
          output: 'https://example.com/a?b=1 and more\n',
          openLink: (uri) async {
            opened.add(uri);
            return true;
          },
        );

        final gesture = await tester.startGesture(
          _firstCell(tester) + const Offset(2, 2),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump(const Duration(milliseconds: 600));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(find.text('打开链接'), findsOneWidget);
        await tester.tap(find.text('打开链接'));
        await tester.pumpAndSettle();

        expect(opened, [Uri.parse('https://example.com/a?b=1')]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('长按后抬手不会顺带把链接点开', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final opened = <Uri>[];
        await _pumpTerminal(
          tester,
          output: 'https://example.com\n',
          openLink: (uri) async {
            opened.add(uri);
            return true;
          },
        );

        final gesture = await tester.startGesture(
          _firstCell(tester) + const Offset(2, 2),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump(const Duration(milliseconds: 600));
        await gesture.up();
        await tester.pumpAndSettle();
        // 关掉菜单，再放完双击窗口。
        await tester.tapAt(const Offset(20, 400));
        await _settleWindows(tester);

        expect(opened, isEmpty, reason: '长按是「叫我菜单」，不是「打开链接」');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('触屏点链接', () {
    testWidgets('单击链接直接打开（手机上按不出 Cmd/Ctrl）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final opened = <Uri>[];
        await _pumpTerminal(
          tester,
          output: 'https://example.com/a?b=1 and more\n',
          openLink: (uri) async {
            opened.add(uri);
            return true;
          },
        );

        await _touch(tester, _firstCell(tester) + const Offset(2, 2));
        await _settleWindows(tester);

        expect(opened, [Uri.parse('https://example.com/a?b=1')]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('双击不打开：那是在选词', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final opened = <Uri>[];
        await _pumpTerminal(
          tester,
          output: 'https://example.com\n',
          openLink: (uri) async {
            opened.add(uri);
            return true;
          },
        );

        final at = _firstCell(tester) + const Offset(2, 2);
        await _touch(tester, at);
        await tester.pump(const Duration(milliseconds: 80));
        await _touch(tester, at);
        await _settleWindows(tester);

        expect(opened, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('点空白处不打开任何东西', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final opened = <Uri>[];
        await _pumpTerminal(
          tester,
          output: 'https://example.com plain text\n',
          openLink: (uri) async {
            opened.add(uri);
            return true;
          },
        );

        final render = tester
            .state<TerminalViewState>(find.byType(TerminalView))
            .renderTerminal;
        await _touch(
          tester,
          _firstCell(tester) + Offset(render.cellSize.width * 21, 0),
        );
        await _settleWindows(tester);

        expect(opened, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('回到最新输出', () {
    /// 造一段比视口长的输出，回滚缓冲里才有可滚的余地。
    String manyLines() => List.generate(200, (i) => 'line $i').join('\n');

    ScrollableState scrollable(WidgetTester tester) =>
        tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(TerminalView),
                matching: find.byType(Scrollable),
              )
              .first,
        );

    testWidgets('停在底部时没有按钮，滚上去才出现，点它跳回底部', (tester) async {
      await _pumpTerminal(tester, output: manyLines());
      await tester.pump();

      // 刚连上停在最新输出：不摆按钮。
      expect(find.text('回到最新'), findsNothing);

      final position = scrollable(tester).position;
      expect(position.maxScrollExtent, greaterThan(0), reason: '输出要长过视口');
      position.jumpTo(0);
      await tester.pump();

      expect(find.text('回到最新'), findsOneWidget);

      await tester.tap(find.text('回到最新'));
      await tester.pump();

      expect(position.pixels, position.maxScrollExtent);
      expect(find.text('回到最新'), findsNothing);
    });

    testWidgets('滚回底部（手动）后按钮自己收回', (tester) async {
      await _pumpTerminal(tester, output: manyLines());
      await tester.pump();
      final position = scrollable(tester).position;

      position.jumpTo(0);
      await tester.pump();
      expect(find.text('回到最新'), findsOneWidget);

      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(find.text('回到最新'), findsNothing);
    });
  });

  group('选区手柄（触屏）', () {
    /// 选区文本：手柄拖到哪儿，缓冲区里选中的就是哪儿。
    String selectedText(WidgetTester tester) {
      final view = tester.widget<TerminalView>(find.byType(TerminalView));
      final selection = view.controller!.selection;
      return selection == null ? '' : view.terminal.buffer.getText(selection);
    }

    Finder handle(String which) =>
        find.byKey(ValueKey('selection-handle-$which'));

    ScrollableState scrollable(WidgetTester tester) =>
        tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(TerminalView),
                matching: find.byType(Scrollable),
              )
              .first,
        );

    /// 直接给一个选区。手柄拖动本身用程序化选区来测：长按那条路会把菜单
    /// 弹出来（模态层会挡住后续指针事件），选词与菜单另有专门的用例。
    void selectRange(WidgetTester tester, int row, int fromX, int toX) {
      final view = tester.widget<TerminalView>(find.byType(TerminalView));
      final buffer = view.terminal.buffer;
      view.controller!.setSelection(
        buffer.createAnchor(fromX, row),
        buffer.createAnchor(toX, row),
      );
    }

    /// 拖手柄：按住手柄、挪到目标、松手。判定全在自己的 `Listener` 里，
    /// 没有手势竞技场要过，所以一次 moveTo 就够。
    Future<void> dragHandle(WidgetTester tester, Offset from, Offset to) async {
      final drag = await tester.startGesture(
        from,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 20));
      await drag.moveTo(to);
      await tester.pump();
      await drag.up();
      await tester.pump();
    }

    testWidgets('有选区时出现首尾手柄，拖动终点手柄扩展选区', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await _pumpTerminal(tester, output: 'hello world again\n');

        expect(handle('start'), findsNothing, reason: '没有选区就没有手柄');

        selectRange(tester, 0, 0, 4);
        await tester.pump();

        expect(handle('start'), findsOneWidget);
        expect(handle('end'), findsOneWidget);
        // 末格是开区间：锚到第 4 格选中的是 0..3，也就是 'hell'。
        expect(selectedText(tester).trim(), 'hell');

        // 把终点手柄往右拖：选区应当跟着长出去。
        final from = tester.getCenter(handle('end'));
        final cellWidth = tester
            .state<TerminalViewState>(find.byType(TerminalView))
            .renderTerminal
            .cellSize
            .width;
        await dragHandle(tester, from, from + Offset(cellWidth * 7, 0));

        expect(selectedText(tester).trim(), startsWith('hello world'));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('终点手柄拖出下边界时画面跟着滚，选区落到边上那一行', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final lines = List.generate(200, (i) => 'line $i');
        await _pumpTerminal(tester, output: '${lines.join('\n')}\n');

        // 先滚到中段，让下方还有可滚的余地。
        final position = scrollable(tester).position;
        position.jumpTo(position.maxScrollExtent / 2);
        await tester.pump();

        // 在可见的第一行上选一段：手柄要落在视野里才拖得到。
        final render = tester
            .state<TerminalViewState>(find.byType(TerminalView))
            .renderTerminal;
        final firstRow = (position.pixels / render.lineHeight).floor();
        selectRange(tester, firstRow, 0, 4);
        await tester.pump();
        expect(handle('end'), findsOneWidget);

        final before = position.pixels;
        final from = tester.getCenter(handle('end'));
        // 一路拖到终端下边界之外。
        await dragHandle(tester, from, Offset(from.dx + 40, 5000));

        expect(position.pixels, greaterThan(before), reason: '拖出下边界要把画面跟着滚下去');
        expect(selectedText(tester), isNotEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('桌面端不摆手柄（那边用鼠标拖选）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await _pumpTerminal(tester, output: 'hello world\n');
        // 直接给一个选区（桌面端这一步由鼠标拖选完成）。
        final view = tester.widget<TerminalView>(find.byType(TerminalView));
        final buffer = view.terminal.buffer;
        view.controller!.setSelection(
          buffer.createAnchor(0, 0),
          buffer.createAnchor(4, 0),
        );
        await tester.pump();
        expect(handle('start'), findsNothing);
        expect(handle('end'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('鼠标模式（触屏拖拽转发）', () {
    /// 让远端「开鼠标上报」：1002 = 按住拖动时上报，1006 = SGR 编码。
    void remoteTurnsOnMouse(TerminalSession session) =>
        session.terminal.write('\x1b[?1002h\x1b[?1006h');

    Future<void> dragOnce(WidgetTester tester, Offset at) async {
      final gesture = await tester.startGesture(
        at,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
    }

    testWidgets('开着时拖动转发按下 / 移动 / 抬起，按下那一笔与点击同源', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final (session, transport) = await _pumpTerminal(
          tester,
          output: 'hello world\n',
        );
        remoteTurnsOnMouse(session);
        await tester.pump();

        // 先点一下：远端开着鼠标上报时点击会转发成按下 + 抬起。
        final at = _firstCell(tester) + const Offset(2, 2);
        await _touch(tester, at);
        await _settleWindows(tester);
        expect(transport.sent, isNotEmpty, reason: '远端开了鼠标上报，点击应当转发');
        final tapDown = transport.sent.first;

        transport.sent.clear();
        // 键条上那颗「鼠标」在远端开着鼠标上报时才亮，点亮即开。
        await tester.tap(find.text('鼠标'));
        await tester.pump();

        await dragOnce(tester, at);

        expect(transport.sent, hasLength(3), reason: '按下 / 移动 / 抬起各一笔');
        expect(
          transport.sent.first,
          tapDown,
          reason: '按下的字节必须与点击一致：一边是包编的，一边是我们编的',
        );
        // SGR：\x1b[<32;x;yM —— 移动事件的按钮号加 32。
        expect(
          transport.sent[1],
          startsWith('\x1b[<32;'),
          reason: '移动事件的按钮号加 32',
        );
        expect(transport.sent.last, endsWith('m'), reason: 'SGR 抬起是小写 m');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('挂上来时远端已经开着鼠标上报：那颗键直接可用', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final transport = FakeTransport(lines: ['hello world\n'])
          ..captureOutput = true;
        final session = TerminalSession(
          server: _server,
          credentials: const SshCredentials(password: 'pw'),
          transport: transport,
        );
        await session.start();
        addTearDown(session.dispose);
        // 视图挂上来之前远端就开着鼠标上报——从另一条会话切过来就是这个
        // 时序，状态得在 initState 里对一次表，不能等下一次输出。
        session.terminal.write('\x1b[?1002h\x1b[?1006h');

        final style = ValueNotifier(const TerminalStylePrefs());
        addTearDown(style.dispose);
        await tester.pumpWidget(
          _host(
            SshTerminalView(session: session, openLink: (uri) async => true),
            style: style,
          ),
        );
        await tester.pump();

        await tester.tap(find.text('鼠标'));
        await tester.pump();
        await dragOnce(tester, _firstCell(tester) + const Offset(2, 2));

        expect(transport.sent, isNotEmpty, reason: '那颗键该是亮的，点了就生效');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('开着时一次轻点只发一遍按下 / 抬起', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final (session, transport) = await _pumpTerminal(
          tester,
          output: 'hello world\n',
        );
        remoteTurnsOnMouse(session);
        await tester.pump();
        await tester.tap(find.text('鼠标'));
        await tester.pump();
        transport.sent.clear();

        // 轻点一下：只该有我们这一条路径（xterm 那层 tap 转发已被挂起），
        // 否则远端收到 down,down,up,up —— vim / tmux 会当成双击。
        await _touch(tester, _firstCell(tester) + const Offset(2, 2));
        await _settleWindows(tester);

        expect(transport.sent, hasLength(2), reason: '一遍按下 + 一遍抬起');
        expect(transport.sent.first, startsWith('\x1b[<0;'));
        expect(transport.sent.last, endsWith('m'));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('远端关掉鼠标上报后自动退出鼠标模式，拖动恢复滚动', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final (session, transport) = await _pumpTerminal(
          tester,
          output: '${List.generate(200, (i) => 'line $i').join('\n')}\n',
        );
        remoteTurnsOnMouse(session);
        await tester.pump();
        await tester.tap(find.text('鼠标'));
        await tester.pump();

        // 远端不再上报（`:q` 退出 vim、tmux 关掉 mouse）。
        session.terminal.write('\x1b[?1002l');
        await tester.pump();
        transport.sent.clear();

        final position = tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(TerminalView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
        position.jumpTo(position.maxScrollExtent / 2);
        await tester.pump();
        final before = position.pixels;

        // 往上拖：模式已经自动退出，这一次拖动该滚画面而不是发鼠标事件。
        // 两段移动：头一段只用来越过滚动的判定阈值（DragStartBehavior.start
        // 会把越过阈值之前的那段位移丢掉），第二段才是真正要滚的距离。
        final drag = await tester.startGesture(
          tester.getCenter(find.byType(TerminalView)),
          kind: PointerDeviceKind.touch,
        );
        await drag.moveBy(const Offset(0, 30));
        await tester.pump();
        await drag.moveBy(const Offset(0, 120));
        await tester.pump();
        await drag.up();
        await tester.pump();

        expect(transport.sent, isEmpty, reason: '远端没人接鼠标事件了');
        expect(position.pixels, lessThan(before), reason: '拖动该滚画面');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('没开鼠标模式时拖动不转发（照旧滚画面）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final (session, transport) = await _pumpTerminal(
          tester,
          output: 'hello world\n',
        );
        remoteTurnsOnMouse(session);
        await tester.pump();

        await dragOnce(tester, _firstCell(tester) + const Offset(2, 2));

        expect(transport.sent, isEmpty, reason: '默认拖动是滚画面，不发鼠标事件');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('远端没开鼠标上报时那颗键置灰，点了也不生效', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final (_, transport) = await _pumpTerminal(tester, output: 'hello\n');

        await tester.tap(find.text('鼠标'));
        await tester.pump();
        await dragOnce(tester, _firstCell(tester) + const Offset(2, 2));

        expect(transport.sent, isEmpty, reason: '远端没人接鼠标事件，开了也没用');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('双指捏合缩放（触屏）', () {
    /// 造一段比视口长的输出，顺便能验证捏合期间画面没被滚走。
    String manyLines() => List.generate(200, (i) => 'line $i').join('\n');

    ScrollableState scrollable(WidgetTester tester) =>
        tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(TerminalView),
                matching: find.byType(Scrollable),
              )
              .first,
        );

    testWidgets('两指张开只预览，抬手才改字号（且只落一次）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final style = ValueNotifier(const TerminalStylePrefs());
        addTearDown(style.dispose);
        await _pumpTerminal(tester, style: style, output: manyLines());
        final position = scrollable(tester).position;
        position.jumpTo(position.maxScrollExtent / 2);
        await tester.pump();
        final scrollBefore = position.pixels;

        final center = tester.getCenter(find.byType(TerminalView));
        final left = await tester.startGesture(
          center - const Offset(30, 0),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump();
        final right = await tester.startGesture(
          center + const Offset(30, 0),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump();

        // 张开到三倍跨度：字号该涨，但手势期间只出预览。
        await left.moveTo(center - const Offset(90, 0));
        await right.moveTo(center + const Offset(90, 0));
        await tester.pump();

        expect(
          style.value.fontSize,
          TerminalStylePrefs.defaultFontSize,
          reason: '手势期间不写偏好：写一次就是一次 PTY 重排',
        );
        expect(find.textContaining('字号'), findsOneWidget, reason: '要有预览');
        expect(position.pixels, scrollBefore, reason: '捏合期间画面不该跟着滚');

        await left.up();
        await right.up();
        await tester.pump();

        expect(
          style.value.fontSize,
          greaterThan(TerminalStylePrefs.defaultFontSize),
        );
        expect(find.textContaining('字号'), findsNothing, reason: '抬手后预览收起');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('两指收拢缩小，且夹在字号下限', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final style = ValueNotifier(const TerminalStylePrefs());
        addTearDown(style.dispose);
        await _pumpTerminal(tester, style: style, output: 'hello\n');

        final center = tester.getCenter(find.byType(TerminalView));
        final left = await tester.startGesture(
          center - const Offset(90, 0),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump();
        final right = await tester.startGesture(
          center + const Offset(90, 0),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump();

        // 收拢到十分之一：远远越过下限，应当被夹住。
        await left.moveTo(center - const Offset(9, 0));
        await right.moveTo(center + const Offset(9, 0));
        await tester.pump();
        await left.up();
        await right.up();
        await tester.pump();

        expect(style.value.fontSize, TerminalStylePrefs.minFontSize);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('外接鼠标按过之后，单指触摸不会被当成捏合', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final style = ValueNotifier(const TerminalStylePrefs());
        addTearDown(style.dispose);
        await _pumpTerminal(tester, style: style, output: 'hello\n');
        final at = tester.getCenter(find.byType(TerminalView));

        // iPad 触控板 / Android 外接鼠标：按下再抬起，抬起走的是鼠标分支。
        final mouse = await tester.startGesture(
          at,
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryButton,
        );
        await mouse.up();
        await tester.pump();

        // 此后单指触摸：表里若留着那根鼠标指针，这里就会被当成两指捏合。
        final touch = await tester.startGesture(
          at,
          kind: PointerDeviceKind.touch,
        );
        await touch.moveBy(const Offset(80, 0));
        await tester.pump();
        expect(find.textContaining('字号'), findsNothing, reason: '这不是捏合');
        await touch.up();
        await tester.pump();
        // 放掉 xterm 双击判定挂的 300ms 计时器。
        await tester.pump(const Duration(milliseconds: 400));

        expect(style.value.fontSize, TerminalStylePrefs.defaultFontSize);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('桌面端两指拖动不改字号（那边没有捏合这回事）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final style = ValueNotifier(const TerminalStylePrefs());
        addTearDown(style.dispose);
        await _pumpTerminal(tester, style: style, output: 'hello\n');

        final center = tester.getCenter(find.byType(TerminalView));
        final left = await tester.startGesture(
          center - const Offset(30, 0),
          kind: PointerDeviceKind.touch,
        );
        final right = await tester.startGesture(
          center + const Offset(30, 0),
          kind: PointerDeviceKind.touch,
        );
        await left.moveTo(center - const Offset(90, 0));
        await right.moveTo(center + const Offset(90, 0));
        await tester.pump();
        await left.up();
        await right.up();
        await tester.pump();

        expect(style.value.fontSize, TerminalStylePrefs.defaultFontSize);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
