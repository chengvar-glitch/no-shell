import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'l10n/generated/app_localizations.dart';

/// 应用语言选项：跟随系统 / 简体中文 / English。
///
/// 「跟随系统」映射为 `locale == null`，由 MaterialApp 按 `supportedLocales`
/// 自动解析（zh 系统→中文，其余→英文，英文为兜底语言）。
enum AppLanguage {
  system,
  chinese,
  english;

  Locale? get locale => switch (this) {
    AppLanguage.system => null,
    AppLanguage.chinese => const Locale('zh'),
    AppLanguage.english => const Locale('en'),
  };

  /// 选项展示文案：中文与英文保持各自母语书写，不随界面语言翻译。
  String label(AppLocalizations l10n) => switch (this) {
    AppLanguage.system => l10n.followSystem,
    AppLanguage.chinese => '中文',
    AppLanguage.english => 'English',
  };
}

/// 桌面快捷键的文案写法：Apple 平台用 ⌘ 符号（⌘N），其余写 Ctrl+N。
/// 快捷键本身两端都绑（见 HomePage 的 CallbackShortcuts），文案不能只写 ⌘。
bool get _usesAppleModifiers =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// [key] 是单个键名（如 `N`、`,`）；组合符号跟随平台习惯
/// （macOS 无 + 号，其余平台以 + 连接）。
String shortcutCombo(String key) => _usesAppleModifiers ? '⌘$key' : 'Ctrl+$key';

/// 侧边栏收起的快捷键写法：macOS 是 ⌘B，Windows / Linux 是 Ctrl+B。
String get sidebarToggleShortcut => shortcutCombo('B');

/// 桌面全局快捷键的文案：新建连接 / 搜索主机 / 打开设置 / 快捷键帮助。
String get newConnectionShortcut => shortcutCombo('N');
String get searchHostsShortcut => _usesAppleModifiers ? '⌘F' : 'Ctrl+F';
String get openSettingsShortcut => shortcutCombo(',');
String get shortcutsHelpShortcut => shortcutCombo('/');

/// 多会话键位（⌘T 与 ⌘1…⌘9）。
String get newSessionShortcutLabel => shortcutCombo('T');
String get sessionSwitchShortcut =>
    _usesAppleModifiers ? '⌘1…⌘9' : 'Ctrl+1…Ctrl+9';

/// 终端键位：字号缩放（Apple 用 Cmd，其余 Ctrl）、恢复默认、查找。
/// 查找在非 Apple 平台是 Ctrl+Shift+F——裸 Ctrl+F 在 shell 里是
/// readline 的「向右一个字符」，不能抢（见 terminal_interactions.dart）。
String get terminalFontZoomShortcut =>
    _usesAppleModifiers ? '⌘+ / ⌘-' : 'Ctrl+= / Ctrl+-';
String get terminalFontResetShortcut => shortcutCombo('0');
String get terminalFindShortcut => _usesAppleModifiers ? '⌘F' : 'Ctrl+Shift+F';

/// 终端复制 / 粘贴 / 全选：Apple 是 ⌘C/V/A；其余平台复制是 Ctrl+Shift+C
/// （Ctrl+C 是中断信号）、粘贴是 Ctrl+V，全选没有绑定（Ctrl+A 属于 shell）。
String get terminalClipboardShortcut =>
    _usesAppleModifiers ? '⌘C / ⌘V / ⌘A' : 'Ctrl+Shift+C / Ctrl+V';
