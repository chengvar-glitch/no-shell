import 'package:flutter/material.dart';

import '../app_locale.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme.dart';

/// 键盘快捷键帮助弹窗（桌面端）。
///
/// 只汇总、不教学：一节「通用」、一节「终端」，每行左边是动作、右边是键位。
/// 键位文案统一由 app_locale.dart 的 shortcut* 取值器按平台生成，
/// 与 CallbackShortcuts 里真正绑定的键位一一对应——改键位时两边一起改。
Future<void> showShortcutHelpDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const ShortcutHelpDialog(),
  );
}

/// 一条「动作 → 键位」。
class _ShortcutRowSpec {
  const _ShortcutRowSpec(this.label, this.keys);

  final String label;
  final String keys;
}

class ShortcutHelpDialog extends StatelessWidget {
  const ShortcutHelpDialog({super.key});

  List<_ShortcutRowSpec> _generalRows(AppLocalizations l10n) => [
    _ShortcutRowSpec(l10n.newConnection, newConnectionShortcut),
    _ShortcutRowSpec(l10n.shortcutSearchHosts, searchHostsShortcut),
    _ShortcutRowSpec(l10n.newSession, newSessionShortcutLabel),
    _ShortcutRowSpec(l10n.shortcutSwitchSession, sessionSwitchShortcut),
    _ShortcutRowSpec(l10n.shortcutToggleSidebar, sidebarToggleShortcut),
    _ShortcutRowSpec(l10n.shortcutOpenSettings, openSettingsShortcut),
    _ShortcutRowSpec(l10n.shortcutShortcutsHelp, shortcutsHelpShortcut),
  ];

  List<_ShortcutRowSpec> _terminalRows(AppLocalizations l10n) => [
    _ShortcutRowSpec(l10n.shortcutFontZoom, terminalFontZoomShortcut),
    _ShortcutRowSpec(l10n.shortcutFontReset, terminalFontResetShortcut),
    _ShortcutRowSpec(l10n.shortcutFindInTerminal, terminalFindShortcut),
    _ShortcutRowSpec(l10n.shortcutCopyPaste, terminalClipboardShortcut),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.keyboardShortcuts),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _sectionHeader(l10n.shortcutSectionGeneral, theme),
              for (final row in _generalRows(l10n)) _row(row, theme),
              const SizedBox(height: 14),
              _sectionHeader(l10n.shortcutSectionTerminal, theme),
              for (final row in _terminalRows(l10n)) _row(row, theme),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.done),
        ),
      ],
    );
  }

  Widget _sectionHeader(String text, ThemeData theme) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: theme.secondaryText,
      ),
    ),
  );

  Widget _row(_ShortcutRowSpec row, ThemeData theme) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(child: Text(row.label, style: const TextStyle(fontSize: 13))),
        const SizedBox(width: 12),
        Text(
          row.keys,
          style: TextStyle(
            fontSize: 12.5,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: theme.secondaryText,
          ),
        ),
      ],
    ),
  );
}
