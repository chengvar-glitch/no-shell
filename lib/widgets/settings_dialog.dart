import 'package:flutter/material.dart';

import '../app_locale.dart';
import '../app_version.dart';
import '../l10n/generated/app_localizations.dart';
import '../settings.dart';
import '../theme.dart';
import 'about_dialog.dart';
import 'app_icon_mark.dart';
import 'settings_controls.dart';

/// 桌面端设置弹窗：外观（主题）、终端（配色 / 字体 / 字号 / 预览）与语言。
///
/// 所有改动都即时生效——各自回调直接写根状态或全局作用域，
/// 因此底部只有「完成」，没有也不需要有「保存」。
Future<void> showSettingsDialog(
  BuildContext context, {
  required ThemeMode themeMode,
  required ValueChanged<ThemeMode> onThemeModeChanged,
  required AppLanguage language,
  required ValueChanged<AppLanguage> onLanguageChanged,
  bool archiveUnreadable = false,
  bool allowLegacyHostKeys = false,
  ValueChanged<bool>? onAllowLegacyHostKeysChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SettingsDialog(
      initialThemeMode: themeMode,
      onThemeModeChanged: onThemeModeChanged,
      initialLanguage: language,
      onLanguageChanged: onLanguageChanged,
      archiveUnreadable: archiveUnreadable,
      initialAllowLegacyHostKeys: allowLegacyHostKeys,
      onAllowLegacyHostKeysChanged: onAllowLegacyHostKeysChanged,
    ),
  );
}

final class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.initialThemeMode,
    required this.onThemeModeChanged,
    required this.initialLanguage,
    required this.onLanguageChanged,
    required this.archiveUnreadable,
    required this.initialAllowLegacyHostKeys,
    required this.onAllowLegacyHostKeysChanged,
  });

  final ThemeMode initialThemeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final AppLanguage initialLanguage;
  final ValueChanged<AppLanguage> onLanguageChanged;

  /// 主机存档读不出来：设置页顶部给出告警。
  final bool archiveUnreadable;

  /// 连接老设备时是否允许 ssh-rsa（SHA-1）主机密钥。
  final bool initialAllowLegacyHostKeys;
  final ValueChanged<bool>? onAllowLegacyHostKeysChanged;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

