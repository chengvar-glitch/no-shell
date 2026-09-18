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

/// 侧边栏收起的快捷键写法：macOS 是 ⌘B，Windows / Linux 是 Ctrl+B。
/// 快捷键本身两端都绑（见 HomePage 的 CallbackShortcuts），文案不能只写 ⌘。
String get sidebarToggleShortcut =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS ? '⌘B' : 'Ctrl+B';
