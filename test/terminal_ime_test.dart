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
  WidgetTester tester,
) async {
  final transport = FakeTransport()..captureOutput = true;
  final session = TerminalSession(
    server: _server,
    credentials: const SshCredentials(password: 'pw'),
    transport: transport,
  );
  await session.start();
  addTearDown(session.dispose);
  await tester.pumpWidget(
    _host(
      SshTerminalView(session: session, openLink: (uri) async => true),
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
}
