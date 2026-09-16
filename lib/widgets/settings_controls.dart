import 'package:flutter/material.dart';
import 'package:xterm/ui.dart';

import '../l10n/generated/app_localizations.dart';
import '../settings.dart';
import '../theme.dart';

/// 设置面板共用控件：界面字体、终端配色预设与终端字体。
/// 移动端设置 Tab 与桌面端设置弹窗共用，保证行为一致。

/// 界面字体下拉：受控组件，由调用方持有选中值。
/// [showLabel] 为 false 时不画字段自带标签，由外层的设置行提供标签。
class UiFontDropdown extends StatelessWidget {
  const UiFontDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.showLabel = true,
  });

  final UiFont value;
  final ValueChanged<UiFont> onChanged;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DropdownButtonFormField<UiFont>(
      initialValue: value,
      decoration: InputDecoration(labelText: showLabel ? l10n.appFont : null),
      items: [
        for (final font in UiFont.values)
          DropdownMenuItem(value: font, child: Text(font.label(l10n))),
      ],
      onChanged: (font) {
        if (font != null) onChanged(font);
      },
    );
  }
}

/// 终端配色预设下拉：选中态与写入都走全局 [TerminalStyleScope]。
/// 每个选项带配色缩略色卡，直观区分深浅。
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
          decoration: InputDecoration(labelText: l10n.terminalPreset),
          items: [
            for (final preset in TerminalPreset.values)
              DropdownMenuItem(
                value: preset,
                child: Row(
                  children: [
                    _PresetSwatch(theme: preset.theme, hairline: hairline),
                    const SizedBox(width: 8),
                    Text(preset.label(l10n)),
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
/// [showLabel] 为 false 时不画字段自带标签，由外层的设置行提供标签。
class TerminalFontDropdown extends StatefulWidget {
  const TerminalFontDropdown({super.key, this.showLabel = true});

  final bool showLabel;

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
              decoration: InputDecoration(
                labelText: widget.showLabel ? l10n.terminalFont : null,
              ),
              items: [
                for (final font in TerminalFont.values)
                  DropdownMenuItem(value: font, child: Text(font.label(l10n))),
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
  const TerminalFontSizeControl({super.key, this.showLabel = true});

  final bool showLabel;

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
          decoration: InputDecoration(
            labelText: showLabel ? l10n.terminalFontSize : null,
            isDense: true,
          ),
          child: Row(
            children: [
              _SizeStepButton(
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
              _SizeStepButton(
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

/// 字号步进按钮：与设置面板其它小按钮同一套尺寸与悬停反馈。
class _SizeStepButton extends StatelessWidget {
  const _SizeStepButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      color: theme.secondaryText,
      disabledColor: theme.secondaryText.withValues(alpha: 0.3),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 30, height: 28),
      onPressed: onPressed,
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
