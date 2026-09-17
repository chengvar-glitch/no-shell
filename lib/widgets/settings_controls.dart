import 'package:flutter/material.dart';
import 'package:xterm/ui.dart';

import '../l10n/generated/app_localizations.dart';
import '../settings.dart';
import '../theme.dart';

/// 设置面板共用件：分组卡片（[SettingsSection] / [SettingsCard] /
/// [SettingsRow]）、统一的图标按钮 [SettingsIconButton]，以及各处共用的
/// 具体控件（界面字体、终端配色 / 字体 / 字号 / 预览）。
/// 移动端设置 Tab 与桌面端设置弹窗共用，保证两端观感与行为一致。

/// 分组卡片内容的左内边距：与分区标题文字落在同一条竖线上
/// （标题图标 [kSettingsSectionIconSize] + 间距 [kSettingsSectionIconGap]）。
const double kSettingsRowInset = 21;

/// 分区标题的图标尺寸与它到标题文字的间距。
const double kSettingsSectionIconSize = 14;
const double kSettingsSectionIconGap = 7;

/// 下拉 / 输入类控件的文字：与设置行标签同一号字（默认 titleMedium 的 16
/// 在设置面板里偏大，窄屏也更容易顶破卡片宽度）。
///
/// 颜色必须显式给：下拉按钮和它的菜单项是用 `DefaultTextStyle(style: _textStyle)`
/// 直接替换环境样式的（见 DropdownButton 内部实现），样式里缺颜色就等于丢掉了
/// 文字颜色，按钮与菜单项会一起变成近白色的「泛白」。
TextStyle _dropdownTextStyle(ThemeData theme) =>
    TextStyle(fontSize: 13, color: theme.colorScheme.onSurface);

/// 设置分区：图标 + 标题 + 一张分组卡片。
///
/// 不写分区说明：标题已经说清是什么，多一行小字只是噪音（简约留白优先）。
/// 卡片不描边、组内也不画分隔线，层次由底色与间距承担。
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: kSettingsSectionIconSize,
                color: theme.secondaryText,
              ),
              const SizedBox(width: kSettingsSectionIconGap),
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
          const SizedBox(height: 12),
          SettingsCard(children: children),
        ],
      ),
    );
  }
}

/// 分组卡片：面板底色的圆角块，不描边、组内不画分隔线。
/// 页面铺页面底色——与主界面同一套层级（画布一色，卡片亮一档）。
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.panelBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// 一块设置：名称一行、控件一行。
/// 控件拿到的是整行宽度，配色选择器 / 预览这类宽控件才排得开。
class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, this.label, required this.child});

  /// 分区标题已经说明是什么时（如语言）可以省掉这一行。
  final String? label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = this.label;
    return Padding(
      // 上下各 14：相邻两项之间留出 28 的空隙，不用分隔线也分得开。
      padding: const EdgeInsets.fromLTRB(
        kSettingsRowInset,
        14,
        kSettingsRowInset,
        14,
      ),
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

/// 设置面板统一的小图标按钮：30×30 命中区、悬停铺一层浅色浮层。
/// 关闭弹窗、终端字号增减都用它，尺寸与反馈保持一致；
/// [onPressed] 为 null 时置灰并交出光标（到达上下限）。
class SettingsIconButton extends StatefulWidget {
  const SettingsIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.iconSize = 18,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double iconSize;

  @override
  State<SettingsIconButton> createState() => _SettingsIconButtonState();
}

class _SettingsIconButtonState extends State<SettingsIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = widget.onPressed != null;
    final hovered = enabled && _hovered;
    final Color foreground;
    if (!enabled) {
      foreground = theme.secondaryText.withValues(alpha: 0.3);
    } else if (hovered) {
      foreground = theme.colorScheme.onSurface;
    } else {
      foreground = theme.secondaryText;
    }
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
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
              color: hovered
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(widget.icon, size: widget.iconSize, color: foreground),
          ),
        ),
      ),
    );
  }
}