final class _SettingsDialogState extends State<_SettingsDialog> {
  late ThemeMode _themeMode = widget.initialThemeMode;
  late AppLanguage _language = widget.initialLanguage;
  late bool _allowLegacyHostKeys = widget.initialAllowLegacyHostKeys;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // 低分辨率兜底：弹窗不高于窗口，内容区自己滚动。
    final maxHeight = (MediaQuery.sizeOf(context).height - 96)
        .clamp(320.0, 760.0)
        .toDouble();
    return Dialog(
      // 弹窗自己就是一块画布（页面底色），分组卡片才是亮一档的面板底色——
      // 与主界面同一套层级；不描边，靠遮罩把弹窗从底下的界面里分出来。
      backgroundColor: theme.pageBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(32),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 680, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头部 / 内容 / 底部之间不画分隔线：间距与分组卡片的底色已经分好层。
            _buildHeader(context, theme, l10n),
            Flexible(
              child: SingleChildScrollView(
                // 桌面默认的回弹（果冻）效果在设置页没有意义，钳住。
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.archiveUnreadable) const ArchiveWarningCard(),
                    SettingsSection(
                      icon: Icons.palette_outlined,
                      title: l10n.appearance,
                      children: [
                        SettingsRow(
                          label: l10n.theme,
                          // 分段控件给松约束 + 左对齐：保持自身尺寸，
                          // 也不会因为父级紧约束把三段挤出卡片。
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
                                  icon: const Icon(
                                    Icons.light_mode_outlined,
                                    size: 15,
                                  ),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.dark,
                                  label: Text(l10n.dark),
                                  icon: const Icon(
                                    Icons.dark_mode_outlined,
                                    size: 15,
                                  ),
                                ),
                              ],
                              selected: {_themeMode},
                              showSelectedIcon: false,
                              onSelectionChanged: (selection) {
                                setState(() => _themeMode = selection.first);
                                widget.onThemeModeChanged(selection.first);
                              },
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
                          child: const _PresetPicker(),
                        ),
                        SettingsRow(
                          label: l10n.terminalFont,
                          child: const TerminalFontDropdown(),
                        ),
                        // 字号单独一行、撑满整行：与字体下拉同宽，高度不再
                        // 写死（并排那套才需要钳高对齐）。
                        SettingsRow(
                          label: l10n.terminalFontSize,
                          child: const TerminalFontSizeControl(),
                        ),
                        SettingsRow(
                          label: l10n.terminalPreview,
                          child: const TerminalPreview(),
                        ),
                        SettingsRow(
                          label: l10n.copyOnSelect,
                          child: const TerminalCopyOnSelectControl(),
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
                              selected: {_language},
                              showSelectedIcon: false,
                              onSelectionChanged: (selection) {
                                setState(() => _language = selection.first);
                                widget.onLanguageChanged(selection.first);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    SettingsSection(
                      icon: Icons.lan_outlined,
                      title: l10n.connectionSection,
                      children: [
                        SettingsRow(
                          label: l10n.allowLegacyHostKeys,
                          child: Row(
                            children: [
                              Switch(
                                value: _allowLegacyHostKeys,
                                onChanged: (value) {
                                  setState(() => _allowLegacyHostKeys = value);
                                  widget.onAllowLegacyHostKeysChanged?.call(
                                    value,
                                  );
                                },
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  l10n.allowLegacyHostKeysHint,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: theme.secondaryText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            _buildFooter(context, theme, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    // 减重成一行标题：应用身份在侧边栏品牌区已经有了，版本号收进「关于」。
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.navSettings,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          SettingsIconButton(
            icon: Icons.close_rounded,
            iconSize: 15,
            tooltip: l10n.done,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 14, 12),
      child: Row(
        children: [
          const Spacer(),
          TextButton(
            onPressed: () => _showAbout(context),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: const TextStyle(fontSize: 13),
            ),
            child: Text(l10n.about),
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(l10n.done),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAppAboutDialog(
      context: context,
      applicationName: AppLocalizations.of(context).appName,
      applicationVersion: appVersion,
      applicationIcon: const AppIconMark(size: 40),
    );
  }
}

/// 终端配色选择器：每块用它自己的配色绘制背景与文字，选中的一块描边高亮并打勾；
/// 比下拉列表更容易一眼比出深浅与色相，又不至于在卡片里堆一堆装饰。
class _PresetPicker extends StatelessWidget {
  const _PresetPicker();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scope = TerminalStyleScope.of(context);
    return ValueListenableBuilder<TerminalStylePrefs>(
      valueListenable: scope.notifier,
      builder: (context, prefs, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            const gap = 8.0;
            const columns = 3;
            final tileWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final preset in TerminalPreset.values)
                  SizedBox(
                    width: tileWidth,
                    child: _PresetTile(
                      preset: preset,
                      label: preset.label(l10n),
                      selected: preset == prefs.preset,
                      onTap: () =>
                          scope.notifier.value = prefs.copyWith(preset: preset),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// 悬停态收敛在 tile 内部：鼠标扫过时只重建这一块，不惊动整组 tile。
class _PresetTile extends StatefulWidget {
  const _PresetTile({
    required this.preset,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final TerminalPreset preset;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PresetTile> createState() => _PresetTileState();
}

class _PresetTileState extends State<_PresetTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = widget.preset.theme;
    final highlight = theme.colorScheme.primary;
    final hovered = _hovered;
    final selected = widget.selected;
    // 一块 tile 只画两样东西：这套配色的背景 + 名字。五枚色点曾是「配色名片」，
    // 但在简约留白的界面里它是最花的一处，选中态用描边与勾已经说得够清楚。
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? highlight
                  : hovered
                  ? highlight.withValues(alpha: 0.55)
                  : theme.hairline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.foreground,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // 选中标记占位固定：勾出现时不会把标题挤动。
              SizedBox(
                width: 14,
                height: 14,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 130),
                  opacity: selected ? 1 : 0,
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 14,
                    color: highlight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
