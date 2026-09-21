import 'package:flutter/material.dart';
import 'package:xterm/ui.dart';

import '../app_locale.dart';
import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../settings.dart';
import '../theme.dart';
import '../update_check.dart';
import 'confirm_dialog.dart';

/// 设置面板共用件：分组卡片（[SettingsSection] / [SettingsCard] /
/// [SettingsRow]）、统一的图标按钮 [SettingsIconButton]，以及五个分区的
/// 正文（外观 / 终端 / 语言 / 连接 / 更新）与它们用到的具体控件。
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
///
/// 独占一行、撑满整行宽度（与字体下拉、配色选择器同宽），高度不写死：
/// 由主题的输入框装饰加 30 的图标按钮自然撑开。写死高度只在「和字体下拉
/// 并排」时才需要，那套并排布局已经取消。
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

/// 选中即复制开关：写入走全局 [TerminalStyleScope]，桌面设置弹窗与
/// 移动端设置 Tab 共用，两处观感一致。
///
/// 不配说明小字：「选中即复制」四个字已经说完了这件事，开关一拨效果自明。
class TerminalCopyOnSelectControl extends StatelessWidget {
  const TerminalCopyOnSelectControl({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = TerminalStyleScope.of(context);
    return ValueListenableBuilder<TerminalStylePrefs>(
      valueListenable: scope.notifier,
      builder: (context, prefs, _) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Switch(
            value: prefs.copyOnSelect,
            onChanged: (value) =>
                scope.notifier.value = prefs.copyWith(copyOnSelect: value),
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

// ---------------------------------------------------------------------------
// 四个设置分区。桌面设置弹窗与移动端设置 Tab 此前各写一份，内容逐行相同，
// 只有配色选择器的形态（色卡平铺 / 下拉）与外壳的排版不同。

/// 外观分区：主题模式三选一。
class AppearanceSettingsSection extends StatelessWidget {
  const AppearanceSettingsSection({
    super.key,
    required this.themeMode,
    required this.onChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsSection(
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
                  icon: const Icon(Icons.brightness_auto_outlined, size: 15),
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
              onSelectionChanged: (selection) => onChanged(selection.first),
            ),
          ),
        ),
      ],
    );
  }
}

/// 终端分区：配色 / 字体 / 字号 / 预览 / 复制即选中。
///
/// [presetPicker] 由两端决定形态：宽屏（桌面弹窗）用色卡平铺，
/// 窄屏（移动设置 Tab）用下拉——同一个分区的内容只此一份。
class TerminalSettingsSection extends StatelessWidget {
  const TerminalSettingsSection({super.key, required this.presetPicker});

  final Widget presetPicker;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsSection(
      icon: Icons.terminal_rounded,
      title: l10n.terminal,
      children: [
        SettingsRow(label: l10n.terminalPreset, child: presetPicker),
        SettingsRow(
          label: l10n.terminalFont,
          child: const TerminalFontDropdown(),
        ),
        // 字号单独一行、撑满整行：与字体下拉同宽，高度不再写死
        // （并排那套才需要钳高对齐）。
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
    );
  }
}

/// 语言分区。
class LanguageSettingsSection extends StatelessWidget {
  const LanguageSettingsSection({
    super.key,
    required this.language,
    required this.onChanged,
  });

  final AppLanguage language;
  final ValueChanged<AppLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsSection(
      icon: Icons.translate_rounded,
      title: l10n.language,
      children: [
        SettingsRow(
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<AppLanguage>(
              segments: [
                for (final option in AppLanguage.values)
                  ButtonSegment(value: option, label: Text(option.label(l10n))),
              ],
              selected: {language},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => onChanged(selection.first),
            ),
          ),
        ),
      ],
    );
  }
}

/// 连接分区：老旧主机密钥算法兼容与 SFTP 快速预览上限。
class ConnectionSettingsSection extends StatelessWidget {
  const ConnectionSettingsSection({
    super.key,
    required this.allowLegacyHostKeys,
    required this.onChanged,
  });

  final bool allowLegacyHostKeys;

