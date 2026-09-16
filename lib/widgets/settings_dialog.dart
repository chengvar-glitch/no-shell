import 'package:flutter/material.dart';

import '../app_locale.dart';
import '../app_version.dart';
import '../l10n/generated/app_localizations.dart';
import '../settings.dart';
import '../theme.dart';
import 'app_icon_mark.dart';
import 'settings_controls.dart';

/// 桌面端设置弹窗：外观（主题 / 界面字体）、终端（配色 / 字体 / 预览）与语言。
///
/// 所有改动都即时生效——各自回调直接写根状态或全局作用域，
/// 因此底部只有「完成」，没有也不需要有「保存」。
Future<void> showSettingsDialog(
  BuildContext context, {
  required ThemeMode themeMode,
  required ValueChanged<ThemeMode> onThemeModeChanged,
  required AppLanguage language,
  required ValueChanged<AppLanguage> onLanguageChanged,
  required UiFont uiFont,
  required ValueChanged<UiFont> onUiFontChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SettingsDialog(
      initialThemeMode: themeMode,
      onThemeModeChanged: onThemeModeChanged,
      initialLanguage: language,
      onLanguageChanged: onLanguageChanged,
      initialUiFont: uiFont,
      onUiFontChanged: onUiFontChanged,
    ),
  );
}

final class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.initialThemeMode,
    required this.onThemeModeChanged,
    required this.initialLanguage,
    required this.onLanguageChanged,
    required this.initialUiFont,
    required this.onUiFontChanged,
  });

  final ThemeMode initialThemeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final AppLanguage initialLanguage;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final UiFont initialUiFont;
  final ValueChanged<UiFont> onUiFontChanged;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

final class _SettingsDialogState extends State<_SettingsDialog> {
  late ThemeMode _themeMode = widget.initialThemeMode;
  late AppLanguage _language = widget.initialLanguage;
  late UiFont _uiFont = widget.initialUiFont;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // 低分辨率兜底：弹窗不高于窗口，内容区自己滚动。
    final maxHeight = (MediaQuery.sizeOf(context).height - 96)
        .clamp(320.0, 760.0)
        .toDouble();
    return Dialog(
      backgroundColor: theme.panelBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(32),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.hairline),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 620, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, theme, l10n),
            Container(height: 1, color: theme.hairline),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Section(
                      icon: Icons.palette_outlined,
                      title: l10n.appearance,
                      hint: l10n.appearanceHint,
                      children: [
                        _SettingBlock(
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
                              style: _segmentedStyle,
                              onSelectionChanged: (selection) {
                                setState(() => _themeMode = selection.first);
                                widget.onThemeModeChanged(selection.first);
                              },
                            ),
                          ),
                        ),
                        _SettingBlock(
                          label: l10n.appFont,
                          child: UiFontDropdown(
                            showLabel: false,
                            value: _uiFont,
                            onChanged: (font) {
                              setState(() => _uiFont = font);
                              widget.onUiFontChanged(font);
                            },
                          ),
                        ),
                      ],
                    ),
                    _Section(
                      icon: Icons.terminal_rounded,
                      title: l10n.terminal,
                      hint: l10n.terminalSectionHint,
                      children: [
                        _SettingBlock(
                          label: l10n.terminalPreset,
                          child: const _PresetPicker(),
                        ),
                        _SettingBlock(
                          label: l10n.terminalFont,
                          child: const TerminalFontDropdown(showLabel: false),
                        ),
                        _SettingBlock(
                          label: l10n.terminalFontSize,
                          child: const TerminalFontSizeControl(
                            showLabel: false,
                          ),
                        ),
                        _SettingBlock(
                          label: l10n.terminalPreview,
                          child: const _TerminalPreview(),
                        ),
                      ],
                    ),
                    _Section(
                      icon: Icons.translate_rounded,
                      title: l10n.language,
                      hint: l10n.languageHint,
                      children: [
                        _SettingBlock(
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
                              style: _segmentedStyle,
                              onSelectionChanged: (selection) {
                                setState(() => _language = selection.first);
                                widget.onLanguageChanged(selection.first);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Container(height: 1, color: theme.hairline),
            _buildFooter(context, theme, l10n),
          ],
        ),
      ),
    );
  }

  /// 分段控件统一小一号字号，和 12.5~13 的设置行同一套节奏。
  static const _segmentedStyle = ButtonStyle(
    textStyle: WidgetStatePropertyAll(
      TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
    ),
    visualDensity: VisualDensity.compact,
  );

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Row(
        children: [
          const AppIconMark(size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.navSettings,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${l10n.appName} · v$appVersion',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: theme.secondaryText),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _HoverIconButton(
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
      padding: const EdgeInsets.fromLTRB(20, 12, 14, 12),
      child: Row(
        children: [
          Icon(
            Icons.bolt_rounded,
            size: 14,
            color: theme.secondaryText.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.settingsApplyHint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: theme.secondaryText),
            ),
          ),
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
    showAboutDialog(
      context: context,
      applicationName: AppLocalizations.of(context).appName,
      applicationVersion: appVersion,
      applicationIcon: const AppIconMark(size: 40),
    );
  }
}

/// 设置分区：图标 + 标题 + 一句说明 + 一张成组的卡片。
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.hint,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: theme.secondaryText),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: theme.secondaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            // 说明与标题文字左对齐（让过图标宽度），读起来是一条注释。
            padding: const EdgeInsets.only(left: 21),
            child: Text(
              hint,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.3,
                color: theme.secondaryText.withValues(alpha: 0.75),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.hoverOverlay,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, thickness: 1, color: theme.hairline),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 一块设置：名称一行、控件一行。
