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

/// 桌面快捷键的修饰键约定：Apple 平台用 ⌘ 符号（⌘N），其余写 Ctrl+N。
/// 键位本身在 app_shortcuts.dart 里按同一条判据分叉（见那里的 appShortcutIntents），
/// 文案与键位不能各判各的——这里只负责写法，那边负责绑定。
bool get usesAppleShortcutSyntax =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// [key] 是单个键名（如 `N`、`,`）；组合符号跟随平台习惯
/// （macOS 无 + 号，其余平台以 + 连接）。
String shortcutCombo(String key) =>
    usesAppleShortcutSyntax ? '⌘$key' : 'Ctrl+$key';

/// 侧边栏收展的快捷键写法：macOS 是 ⌘B，Windows / Linux 是 Ctrl+Shift+B
/// （Ctrl+B 是 tmux 的前缀键，得留给终端，见 app_shortcuts.dart）。
String get sidebarToggleShortcut =>
    usesAppleShortcutSyntax ? '⌘B' : 'Ctrl+Shift+B';

/// 桌面全局快捷键的文案：新建连接 / 搜索主机 / 打开设置 / 快捷键帮助。
String get newConnectionShortcut => shortcutCombo('N');
String get searchHostsShortcut => usesAppleShortcutSyntax ? '⌘F' : 'Ctrl+F';
String get openSettingsShortcut => shortcutCombo(',');
String get shortcutsHelpShortcut => shortcutCombo('/');

/// 多会话键位（⌘T 与 ⌘1…⌘9）。
String get newSessionShortcutLabel => shortcutCombo('T');
String get sessionSwitchShortcut =>
    usesAppleShortcutSyntax ? '⌘1…⌘9' : 'Ctrl+1…Ctrl+9';

/// 终端键位：字号缩放（Apple 用 Cmd，其余 Ctrl）、恢复默认、查找。
/// 查找在非 Apple 平台是 Ctrl+Shift+F——裸 Ctrl+F 在 shell 里是
/// readline 的「向右一个字符」，不能抢（见 terminal_interactions.dart）。
String get terminalFontZoomShortcut =>
    usesAppleShortcutSyntax ? '⌘+ / ⌘-' : 'Ctrl+= / Ctrl+-';
String get terminalFontResetShortcut => shortcutCombo('0');
String get terminalFindShortcut =>
    usesAppleShortcutSyntax ? '⌘F' : 'Ctrl+Shift+F';

/// 终端剪贴板的分项写法（工具条 tooltip 用）：Apple 是 ⌘C / ⌘V / ⌘A；
/// 其余平台复制是 Ctrl+Shift+C（Ctrl+C 是中断信号）、粘贴是 Ctrl+V，
/// 全选是 Ctrl+Shift+A——Ctrl+A 在 shell 里是「回行首」，只能让位
/// （GNOME Terminal 用的是同一个键位）。
String get terminalCopyShortcut =>
    usesAppleShortcutSyntax ? '⌘C' : 'Ctrl+Shift+C';
String get terminalPasteShortcut => usesAppleShortcutSyntax ? '⌘V' : 'Ctrl+V';
String get terminalSelectAllShortcut =>
    usesAppleShortcutSyntax ? '⌘A' : 'Ctrl+Shift+A';

/// 非 Apple 平台「有选区时 Ctrl+C 也是复制」；Apple 那边 ⌘C 已经说完了，
/// 返回 null 表示不单列一行。
String? get terminalCopySelectionShortcut =>
    usesAppleShortcutSyntax ? null : 'Ctrl+C';

/// SFTP 地址栏进编辑态：Ctrl+L / ⌘L（GNOME 文件管理器同款键位）。
String get sftpPathEditShortcut => shortcutCombo('L');
