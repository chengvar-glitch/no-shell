import 'package:flutter/foundation.dart';

/// 软键盘快捷键条的粘滞修饰键：点一次只作用于「下一个」输入，随后自动落回。
///
/// 触屏上没有「按住 Ctrl 再按字母」这件事——键条与软键盘不是同一块玻璃，
/// 一只手按不出组合键。所以修饰键做成粘滞的：点亮即待命，下一个输入
/// （键条上的键，或软键盘敲下的一个字符）带上它，然后自动熄灭。
final class TerminalInputModifiers extends ChangeNotifier {
  bool _ctrl = false;
  bool _alt = false;
  bool _disposed = false;

  bool get ctrl => _ctrl;
  bool get alt => _alt;

  /// 是否有修饰键处于待命状态（键条据此高亮）。
  bool get isArmed => _ctrl || _alt;

  void toggleCtrl() => _set(ctrl: !_ctrl);

  void toggleAlt() => _set(alt: !_alt);

  void clear() => _set(ctrl: false, alt: false);

  void _set({bool? ctrl, bool? alt}) {
    final nextCtrl = ctrl ?? _ctrl;
    final nextAlt = alt ?? _alt;
    if (nextCtrl == _ctrl && nextAlt == _alt) return;
    _ctrl = nextCtrl;
    _alt = nextAlt;
    // 会话已经回收、但软键盘还在补发按键时不该炸：待命状态照旧更新，
    // 只是不再广播（与 TerminalSession._notify 同一取舍）。
    if (_disposed) return;
    notifyListeners();
  }

  /// 取走待命的修饰键并熄灭：一次输入只吃一次，无论它认不认这个修饰键。
  ({bool ctrl, bool alt}) take() {
    final taken = (ctrl: _ctrl, alt: _alt);
    clear();
    return taken;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 把修饰键作用到一段用户输入上。
///
/// Ctrl 只认单字符里的 ASCII（`a-z` / `A-Z` / `[ \ ] ^ _` / 空格 / `?`），
/// 换成对应的控制码（Ctrl+C → 0x03）；Alt 加 ESC 前缀。认不出来的一律原样
/// 返回——多字符（粘贴、输入法上屏）、中文、本来就带 ESC 的序列都不猜，
/// 宁可少做一次变换，也不能把用户敲进去的东西吞掉或改坏。
String applyTerminalModifiers(
  String text, {
  required bool ctrl,
  required bool alt,
}) {
  if (!ctrl) return alt ? '\x1b$text' : text;
  final control = controlCodeOf(text);
  // Ctrl 认不出来时退回原字符，而不是把这次输入丢掉。
  final result = control ?? text;
  return alt ? '\x1b$result' : result;
}

/// 单字符对应的控制码；不是单字符或没有对应控制码时返回 null。
///
/// 映射按 ASCII 的定义：`@A-Z[\]^_` 是 0x00-0x1F，`?` 是 DEL。小写与大写
/// 等价（Ctrl+C 与 Ctrl+Shift+C 在终端里是同一个码），这是终端的既有语义。
@visibleForTesting
String? controlCodeOf(String text) {
  if (text.length != 1) return null;
  final code = text.codeUnitAt(0);
  if (code >= 0x61 && code <= 0x7A) return String.fromCharCode(code - 0x60);
  if (code >= 0x41 && code <= 0x5A) return String.fromCharCode(code - 0x40);
  if (code >= 0x5B && code <= 0x5F) return String.fromCharCode(code - 0x40);
  if (code == 0x20) return '\x00';
  if (code == 0x3F) return '\x7f';
  return null;
}