  /// 为 null 时开关不可用（宿主没有接这一项）。
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SettingsSection(
      icon: Icons.lan_outlined,
      title: l10n.connectionSection,
      children: [
        // 不写加粗标题：这一节只有这一个开关，标题只会把小字的意思再说一遍。
        // 小字里保留 `ssh-rsa` 这个词——用户报错时就是这么说的，去掉就搜不到。
        SettingsRow(
          child: Row(
            children: [
              Switch(value: allowLegacyHostKeys, onChanged: onChanged),
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
        SettingsRow(
          label: l10n.quickPreviewLimit,
          child: const QuickPreviewLimitDropdown(),
        ),
      ],
    );
  }
}

/// 快速预览上限下拉：选中态与写入都走全局 [QuickPreviewLimitScope]。
final class QuickPreviewLimitDropdown extends StatelessWidget {
  const QuickPreviewLimitDropdown({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = QuickPreviewLimitScope.notifierOf(context);
    return ValueListenableBuilder<QuickPreviewLimit>(
      valueListenable: notifier,
      builder: (context, limit, _) {
        return DropdownButtonFormField<QuickPreviewLimit>(
          initialValue: limit,
          isExpanded: true,
          style: _dropdownTextStyle(Theme.of(context)),
          decoration: const InputDecoration(),
          items: [
            for (final option in QuickPreviewLimit.values)
              DropdownMenuItem(value: option, child: Text(option.label)),
          ],
          onChanged: (value) {
            if (value != null) notifier.value = value;
          },
        );
      },
    );
  }
}

/// 「有新版本」的小红点：贴在设置入口（桌面侧边栏底部 / 移动端设置 Tab）
/// 与 [UpdateSettingsRow] 的图标上。
///
/// 只做一个点，不在任何地方弹窗：启动时的静默查询是**背景**行为，
/// 不该打断用户，但也不能一声不响（那就等于没做检测）。
///
/// 用主题主色而不是状态红：状态红在本应用里是「连接失败」的语义，
/// 有新版本是件可操作的好事，用红色会把用户吓一跳。
class UpdateAvailableDot extends StatelessWidget {
  const UpdateAvailableDot({super.key, this.size = 7, this.border = 1.5});

  final double size;

  /// 描边宽度：贴在有底色的小图标上时留一圈底色，边界才清楚。
  final double border;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        shape: BoxShape.circle,
        // 点会压在图标上方，靠卡片底色描一圈把它与图标分开。
        border: Border.all(color: theme.panelBackground, width: border),
      ),
    );
  }
}

/// 检查结果该怎么显示。抽成可判定的纯数据，是因为「什么时候该说
/// 『已是最新』、什么时候该说『查失败』」正是最容易出错的地方
/// （查失败被显示成已是最新，用户就白点了一次按钮），单独测它比
/// 在 widget 树上断文案稳得多。
///
/// 结果**顶掉行标题**（[title]），不再另起一块：截图里那种「检查更新 /
/// 当前版本 / 已是最新版本 / 当前版本」四行说两件事的排法太啰嗦，
/// 用户一眼看去不知道该读哪行。
class UpdateResultView {
  const UpdateResultView({
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
    this.newer,
  });

  /// 行标题：没查过是「检查更新」，查过就是结果本身（「已是最新版本」…）。
  final String title;

  /// 标题下那一行小字。
  final String detail;

  final IconData icon;
  final Color color;

  /// 查到的新版本（含说明与发布日期）；只有它是非 null 时才有「更新说明」。
  final UpdateResultNewer? newer;
}

/// 查到比当前新的版本时要展示的东西。
class UpdateResultNewer {
  const UpdateResultNewer({
    required this.latestVersion,
    required this.notes,
    this.publishedAt,
  });

  final String latestVersion;
  final String notes;
  final DateTime? publishedAt;
}