/// 界面字体下拉：受控组件，由调用方持有选中值。
/// 字段自带标签一律不画，名称由外层 [SettingsRow] 提供。
class UiFontDropdown extends StatelessWidget {
  const UiFontDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final UiFont value;
  final ValueChanged<UiFont> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DropdownButtonFormField<UiFont>(
      initialValue: value,
      // 窄屏（手机 390pt）下卡片内边距吃掉宽度，长标签必须能省略而不是溢出。
      isExpanded: true,
      style: _dropdownTextStyle(Theme.of(context)),
      decoration: const InputDecoration(),
      items: [
        for (final font in UiFont.values)
          DropdownMenuItem(
            value: font,
            child: Text(
              font.label(l10n),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (font) {
        if (font != null) onChanged(font);
      },
    );
  }
}

/// 终端配色预设下拉：选中态与写入都走全局 [TerminalStyleScope]。
/// 每个选项带配色缩略色卡，直观区分深浅。窄屏用下拉，宽屏用色卡平铺
/// （见设置弹窗的配色选择器）。
class TerminalPresetDropdown extends StatelessWidget {
  const TerminalPresetDropdown({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hairline = Theme.of(context).hairline;
    final scope = TerminalStyleScope.of(context);
    return ValueListenableBuilder<TerminalStylePrefs>(
      valueListenable: scope.notifier,
      builder: (context, prefs, _) {
        return DropdownButtonFormField<TerminalPreset>(
          initialValue: prefs.preset,
          isExpanded: true,
          style: _dropdownTextStyle(Theme.of(context)),
          decoration: const InputDecoration(),
          items: [
            for (final preset in TerminalPreset.values)
              DropdownMenuItem(
                value: preset,
                child: Row(
                  children: [
                    _PresetSwatch(theme: preset.theme, hairline: hairline),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        preset.label(l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (preset) {
            if (preset != null) {
              scope.notifier.value = prefs.copyWith(preset: preset);
            }
          },
        );
      },
    );
  }
}

/// 终端字体下拉：选中态与写入都走全局 [TerminalStyleScope]。
/// 选到「自定义」时就地展开一个字体名输入框：系统字体枚举各平台差异太大，
/// 先让用户直接填已安装的字体族名，填错按回退链降级。
class TerminalFontDropdown extends StatefulWidget {
  const TerminalFontDropdown({super.key});

  @override
  State<TerminalFontDropdown> createState() => _TerminalFontDropdownState();
}

class _TerminalFontDropdownState extends State<TerminalFontDropdown> {
  final _nameController = TextEditingController();
  bool _nameReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 只灌一次初始值：之后以输入框为准，避免每次重建把光标顶回开头。
    if (!_nameReady) {
      _nameController.text = TerminalStyleScope.of(context)
          .notifier
          .value
          .customFontName;
      _nameReady = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scope = TerminalStyleScope.of(context);
    return ValueListenableBuilder<TerminalStylePrefs>(
      valueListenable: scope.notifier,
      builder: (context, prefs, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<TerminalFont>(
              initialValue: prefs.font,
              isExpanded: true,
              style: _dropdownTextStyle(Theme.of(context)),
              decoration: const InputDecoration(),
              items: [
                for (final font in TerminalFont.values)
                  DropdownMenuItem(
                    value: font,
                    child: Text(
                      font.label(l10n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (font) {
                if (font != null) {
                  scope.notifier.value = prefs.copyWith(font: font);
                }
              },
            ),
            if (prefs.font == TerminalFont.custom) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: l10n.terminalFontCustomName,
                  hintText: l10n.terminalFontCustomHint,
                ),
                onChanged: (name) {
                  scope.notifier.value = prefs.copyWith(customFontName: name);
                },
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 终端字号：范围固定、步进 1，改动立刻反映到终端与预览。
class TerminalFontSizeControl extends StatelessWidget {
  const TerminalFontSizeControl({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scope = TerminalStyleScope.of(context);
    return ValueListenableBuilder<TerminalStylePrefs>(
      valueListenable: scope.notifier,
      builder: (context, prefs, _) {
        final size = prefs.fontSize;
        return InputDecorator(
          decoration: const InputDecoration(isDense: true),
          child: Row(
            children: [
              SettingsIconButton(
                icon: Icons.remove_rounded,
                tooltip: l10n.fontSizeDecrease,
                onPressed: size > TerminalStylePrefs.minFontSize
                    ? () => scope.notifier.value = prefs.withFontSize(size - 1)
                    : null,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '$size',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              SettingsIconButton(
                icon: Icons.add_rounded,
                tooltip: l10n.fontSizeIncrease,
                onPressed: size < TerminalStylePrefs.maxFontSize
                    ? () => scope.notifier.value = prefs.withFontSize(size + 1)
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 终端实时预览：用当前配色与终端字体画一行提示符 + 光标块，
/// 换配色 / 字体时立刻能看到实际效果。桌面弹窗与移动端设置 Tab 共用。
class TerminalPreview extends StatelessWidget {
  const TerminalPreview({super.key});

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
            // 浅色终端预设画在卡片底色上会糊成一片，这条描边是控件的轮廓，
            // 与结构性的 hairline 不是一回事。
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

/// 配色缩略色卡：预设背景打底，中心一枚前景色圆点。
class _PresetSwatch extends StatelessWidget {
  const _PresetSwatch({required this.theme, required this.hairline});

  final TerminalTheme theme;
  final Color hairline;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 14,
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: hairline),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: theme.foreground,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