/// 控件拿到的是整行宽度，配色选择器 / 预览这类宽控件才排得开。
class _SettingBlock extends StatelessWidget {
  const _SettingBlock({this.label, required this.child});

  /// 分区标题已经说明是什么时（如语言）可以省掉这一行。
  final String? label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = this.label;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null) ...[
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.92),
              ),
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

/// 终端配色选择器：每块用它自己的配色绘制（背景 + 前景 + 强调色），
/// 选中的一块描边高亮并打勾；比下拉列表更容易一眼比出深浅与色相。
class _PresetPicker extends StatefulWidget {
  const _PresetPicker();

  @override
  State<_PresetPicker> createState() => _PresetPickerState();
}

class _PresetPickerState extends State<_PresetPicker> {
  TerminalPreset? _hovered;

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
                      hovered: preset == _hovered,
                      onHover: (value) =>
                          setState(() => _hovered = value ? preset : null),
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

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.label,
    required this.selected,
    required this.hovered,
    required this.onHover,
    required this.onTap,
  });

  final TerminalPreset preset;
  final String label;
  final bool selected;
  final bool hovered;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = preset.theme;
    final highlight = theme.colorScheme.primary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: colors.foreground,
                      ),
                    ),
                    const SizedBox(height: 7),
                    // 五枚色点就是这套配色的名片：红 / 绿 / 黄 / 蓝 / 品红。
                    Row(
                      children: [
                        for (final color in [
                          colors.red,
                          colors.green,
                          colors.yellow,
                          colors.blue,
                          colors.magenta,
                        ])
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.only(right: 3),
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ],
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

/// 终端实时预览：用当前配色与终端字体画一行提示符 + 光标块，
/// 换配色 / 字体时立刻能看到实际效果。
class _TerminalPreview extends StatelessWidget {
  const _TerminalPreview();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scope = TerminalStyleScope.of(context);
    return ValueListenableBuilder<TerminalStylePrefs>(
      valueListenable: scope.notifier,
      builder: (context, prefs, _) {
        final colors = prefs.theme;
        final size = prefs.fontSize.toDouble();
        final mono = TextStyle(
          fontSize: size,
          height: 1.4,
          fontFamily: prefs.resolvedFontFamily,
          fontFamilyFallback: prefs.fontFallback,
        );
        return Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: mono,
                    children: [
                      TextSpan(
                        text: r'$ ',
                        style: TextStyle(color: colors.green),
                      ),
                      TextSpan(
                        text: l10n.terminalPreviewCommand,
                        style: TextStyle(color: colors.foreground),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: size * 0.5,
                height: size * 1.15,
                color: colors.cursor,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 与自绘标题条同款的小图标按钮：悬停铺一层浅色浮层。
class _HoverIconButton extends StatefulWidget {
  const _HoverIconButton({
    required this.icon,
    required this.iconSize,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final double iconSize;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<_HoverIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _hovered
                  ? theme.colorScheme.onSurface
                  : theme.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}
