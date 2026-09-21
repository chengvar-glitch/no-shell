import 'package:xterm/core.dart';

/// 拖拽在远端看来是什么：按下 / 移动 / 抬起。
enum MouseDragPhase { down, move, up }

/// 把一次鼠标拖动编成转义序列。
///
/// 为什么这一段要自己编：xterm 只编得了按下与抬起——`Terminal.mouseInput`
/// 的 buttonState 只有 up / down 两种，包里也没有任何地方读
/// `PointerInput.move`（那个枚举值是死的）。而「按住左键拖动」正是鼠标模式
/// 的全部意义：vim 里是可视选区、tmux 里是拉分割线、htop 里是点列头。
///
/// 编码按 xterm ctlseqs，与包内 `MouseReporter` 逐字对齐（它没有导出，
/// 按下 / 抬起仍走 `terminal.mouseInput`，所以两边的字节必须一致，
/// 否则同一次拖动在远端看来会前后错位）：
/// - 移动事件的按钮号加 32；抬起固定用按钮号 3；
/// - 坐标 1 起算；
/// - SGR 用 `<` 前缀且抬起是小写 `m`，urxvt 与普通模式用 `M`。
///
/// 普通模式的行号跟着 `MouseReporter` 多加了 1（`32 + y + 1`，y 已是 1 起算）
/// ——那多半是包里的老问题，这里照抄：宁可和按下 / 抬起的坐标一起偏，
/// 也不能让同一次拖动的按下与移动落在不同的行上。
String encodeMouseEvent({
  required MouseDragPhase phase,
  required CellOffset cell,
  required MouseReportMode reportMode,
  int buttonId = 0,
}) {
  final x = cell.x + 1;
  final y = cell.y + 1;
  // 移动带的是「按住的那个键」，抬起固定报 3。
  final id = switch (phase) {
    MouseDragPhase.up => 3,
    MouseDragPhase.move => buttonId + 32,
    MouseDragPhase.down => buttonId,
  };
  switch (reportMode) {
    case MouseReportMode.sgr:
      final sgrId = phase == MouseDragPhase.up ? buttonId : id;
      final suffix = phase == MouseDragPhase.up ? 'm' : 'M';
      return '\x1b[<$sgrId;$x;$y$suffix';
    case MouseReportMode.urxvt:
      return '\x1b[${32 + id};$x;${y}M';
    case MouseReportMode.normal:
    case MouseReportMode.utf:
      // 位置超出编码上限时 xterm 发 NUL（普通模式 223、utf 模式 2015）。
      final limit = reportMode == MouseReportMode.normal ? 223 : 2015;
      final col = x > limit ? '\x00' : String.fromCharCode(32 + x);
      final row = y > limit ? '\x00' : String.fromCharCode(32 + y + 1);
      return '\x1b[M${String.fromCharCode(32 + id)}$col$row';
  }
}
