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
      style: ValueNotifier(const TerminalStylePrefs()),
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
}
