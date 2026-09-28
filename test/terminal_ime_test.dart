import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/settings.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/ssh/terminal_view.dart';
import 'package:no_shell/theme.dart';
import 'package:xterm/ui.dart';

import 'support/transport_fakes.dart';

const _server = SshServer(
  id: 'srv-ime',
  group: 'g',
  name: 'ime-test',
  host: '10.0.0.11',
  username: 'root',
);

/// 平台报来的一份编辑状态。输入法的预编辑段用 [composing] 表示，
/// 上屏时它塌成空区间（引擎的 `-1/-1`）。
TextEditingValue _editingState(String text, {TextRange? composing}) =>
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: composing ?? TextRange.empty,
    );

Widget _host(Widget child, ValueNotifier<TerminalStylePrefs> style) =>
    MaterialApp(
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

/// 在指定平台上跑一段测试体。
///
/// 平台决定 `deleteDetection`（触屏开、桌面关），所以必须在建树之前就定下来；
/// 复位要写在测试体内——foundation 的不变式检查发生在 tear down 之前。
Future<void> _onPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<(TerminalSession, FakeTransport)> _pumpTerminal(
  WidgetTester tester, {
  Widget Function(Widget child)? wrap,
}) async {
  final transport = FakeTransport()..captureOutput = true;
  final session = TerminalSession(
    server: _server,
    credentials: const SshCredentials(password: 'pw'),
    transport: transport,
  );
  await session.start();
  addTearDown(session.dispose);
  final view = SshTerminalView(session: session, openLink: (uri) async => true);
  await tester.pumpWidget(
    _host(
      wrap == null ? view : wrap(view),
      ValueNotifier(const TerminalStylePrefs()),
    ),
  );
  // autofocus 的落地在下一帧：输入连接要在这一帧之后才建起来。
  await tester.pump();
  return (session, transport);
}

/// 引擎那边报来一份新的编辑状态。
Future<void> _send(WidgetTester tester, TextEditingValue value) async {
  tester.testTextInput.updateEditingValue(value);
  await tester.pump();
}

/// 一块 390×844 的手机屏（dpr 3）；键盘高度由 `tester.view.viewInsets` 驱动，
/// 与真机上一样先过 MediaQuery 再落到 Scaffold 的 body 上。
void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// 逐帧推键盘高度（逻辑像素），模拟平台的弹起 / 收起动画。
///
/// [systemBottomPad] 非零时同时按真机引擎的口径回填 `view.padding`
/// （`viewPadding` 减掉 insets）：键盘一弹起，系统底栏那一截就跟着塌掉。
Future<void> _animateKeyboard(
  WidgetTester tester, {
  required double from,
  required double to,
  int frames = 16,
  double systemBottomPad = 0,
}) async {
  for (var i = 1; i <= frames; i++) {
    final inset = from + (to - from) * i / frames;
    tester.view.viewInsets = FakeViewPadding(bottom: inset * 3);
    if (systemBottomPad > 0) {
      tester.view.padding = FakeViewPadding(
        bottom: (systemBottomPad - inset).clamp(0, systemBottomPad) * 3,
      );
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('输入法上屏', () {
    testWidgets('同一笔提交被引擎发三遍，只上屏一次', (tester) async {
      await _onPlatform(TargetPlatform.linux, () async {
        final (_, transport) = await _pumpTerminal(tester);

        // GTK 的一次上屏会依次触发 commit / preedit-changed / preedit-end，
        // 三遍都是同一份累积文本。逐遍都当「新输入」算，远端就收到三份。
        for (var i = 0; i < 3; i++) {
          await _send(tester, _editingState('吧'));
        }

        expect(transport.sent, ['吧']);
      });
    });

    testWidgets('同一个字连打两次仍然发两次', (tester) async {
      await _onPlatform(TargetPlatform.linux, () async {
        final (_, transport) = await _pumpTerminal(tester);

        // 用户真敲两下：引擎的状态是累积的（我们不再回写初始状态），
        // 第二遍报来的是「吧吧」。把它当成重复吞掉就是丢用户输入。
        await _send(tester, _editingState('吧'));
        await _send(tester, _editingState('吧吧'));

        expect(transport.sent, ['吧', '吧']);
      });
    });

    testWidgets('预编辑期间不上屏，提交时才上屏', (tester) async {
      await _onPlatform(TargetPlatform.linux, () async {
        final (_, transport) = await _pumpTerminal(tester);

        await _send(
          tester,
          _editingState('ba', composing: const TextRange(start: 0, end: 2)),
        );
        expect(transport.sent, isEmpty, reason: '预编辑只在终端里预览，不发往远端');

        await _send(tester, _editingState('吧'));
        expect(transport.sent, ['吧']);
      });
    });

    testWidgets('重新聚焦后第一笔输入不会被镜像吞掉', (tester) async {
      await _onPlatform(TargetPlatform.linux, () async {
        final (_, transport) = await _pumpTerminal(tester);
        await _send(tester, _editingState('吧不'));
        expect(transport.sent, ['吧不']);

        // 失焦会关掉输入连接，重新聚焦时又把平台状态设回初始值——镜像得跟着
        // 归位，否则这一段更短的输入会被算成「没有新内容」。
        final focusNode = tester
            .widget<TerminalView>(find.byType(TerminalView))
            .focusNode!;
        focusNode.unfocus();
        await tester.pump();
        focusNode.requestFocus();
        await tester.pump();

        await _send(tester, _editingState('是'));
        expect(transport.sent, ['吧不', '是']);
      });
    });
  });

  group('删除键检测只在触屏平台打开', () {
    testWidgets('桌面端用空的初始编辑状态', (tester) async {
      await _onPlatform(TargetPlatform.linux, () async {
        await _pumpTerminal(tester);

        expect(tester.testTextInput.editingState?['text'], '');
      });
    });

    testWidgets('触屏端保留两空格占位符', (tester) async {
      await _onPlatform(TargetPlatform.android, () async {
        await _pumpTerminal(tester);

        expect(tester.testTextInput.editingState?['text'], '  ');
      });
    });
  });

  group('软键盘弹起不带着终端一起重排', () {
    testWidgets('动画期间行列数不动，停稳后才落定一次', (tester) async {
      await _onPlatform(TargetPlatform.linux, () async {
        _usePhoneScreen(tester);
        final (session, _) = await _pumpTerminal(tester);
        // 终端给远端的 window-change 就挂在这条回调上（真机由传输层接）。
        final resizes = <(int, int)>[];
        session.terminal.onResize = (w, h, _, _) => resizes.add((w, h));
        final rows = session.terminal.viewHeight;

        await _animateKeyboard(tester, from: 0, to: 320);

        // 逐帧转发就是十六次 window-change：远端 shell / vim 会跟着重画
        // 十六遍，手机上看到的就是「切到终端 Tab、键盘弹起」时画面抖。
        expect(resizes, isEmpty);
        expect(session.terminal.viewHeight, rows);

        // 盒子没被压扁，只是上面多出来的一截被裁掉了——底边仍贴着槽位，
        // 也就是提示符与光标所在的那一行纹丝不动。
        final terminal = tester.getRect(find.byType(TerminalView));
        final host = tester.getRect(find.byType(SshTerminalView));
        expect(terminal.bottom, host.bottom);
        expect(terminal.height, greaterThan(host.height));

        // 键盘停稳：一次性落定到最终尺寸。
        await tester.pump(const Duration(milliseconds: 300));
        expect(resizes, hasLength(1));
        expect(session.terminal.viewHeight, lessThan(rows));
        expect(
          tester.getRect(find.byType(TerminalView)),
          tester.getRect(find.byType(SshTerminalView)),
          reason: '落定之后盒子回到槽位大小，不再有裁掉的部分',
        );
      });
    });

    testWidgets('收起键盘同样只落定一次', (tester) async {
      await _onPlatform(TargetPlatform.linux, () async {
        _usePhoneScreen(tester);
        final (session, _) = await _pumpTerminal(tester);
        await _animateKeyboard(tester, from: 0, to: 320);
        await tester.pump(const Duration(milliseconds: 300));
        final rowsUp = session.terminal.viewHeight;

        final resizes = <(int, int)>[];
        session.terminal.onResize = (w, h, _, _) => resizes.add((w, h));

        await _animateKeyboard(tester, from: 320, to: 0);
        expect(resizes, isEmpty, reason: '收起时同样不该逐帧重排');
        expect(session.terminal.viewHeight, rowsUp);

        await tester.pump(const Duration(milliseconds: 300));
        expect(resizes, hasLength(1));
        expect(session.terminal.viewHeight, greaterThan(rowsUp));
      });
    });

    testWidgets('不是键盘引起的高度变化立刻生效', (tester) async {
      await _onPlatform(TargetPlatform.linux, () async {
        _usePhoneScreen(tester);
        final (session, _) = await _pumpTerminal(tester);
        await tester.pump(const Duration(milliseconds: 300));
        final resizes = <(int, int)>[];
        session.terminal.onResize = (w, h, _, _) => resizes.add((w, h));

        // 键盘高度没动，只是可用高度变了（折叠键条 / 拖窗口边缘）：
        // 没有理由等落定，行列数当帧就该跟上。
        tester.view.physicalSize = const Size(390 * 3, 500 * 3);
        await tester.pump();

        expect(resizes, isNotEmpty);
      });
    });

    testWidgets('系统底栏那一截同时塌掉时也只落定一次', (tester) async {
      await _onPlatform(TargetPlatform.linux, () async {
        _usePhoneScreen(tester);
        // iPhone 的 home indicator（Android 是导航条）：键盘弹起后那一截不用
        // 再单独留出（insets 已经盖住它），槽位少掉的是「键盘高度 − 底栏」，
        // 与键盘高度并不相等。按键盘高度补差会多补一截，所以保持的目标是
        // 「动画前的槽高」而不是「键盘高度」。
        tester.view.viewPadding = const FakeViewPadding(bottom: 34 * 3);
        tester.view.padding = const FakeViewPadding(bottom: 34 * 3);
        final (session, _) = await _pumpTerminal(
          tester,
          wrap: (child) => SafeArea(child: child),
        );
        final slotBefore = tester.getRect(find.byType(SshTerminalView)).height;
        final resizes = <(int, int)>[];
        session.terminal.onResize = (w, h, _, _) => resizes.add((w, h));

        await _animateKeyboard(tester, from: 0, to: 320, systemBottomPad: 34);
        expect(resizes, isEmpty);
        await tester.pump(const Duration(milliseconds: 300));
        expect(resizes, hasLength(1));

        // 确认槽位与键盘高度真的不是一回事：少掉 320 − 34。
        final slotAfter = tester.getRect(find.byType(SshTerminalView)).height;
        expect(slotBefore - slotAfter, closeTo(320 - 34, 1));
      });
    });
  });
}
