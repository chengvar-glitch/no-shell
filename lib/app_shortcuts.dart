/// 桌面端应用级快捷键的键位与意图：骨架（`home_page.dart`）与终端
/// （`ssh/terminal_interactions.dart`）共用一份。
///
/// 为什么终端也要插一脚：终端聚焦时（也就是这个应用最常态的样子）xterm 会
/// 先把 Ctrl+字母 当控制字符发给远端，`_handleKeyEvent` 一旦认下就不再往上
/// 传，骨架那层的键位表根本轮不到——非 Apple 平台上 Ctrl+N / Ctrl+F / Ctrl+T
/// 因此写着却按不出来（实测见 `test/terminal_app_shortcut_test.dart`）。
/// 终端自己那张键位表排在 keyInput 之前，把同一批键位绑成同一批意图之后，
/// 动作照旧由骨架那层的 `Actions` 提供（沿树向上找得到），键位只有一处来源。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_locale.dart';

/// 侧边栏收起 / 展开。
class ToggleSidebarIntent extends Intent {
  const ToggleSidebarIntent();
}

/// 跳到侧边栏的主机搜索框。
class FocusHostSearchIntent extends Intent {
  const FocusHostSearchIntent();
}

/// 新建连接。
class NewConnectionIntent extends Intent {
  const NewConnectionIntent();
}

/// 给当前选中的主机再开一条会话。
class NewSessionIntent extends Intent {
  const NewSessionIntent();
}

/// 打开设置。
class OpenSettingsIntent extends Intent {
  const OpenSettingsIntent();
}

/// 快捷键帮助。
class ShortcutsHelpIntent extends Intent {
  const ShortcutsHelpIntent();
}

/// 切到当前主机的第 [ordinal] 条会话（1 起）。
class SwitchSessionIntent extends Intent {
  const SwitchSessionIntent(this.ordinal);

  final int ordinal;
}

/// ⌘1…⌘9 用到的数字键（终端字号缩放用的是无修饰键的 0，不冲突）。
const List<LogicalKeyboardKey> sessionDigitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

/// 应用级键位表：Apple 平台用 ⌘，其余平台用 Ctrl。
///
/// 非 Apple 平台的侧边栏是 **Ctrl+Shift+B**，不是 Ctrl+B：终端里 Ctrl+B 是
/// tmux 的前缀键，键盘焦点又基本都在终端上，抢走它等于让 tmux 用户按不出
/// 前缀（macOS 的 ⌘B 没有这个问题）。Ctrl+Shift+B 在终端里没有别的含义。
Map<ShortcutActivator, Intent> appShortcutIntents() {
  final meta = usesAppleShortcutSyntax;
  SingleActivator mod(LogicalKeyboardKey key, {bool shift = false}) => meta
      ? SingleActivator(key, meta: true, shift: shift)
      : SingleActivator(key, control: true, shift: shift);
  return {
    mod(LogicalKeyboardKey.keyB, shift: !meta): const ToggleSidebarIntent(),
    mod(LogicalKeyboardKey.keyF): const FocusHostSearchIntent(),
    mod(LogicalKeyboardKey.keyN): const NewConnectionIntent(),
    mod(LogicalKeyboardKey.keyT): const NewSessionIntent(),
    mod(LogicalKeyboardKey.comma): const OpenSettingsIntent(),
    mod(LogicalKeyboardKey.slash): const ShortcutsHelpIntent(),
    for (var i = 0; i < sessionDigitKeys.length; i++)
      mod(sessionDigitKeys[i]): SwitchSessionIntent(i + 1),
  };
}

/// 会被终端自己吃掉的键位：xterm 的字符映射表把 Ctrl+字母 变成控制字符
/// （^F / ^N / ^T 各自有 readline 含义），只有先由终端那张键位表认下来，应用级
/// 的动作才轮得到。取的是 [appShortcutIntents] 里带 Ctrl 的那几颗——非 Apple
/// 平台的键位表本来就没有裸 Ctrl+B（那是 tmux 前缀，见那边），对应的是
/// Ctrl+Shift+B，一并被这里的条件捞进来。Ctrl+, 与 Ctrl+/ 不在 [appShortcutIntents]
/// 的 Ctrl 名单里，xterm 也不认它们，本来就会冒到骨架那一层（实测）。
///
/// Apple 平台返回空表：那边用的是 ⌘，xterm 不认 meta，键位本来就冒得上去。
Map<ShortcutActivator, Intent> terminalAppShortcutIntents() {
  final swallowed = <LogicalKeyboardKey>{
    LogicalKeyboardKey.keyB,
    LogicalKeyboardKey.keyF,
    LogicalKeyboardKey.keyN,
    LogicalKeyboardKey.keyT,
  };
  return {
    for (final entry in appShortcutIntents().entries)
      if (entry.key case SingleActivator(control: true, :final trigger)
          when swallowed.contains(trigger))
        entry.key: entry.value,
  };
}

/// 把 [appShortcutIntents] 里的意图接到骨架的动作上。
///
/// 意图与动作分居两处是刻意的：意图可以绑在终端那张更近的键位表上，动作仍由
/// 骨架持有（`ServerStore` / `SessionManager` 都在它手里）。
Map<Type, Action<Intent>> appShortcutActions({
  required VoidCallback onToggleSidebar,
  required VoidCallback onFocusHostSearch,
  required VoidCallback onNewConnection,
  required VoidCallback onNewSession,
  required VoidCallback onOpenSettings,
  required VoidCallback onShortcutsHelp,
  required ValueChanged<int> onSwitchSession,
}) => {
  ToggleSidebarIntent: CallbackAction<ToggleSidebarIntent>(
    onInvoke: (_) {
      onToggleSidebar();
      return null;
    },
  ),
  FocusHostSearchIntent: CallbackAction<FocusHostSearchIntent>(
    onInvoke: (_) {
      onFocusHostSearch();
      return null;
    },
  ),
  NewConnectionIntent: CallbackAction<NewConnectionIntent>(
    onInvoke: (_) {
      onNewConnection();
      return null;
    },
  ),
  NewSessionIntent: CallbackAction<NewSessionIntent>(
    onInvoke: (_) {
      onNewSession();
      return null;
    },
  ),
  OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(
    onInvoke: (_) {
      onOpenSettings();
      return null;
    },
  ),
  ShortcutsHelpIntent: CallbackAction<ShortcutsHelpIntent>(
    onInvoke: (_) {
      onShortcutsHelp();
      return null;
    },
  ),
  SwitchSessionIntent: CallbackAction<SwitchSessionIntent>(
    onInvoke: (intent) {
      onSwitchSession(intent.ordinal);
      return null;
    },
  ),
};
