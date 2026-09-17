import 'package:flutter/material.dart';
import 'package:xterm/ui.dart';

import '../l10n/generated/app_localizations.dart';
import '../settings.dart';
import '../theme.dart';

/// 设置面板共用件：分组卡片（[SettingsSection] / [SettingsCard] /
/// [SettingsRow]）、统一的图标按钮 [SettingsIconButton]，以及各处共用的
/// 具体控件（终端配色 / 字体 / 字号 / 预览）。
/// 移动端设置 Tab 与桌面端设置弹窗共用，保证两端观感与行为一致。
/// 字体只暴露随包内置的两个族与「系统等宽」，不提供自由填写字体名的入口。

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

/// 存档读不出来时的告警卡片。
///
/// 这件事必须说出来：此时主机列表是残缺的、改动也不会落盘，
/// 用户若以为一切正常，就会在「以为已经保存」的情况下继续用下去。
/// 桌面设置弹窗与移动端设置 Tab 顶部共用。
class ArchiveWarningCard extends StatelessWidget {
  const ArchiveWarningCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        decoration: BoxDecoration(
          color: AppPalette.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: AppPalette.warning,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.archiveUnreadableTitle,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.archiveUnreadableHint,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: theme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

/// 终端字体下拉：只列出随包内置的两个族与「系统等宽」，选中态与写入都走
/// 全局 [TerminalStyleScope]。
///
/// 每个选项用它自己的字体渲染：内置字体一定存在，所以列表里看到的就是终端里
/// 会得到的。不再提供「自定义字体名」入口——名字填错时 Linux 上会被 fontconfig
/// 顶替成比例字体，终端网格会直接散架（原因见 [TerminalFont] 的注释）。
class TerminalFontDropdown extends StatelessWidget {
  const TerminalFontDropdown({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scope = TerminalStyleScope.of(context);
    return ValueListenableBuilder<TerminalStylePrefs>(
      valueListenable: scope.notifier,
      builder: (context, prefs, _) {
        return DropdownButtonFormField<TerminalFont>(
          initialValue: prefs.font,
          // 窄屏（手机 390pt）下卡片内边距吃掉宽度，长标签必须能省略而不是溢出。
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
                  // 只覆盖族名，颜色仍由下拉自带的 DefaultTextStyle 提供。
                  style: TextStyle(fontFamily: font.family),
                ),
              ),
          ],
          onChanged: (font) {
            if (font != null) {
              scope.notifier.value = prefs.copyWith(font: font);
            }
          },
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
          // 高度与同行的字体下拉（48）对齐：内容 30 的图标按钮
          // 加上下各 9 的内边距正好撑满，两边不再一高一低。
          // maxHeight 必须钳死：只给 minHeight 时松约束下会撑满可用高度。
          decoration: const InputDecoration(
            isDense: true,
            constraints: BoxConstraints(minHeight: 48, maxHeight: 48),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          ),
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

/// 选中即复制开关：写入走全局 [TerminalStyleScope]，桌面设置弹窗与
/// 移动端设置 Tab 共用，两处观感一致。
class TerminalCopyOnSelectControl extends StatelessWidget {
  const TerminalCopyOnSelectControl({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scope = TerminalStyleScope.of(context);
    return ValueListenableBuilder<TerminalStylePrefs>(
      valueListenable: scope.notifier,
      builder: (context, prefs, _) {
        return Row(
          children: [
            Switch(
              value: prefs.copyOnSelect,
              onChanged: (value) =>
                  scope.notifier.value = prefs.copyWith(copyOnSelect: value),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.copyOnSelectHint,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: theme.secondaryText,
                ),
              ),
            ),
          ],
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