/// 没查过 → 返回 null，行按「还没查」的原样显示。
///
/// 查到结果时返回 [UpdateResultView]：标题换成结果、配色换成状态色，
/// 需要的话再挂一个「更新说明」。
UpdateResultView? updateResultViewOf(
  UpdateCheckService service, {
  required AppLocalizations l10n,
  required ThemeData theme,
}) {
  final current = service.currentVersion;
  final currentLine = l10n.updateRowSubtitle(current);
  // 查过之后的标题不再是无色彩的「检查更新」：颜色本身就是结论的一部分
  // （绿=已最新、主色=有新版本、红=没查成），图标按语义各自给。
  if (service.status == UpdateCheckStatus.checking) {
    return UpdateResultView(
      title: l10n.updateChecking,
      detail: currentLine,
      icon: Icons.sync_rounded,
      color: theme.secondaryText,
    );
  }
  if (service.status == UpdateCheckStatus.failed) {
    final failure = service.failure ?? UpdateCheckFailure.network;
    return UpdateResultView(
      title: _failureText(l10n, failure),
      detail: currentLine,
      icon: Icons.error_outline,
      color: theme.statusColor(ServerStatus.error),
    );
  }
  // 判的是「有没有结论」而不是 `status == done`：启动时从落盘读回来的
  // 结论状态仍是 idle（那次没联网），但它同样是有效结论，照常展示。
  final result = service.result;
  if (result == null) return null;
  if (result.updateAvailable) {
    final publishedAt = result.publishedAt;
    return UpdateResultView(
      title: l10n.updateAvailableSubtitle(result.latestVersion),
      // 发布日期拿不到（结论来自上次会话的落盘记录）时不编一个出来。
      detail: publishedAt == null
          ? currentLine
          : l10n.updateResultDate(formatReleaseDate(publishedAt), current),
      icon: Icons.new_releases_outlined,
      color: theme.colorScheme.primary,
      newer: UpdateResultNewer(
        latestVersion: result.latestVersion,
        notes: result.notes,
        publishedAt: publishedAt,
      ),
    );
  }
  return UpdateResultView(
    title: l10n.updateUpToDate,
    detail: currentLine,
    icon: Icons.check_circle_outline,
    color: theme.statusColor(ServerStatus.connected),
  );
}

/// 手动检查失败时的标题文案。
String _failureText(AppLocalizations l10n, UpdateCheckFailure failure) =>
    switch (failure) {
      UpdateCheckFailure.network => l10n.updateFailedNetwork,
      UpdateCheckFailure.notFound => l10n.updateFailedNotFound,
      UpdateCheckFailure.server => l10n.updateFailedServer,
      UpdateCheckFailure.malformed => l10n.updateFailedMalformed,
      UpdateCheckFailure.unsupported => l10n.updateFailedUnsupported,
    };

/// 版本检测分区：一行（状态 + 当前版本 + 动作按钮），查到什么就把那行
/// 换成结果本身，更新说明按需在行下展开。桌面设置弹窗与移动端设置 Tab
/// 共用，两端观感与行为必须一致。
///
/// [updateCheck] 为 null 时整块不显示（测试或嵌入方没有下发检测服务）。
/// 自带 [ListenableBuilder] 订阅，宿主不必因一次查询结果重建整页。
class UpdateSettingsRow extends StatelessWidget {
  const UpdateSettingsRow({
    super.key,
    required this.updateCheck,
    this.openReleasePage,
    this.showSection = true,
  });

  final UpdateCheckService? updateCheck;

  /// 打开发布页的能力；不传时走条件导出的系统实现（web 桩返回打不开）。
  final Future<bool> Function(Uri uri)? openReleasePage;

  /// 是否连分区标题一并给出。桌面端设置弹窗里自成一节，
  /// 移动端跟在信息行后面时也可以只给一行。
  final bool showSection;

  @override
  Widget build(BuildContext context) {
    final service = updateCheck;
    if (service == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final row = _UpdateRowBody(updateCheck: service, open: openReleasePage);
        return showSection
            ? SettingsSection(
                icon: Icons.system_update_alt_rounded,
                title: AppLocalizations.of(context).updateSection,
                children: [row],
              )
            : SettingsCard(children: [row]);
      },
    );
  }
}

class _UpdateRowBody extends StatefulWidget {
  const _UpdateRowBody({required this.updateCheck, this.open});

  final UpdateCheckService updateCheck;
  final Future<bool> Function(Uri uri)? open;

  @override
  State<_UpdateRowBody> createState() => _UpdateRowBodyState();
}

class _UpdateRowBodyState extends State<_UpdateRowBody> {
  bool _notesExpanded = false;
  bool _opening = false;

