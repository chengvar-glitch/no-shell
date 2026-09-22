import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

Map<ShortcutActivator, Intent> get defaultTerminalShortcuts {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.linux:
    case TargetPlatform.windows:
      return _defaultShortcuts;
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return _defaultAppleShortcuts;
  }
}

final _defaultShortcuts = {
  SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true):
      CopySelectionTextIntent.copy,
  SingleActivator(LogicalKeyboardKey.keyV, control: true):
      const PasteTextIntent(SelectionChangedCause.keyboard),
  // No upstream binding for Ctrl+A / Ctrl+Insert / Shift+Insert: Ctrl+A is
  // "move to beginning of line" in readline/zsh and must reach the shell.
  // No terminal emulator binds select-all to it.
};

final _defaultAppleShortcuts = {
  SingleActivator(LogicalKeyboardKey.keyC, meta: true):
      CopySelectionTextIntent.copy,
  SingleActivator(LogicalKeyboardKey.keyV, meta: true):
      const PasteTextIntent(SelectionChangedCause.keyboard),
  SingleActivator(LogicalKeyboardKey.keyA, meta: true):
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
};
