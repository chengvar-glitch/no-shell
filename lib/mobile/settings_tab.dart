import 'package:flutter/material.dart';

import '../app_locale.dart';
import '../app_version.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme.dart';
import '../widgets/app_icon_mark.dart';
import '../widgets/settings_controls.dart';

/// 设置 Tab：外观（主题）、终端（配色 / 字体 / 字号 / 预览）、语言与信息行。
/// 分区卡片与控件全部与桌面设置弹窗共用（见 settings_controls.dart），
/// 两端只有排版宽度与配色选择器的形态不同。
class SettingsTab extends StatelessWidget {
  const SettingsTab({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onLanguageChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      // 与主界面、桌面设置弹窗同一套层级：页面底色画布 + 面板底色卡片，
      // 不靠描边与分隔线，只靠底色差与留白。
      backgroundColor: theme.pageBackground,
      appBar: AppBar(
        title: Text(l10n.navSettings),
        backgroundColor: theme.pageBackground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          SettingsSection(
            icon: Icons.palette_outlined,
            title: l10n.appearance,
            children: [
              SettingsRow(
                label: l10n.theme,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<ThemeMode>(
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(l10n.followSystem),
                        icon: const Icon(
                          Icons.brightness_auto_outlined,
                          size: 15,
                        ),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text(l10n.light),
                        icon: const Icon(Icons.light_mode_outlined, size: 15),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text(l10n.dark),
                        icon: const Icon(Icons.dark_mode_outlined, size: 15),
                      ),
                    ],
                    selected: {themeMode},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        onThemeModeChanged(selection.first),
                  ),
                ),
              ),
            ],
          ),
          SettingsSection(
            icon: Icons.terminal_rounded,
            title: l10n.terminal,
            children: [
              SettingsRow(
                label: l10n.terminalPreset,
                child: const TerminalPresetDropdown(),
              ),
              SettingsRow(
                label: l10n.terminalFont,
                child: const TerminalFontDropdown(),
              ),
              SettingsRow(
                label: l10n.terminalFontSize,
                child: const TerminalFontSizeControl(),
              ),
              SettingsRow(
                label: l10n.terminalPreview,
                child: const TerminalPreview(),
              ),
            ],
          ),
          SettingsSection(
            icon: Icons.translate_rounded,
            title: l10n.language,
            children: [
              SettingsRow(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<AppLanguage>(
                    segments: [
                      for (final option in AppLanguage.values)
                        ButtonSegment(
                          value: option,
                          label: Text(option.label(l10n)),
                        ),
                    ],
                    selected: {language},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        onLanguageChanged(selection.first),
                  ),
                ),
              ),
            ],
          ),
          // 信息行不成组：没有分区标题，两张卡片之间只留一段间距。
          SettingsCard(
            children: [
              _MoreRow(
                icon: Icons.fingerprint,
                title: l10n.biometricLock,
                subtitle: l10n.comingSoon,
              ),
              _MoreRow(
                icon: Icons.info_outline,
                title: l10n.about,
                subtitle: '${l10n.appName} v$appVersion',
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: l10n.appName,
                  applicationVersion: appVersion,
                  applicationIcon: const AppIconMark(size: 40),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 信息 / 动作行：图标 + 标题 + 副标题，给了 [onTap] 就整行可点并带右箭头。
/// 左边距与 [SettingsRow] 同一条线，卡片里的内容保持一列。
class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(kSettingsRowInset, 12, 16, 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.secondaryText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.92,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: theme.secondaryText.withValues(alpha: 0.7),
              ),
          ],
        ),
      ),
    );
  }
}