  UpdateCheckService get _service => widget.updateCheck;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final view = updateResultViewOf(_service, l10n: l10n, theme: theme);
    // 结果标题的配色：没查过时是普通文字色，查过之后用状态色。
    final titleColor =
        view?.color ?? theme.colorScheme.onSurface.withValues(alpha: 0.92);
    final notes = view?.newer?.notes.trim() ?? '';
    return SettingsRow(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // 结论图标嵌在标题里（一行搞定，不再另起一块）。
                        if (view != null) ...[
                          Padding(
                            // 与 13px 标题的首行文字对齐。
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(view.icon, size: 15, color: view.color),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            view?.title ?? l10n.updateRowTitle,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                              color: titleColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      view?.detail ??
                          l10n.updateRowSubtitle(_service.currentVersion),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: theme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildAction(l10n),
            ],
          ),
          // 更新说明挂在行下（默认收起）：它可能很长，塞进那一行会把布局撑坏。
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _notesExpanded = !_notesExpanded),
                icon: Icon(
                  _notesExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 16,
                ),
                label: Text(l10n.updateNotesToggle),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12.5),
                ),
              ),
            ),
            if (_notesExpanded) ...[
              const SizedBox(height: 2),
              _buildNotes(context, notes),
            ],
          ],
        ],
      ),
    );
  }

  /// 右侧动作：能做的只有一件——检查 / 重试 / 前往下载。
  /// 「已是最新」时没有可做的事，就不摆一个点不动的按钮。
  Widget _buildAction(AppLocalizations l10n) {
    if (_service.status == UpdateCheckStatus.checking) {
      return const Padding(
        padding: EdgeInsets.only(top: 2),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_service.status == UpdateCheckStatus.failed) {
      // 能重试就给「重试」；点多少次都是同样结果的失败（没发过版 /
      // 平台不支持）给「检查」——不摆一个点不动的按钮，但也不让按钮凭空消失。
      final retryable = _retryable(
        _service.failure ?? UpdateCheckFailure.network,
      );
      return _button(
        retryable ? l10n.updateRetry : l10n.updateCheck,
        _checkNow,
        filled: false,
      );
    }
    if (_service.updateAvailable) {
      return _button(
        l10n.updateDownload,
        _opening ? null : _openReleasePage,
        filled: true,
      );
    }
    return _button(l10n.updateCheck, _checkNow, filled: false);
  }

  Widget _button(
    String label,
    VoidCallback? onPressed, {
    required bool filled,
  }) {
    final style = TextStyle(
      fontSize: 13,
      fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
    );
    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: style,
        ),
        child: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        textStyle: style,
      ),
      child: Text(label),
    );
  }

  /// 手动检查。结果顶掉行标题，这里不弹轻提示——同一件事说两遍反而
  /// 让人怀疑到底看哪个。
  Future<void> _checkNow() => _service.check();

  Future<void> _openReleasePage() async {
    final uri = Uri.tryParse(_service.releasePageUrl);
    if (uri == null) return;
    final open = widget.open;
    setState(() => _opening = true);
    final opened = open == null ? await openExternalUrl(uri) : await open(uri);
    if (!mounted) return;
    setState(() => _opening = false);
    if (!opened) {
      showToast(context, AppLocalizations.of(context).updateOpenFailed);
    }
  }

  /// 更新说明：GitHub 的 release body 是 Markdown，这里按纯文本展示——
  /// 去掉标题井号与列表符号即可读，为此引一个 Markdown 渲染器不值得。
  Widget _buildNotes(BuildContext context, String notes) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: theme.pageBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _plainTextNotes(notes),
        style: TextStyle(
          fontSize: 12,
          height: 1.55,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.82),
        ),
      ),
    );
  }
}

/// 点多少次都是同样结果的失败不给重试：查不到发布版说明这个项目还没
/// 发过版，平台不支持更是点烂按钮也不会变。
bool _retryable(UpdateCheckFailure failure) =>
    failure != UpdateCheckFailure.notFound &&
    failure != UpdateCheckFailure.unsupported;

/// 把 release body 收拾成能直接读的纯文本：去掉标题井号、把列表符号
/// 换成 `·`（保留「这是几条」的结构），并去掉首尾空行。
String _plainTextNotes(String notes) {
  final lines = notes
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((line) => line.trim())
      .map((line) {
        final heading = RegExp(r'^#{1,6}\s*').firstMatch(line);
        if (heading != null) return line.substring(heading.end);
        final bullet = RegExp(r'^[-*+]\s+').firstMatch(line);
        if (bullet != null) return '· ${line.substring(bullet.end)}';
        return line;
      })
      .toList();
  while (lines.isNotEmpty && lines.first.isEmpty) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines.join('\n');
}
