/// 应用级快捷键在终端聚焦时也得管用。
///
/// 终端是这个应用最常态的焦点所在，而 xterm 会把 Ctrl+字母 先当控制字符发往
/// 远端（^B / ^F / ^N / ^T），骨架那层 `CallbackShortcuts` 因此根本收不到键——
/// 非 Apple 平台上 Ctrl+N / Ctrl+F / Ctrl+T / Ctrl+B 曾经写着却按不出来。
/// 现在终端那张更近的键位表绑的是同一批意图（`appShortcuts`），Action 仍由
/// 骨架提供（沿树向上找到）。
///
/// 两件事分开测：键位表里有没有那几个绑定（纯函数，一眼看穿），以及按下之后
/// 动作有没有真的发生、控制字符有没有漏给远端（要挂一棵树）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:no_shell/app_shortcuts.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/settings.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_interactions.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/ssh/terminal_view.dart';
import 'package:no_shell/theme.dart';

import 'support/transport_fakes.dart';

const _server = SshServer(
  id: 'srv-app-shortcut',
  group: 'g',
  name: 'shortcut-test',
  host: '10.0.0.9',
  username: 'root',
);

void main() {
  setUp(AppTheme.resetCache);

  test('终端键位表让出 Ctrl+F / N / T 与 Ctrl+Shift+B，裸 Ctrl+B 不动', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final shortcuts = terminalShortcuts();
      final byKey = <(LogicalKeyboardKey, bool), Intent>{
        for (final entry in shortcuts.entries)
          if (entry.key is SingleActivator)
            (
              (entry.key as SingleActivator).trigger,
              (entry.key as SingleActivator).shift,
            ): entry.value,
      };
      expect(
        byKey[(LogicalKeyboardKey.keyF, false)],
        isA<FocusHostSearchIntent>(),
      );
      expect(
        byKey[(LogicalKeyboardKey.keyN, false)],
        isA<NewConnectionIntent>(),
      );
      expect(byKey[(LogicalKeyboardKey.keyT, false)], isA<NewSessionIntent>());
      expect(
        byKey[(LogicalKeyboardKey.keyB, true)],
        isA<ToggleSidebarIntent>(),
        reason: '侧边栏在非 Apple 平台是 Ctrl+Shift+B，也得按得出来',
      );
      expect(
        byKey.containsKey((LogicalKeyboardKey.keyB, false)),
        isFalse,
        reason: '裸 Ctrl+B 是 tmux 前缀，留给远端（见 tests 里的运行时用例）',
      );
      // 终端自己的键位不受影响。
      expect(
        byKey[(LogicalKeyboardKey.keyC, true)],
        isA<CopySelectionTextIntent>(),
      );
      expect(
        byKey[(LogicalKeyboardKey.keyF, true)],
        isA<TerminalSearchIntent>(),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('Apple 平台不让位：那边用 ⌘，xterm 不认 meta，键位自己会冒上去', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final appIntents = terminalAppShortcutIntents();
      expect(appIntents, isEmpty);
      final keyB = terminalShortcuts().keys.whereType<SingleActivator>().where(
        (a) => a.trigger == LogicalKeyboardKey.keyB,
      );
      expect(keyB, isEmpty, reason: 'macOS 的 Ctrl+B 是 tmux 前缀，不能被应用抢走');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('终端聚焦时 Ctrl+F / N / T / B 触发动作，且不漏控制字符给远端', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final transport = FakeTransport(lines: ['banner\n'])
        ..captureOutput = true;
      final session = TerminalSession(
        server: _server,
        credentials: const SshCredentials(password: 'pw'),
        transport: transport,
      );
      await session.start();
      addTearDown(session.dispose);
      final style = ValueNotifier(const TerminalStylePrefs());
      final fired = <String>[];

      // 骨架那一层的结构：键位表 + 动作，终端是它的子树。
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: Scaffold(
            body: Shortcuts(
              shortcuts: appShortcutIntents(),
              child: Actions(
                actions: appShortcutActions(
                  onToggleSidebar: () => fired.add('侧边栏'),
                  onFocusHostSearch: () => fired.add('搜索主机'),
                  onNewConnection: () => fired.add('新建连接'),
                  onNewSession: () => fired.add('新建会话'),
                  onOpenSettings: () => fired.add('设置'),
                  onShortcutsHelp: () => fired.add('帮助'),
                  onSwitchSession: (ordinal) => fired.add('会话 $ordinal'),
                ),
                child: SshTerminalView(session: session),
              ),
            ),
          ),
          builder: (context, navigator) => TerminalStyleScope(
            notifier: style,
            child: navigator ?? const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> pressCtrl(
        LogicalKeyboardKey key, {
        bool shift = false,
      }) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyDownEvent(key);
        await tester.sendKeyUpEvent(key);
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }

      Future<void> pressCtrlWithShift(LogicalKeyboardKey key) =>
          pressCtrl(key, shift: true);

      await pressCtrl(LogicalKeyboardKey.keyF);
      await pressCtrl(LogicalKeyboardKey.keyN);
      await pressCtrl(LogicalKeyboardKey.keyT);
      await pressCtrl(LogicalKeyboardKey.digit2);
      await pressCtrlWithShift(LogicalKeyboardKey.keyB);

      expect(fired, ['搜索主机', '新建连接', '新建会话', '会话 2', '侧边栏']);
      // 裸 Ctrl+B 是 tmux 前缀：终端聚焦时仍归远端，应用不抢。
      await pressCtrl(LogicalKeyboardKey.keyB);
      expect(fired, hasLength(5));
      expect(transport.sent, ['\x02'], reason: '^B 要原样发给远端');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
