import 'package:flutter/material.dart';

import '../app_locale.dart';
import '../app_version.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme.dart';
import '../update_check.dart';
import '../widgets/about_dialog.dart';
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
    this.archiveWarning,
    this.allowLegacyHostKeys = false,
    this.onAllowLegacyHostKeysChanged,
    this.updateCheck,
    this.openReleasePage,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;

  /// 主机存档读不出来时设置页顶部的告警卡；由外壳订阅 store 后传入，
  /// 本控件自己不订阅——整页设置控件不该跟着主机状态翻转重建。
  final Widget? archiveWarning;

  /// 连接老设备时是否允许 ssh-rsa（SHA-1）主机密钥。
  final bool allowLegacyHostKeys;
  final ValueChanged<bool>? onAllowLegacyHostKeysChanged;

  /// 版本检测；为 null 时不显示「更新」分区。
  final UpdateCheckService? updateCheck;

  /// 打开发布页的能力；不传时走系统实现。
  final Future<bool> Function(Uri uri)? openReleasePage;

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
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          ?archiveWarning,
          AppearanceSettingsSection(
            themeMode: themeMode,
            onChanged: onThemeModeChanged,
          ),
          TerminalSettingsSection(presetPicker: const TerminalPresetDropdown()),
          LanguageSettingsSection(
            language: language,
            onChanged: onLanguageChanged,
          ),
          ConnectionSettingsSection(
            allowLegacyHostKeys: allowLegacyHostKeys,
            onChanged: onAllowLegacyHostKeysChanged,
          ),
          UpdateSettingsRow(
            updateCheck: updateCheck,
            openReleasePage: openReleasePage,
          ),
          // 信息行不成组：没有分区标题，两张卡片之间只留一段间距。
          SettingsCard(
            children: [
              _MoreRow(
                icon: Icons.info_outline,
                title: l10n.about,
                onTap: () => showAppAboutDialog(
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

/// 信息 / 动作行：图标 + 标题，给了 [onTap] 就整行可点并带右箭头。
/// 左边距与 [SettingsRow] 同一条线，卡片里的内容保持一列。
///
/// 不配副标题：行里只在标题下写小字，而这里能写的只有版本号——它已经
/// 在「更新」那一行（与桌面端同一处），重复一遍只会让人多看一次。
class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.icon, required this.title, this.onTap});

  final IconData icon;
  final String title;
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
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.92),
                ),
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
