import 'package:flutter/material.dart';

import '../app_locale.dart';
import '../app_version.dart';
import '../l10n/generated/app_localizations.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets/app_icon_mark.dart';
import '../widgets/settings_controls.dart';

/// 设置 Tab：提供外观（主题模式 / 界面字体）、语言与终端样式（预设 / 字体）。
class SettingsTab extends StatelessWidget {
  const SettingsTab({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onLanguageChanged,
    required this.uiFont,
    required this.onUiFontChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final UiFont uiFont;
  final ValueChanged<UiFont> onUiFontChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navSettings)),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          _sectionHeader(context, l10n.appearance),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text(l10n.followSystem),
                  icon: const Icon(Icons.brightness_auto_outlined, size: 16),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text(l10n.light),
                  icon: const Icon(Icons.light_mode_outlined, size: 16),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text(l10n.dark),
                  icon: const Icon(Icons.dark_mode_outlined, size: 16),
                ),
              ],
              selected: {themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  onThemeModeChanged(selection.first),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: UiFontDropdown(value: uiFont, onChanged: onUiFontChanged),
          ),
          const Divider(height: 32),
          _sectionHeader(context, l10n.terminal),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TerminalPresetDropdown(),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TerminalFontDropdown(),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TerminalFontSizeControl(),
          ),
          const Divider(height: 32),
          _sectionHeader(context, l10n.language),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<AppLanguage>(
              segments: [
                for (final option in AppLanguage.values)
                  ButtonSegment(value: option, label: Text(option.label(l10n))),
              ],
              selected: {language},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  onLanguageChanged(selection.first),
            ),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: Text(l10n.biometricLock),
            subtitle: Text(l10n.comingSoon),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.about),
            subtitle: Text('${l10n.appName} v$appVersion'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: l10n.appName,
              applicationVersion: appVersion,
              applicationIcon: const AppIconMark(size: 40),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: theme.secondaryText,
        ),
      ),
    );
  }
}
