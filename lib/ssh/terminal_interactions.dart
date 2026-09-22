import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm/core.dart';
import 'package:xterm/ui.dart';

/// 终端便捷交互的公共件：字号缩放键位、复制 / 粘贴 / 全选动作、
/// 超链接识别。只依赖 xterm 公共 API，web 也要能编译。

/// 双击 / 长按选词的分隔符表。
///
/// fork 默认表把 `-` `.` `:` `/` 都当分隔符，而这些字符在 UUID、文件路径、
/// 域名、IPv6 里是词的一部分——从日志里双击复制一个日志编号
/// （`c8cf4fd4-ed93-…`）或一条路径是运维的高频动作，iTerm2 / GNOME
/// Terminal 的双击都能整条带走。这里去掉这四个；另收中文标点（全角冒号、
/// 逗号、顿号与弯引号），「日志编号：xxx」双击不会把前缀带上。
final Set<int> kTerminalWordSeparators = {
  0, // 宽字符占位格的 codepoint，恒为 0
  ' '.codeUnitAt(0),
  '\t'.codeUnitAt(0),
  '"'.codeUnitAt(0),
  '\''.codeUnitAt(0),
  '`'.codeUnitAt(0),
  '\\'.codeUnitAt(0),
  '*'.codeUnitAt(0),
  '+'.codeUnitAt(0),
  ','.codeUnitAt(0),
  ';'.codeUnitAt(0),
  '('.codeUnitAt(0),
  ')'.codeUnitAt(0),
  '['.codeUnitAt(0),
  ']'.codeUnitAt(0),
  '{'.codeUnitAt(0),
  '}'.codeUnitAt(0),
  '<'.codeUnitAt(0),
  '>'.codeUnitAt(0),
  '|'.codeUnitAt(0),
  '&'.codeUnitAt(0),
  '!'.codeUnitAt(0),
  '?'.codeUnitAt(0),
  '“'.codeUnitAt(0),
  '”'.codeUnitAt(0),
  '‘'.codeUnitAt(0),
  '’'.codeUnitAt(0),
  '：'.codeUnitAt(0),
  '，'.codeUnitAt(0),
  '；'.codeUnitAt(0),
  '、'.codeUnitAt(0),
};

/// Ctrl+C 的处置结论：有选区时复制（Windows Terminal 的默认语义），
/// 没有选区时仍发 ^C 中断。
enum TerminalCtrlCDisposition { copy, interrupt }

/// 判定一次按键是不是「该复制的那个 Ctrl+C」。
///
/// Apple 平台 Cmd+C 已是复制、终端里 Ctrl+C 从不抢，恒为中断；带 Shift /
/// Alt / Meta 的组合各自另有含义（Ctrl+Shift+C 是复制快捷键，落到键位表
/// 那条路），也不拦。判定为 [TerminalCtrlCDisposition.copy] 时调用方必须
/// 把事件标为已处理，否则 ^C 照发、选区就白选了。
TerminalCtrlCDisposition resolveCtrlC(
  KeyEvent event, {
  required bool hasSelection,
}) {
  if (isAppleLikePlatform()) return TerminalCtrlCDisposition.interrupt;
  if (event.logicalKey != LogicalKeyboardKey.keyC) {
    return TerminalCtrlCDisposition.interrupt;
  }
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
    return TerminalCtrlCDisposition.interrupt;
  }
  final keyboard = HardwareKeyboard.instance;
  final plainCtrl =
      keyboard.isControlPressed &&
      !keyboard.isShiftPressed &&
      !keyboard.isAltPressed &&
      !keyboard.isMetaPressed;
  if (!plainCtrl) return TerminalCtrlCDisposition.interrupt;
  return hasSelection
      ? TerminalCtrlCDisposition.copy
      : TerminalCtrlCDisposition.interrupt;
}

/// 终端字号步进意图：[delta] 为 ±1。键位在 [terminalShortcuts] 绑定，
/// 动作方（SshTerminalView）把结果写回全局终端偏好。
class TerminalFontSizeAdjustIntent extends Intent {
  const TerminalFontSizeAdjustIntent(this.delta);

  final int delta;
}

/// 恢复默认字号意图。
class TerminalFontSizeResetIntent extends Intent {
  const TerminalFontSizeResetIntent();
}

/// 打开终端查找意图。
class TerminalSearchIntent extends Intent {
  const TerminalSearchIntent();
}

/// 终端键位表：包默认（复制 / 粘贴 / 全选）+ 字号缩放。
///
/// `TerminalView.shortcuts` 会**整体替换**包的默认表，所以必须把
/// [defaultTerminalShortcuts] 展开合并，否则复制粘贴快捷键会丢。
/// 缩放的修饰键按平台取：Apple 用 Cmd，其余用 Ctrl——Ctrl 系在终端里
/// 有既有含义（Ctrl+C 是中断信号），不能在 macOS 上被缩放抢走。
Map<ShortcutActivator, Intent> terminalShortcuts() {
  final meta = isAppleLikePlatform();
  return {
    ...defaultTerminalShortcuts,
    ..._zoomKeys(
      modifier: meta,
      // Cmd/Ctrl + + 在美式键盘上是 Shift+=，逻辑键仍是 keyEqual；
      // 小键盘加号与「+」字符键各是一枚逻辑键，都要覆盖。
      activators: const [
        SingleActivator(LogicalKeyboardKey.equal),
        SingleActivator(LogicalKeyboardKey.equal, shift: true),
        SingleActivator(LogicalKeyboardKey.add),
        SingleActivator(LogicalKeyboardKey.numpadAdd),
      ],
      intent: const TerminalFontSizeAdjustIntent(1),
    ),
    ..._zoomKeys(
      modifier: meta,
      activators: const [
        SingleActivator(LogicalKeyboardKey.minus),
        SingleActivator(LogicalKeyboardKey.numpadSubtract),
      ],
      intent: const TerminalFontSizeAdjustIntent(-1),
    ),
    ..._zoomKeys(
      modifier: meta,
      activators: const [
        SingleActivator(LogicalKeyboardKey.digit0),
        SingleActivator(LogicalKeyboardKey.numpad0),
      ],
      intent: const TerminalFontSizeResetIntent(),
    ),
    // 查找：Apple 用 Cmd+F；其余平台用 Ctrl+Shift+F——裸 Ctrl+F 在 shell 里
    // 是 readline 的「光标右移一个字符」，抢走它等于让用户按不出这个键
    // （GNOME Terminal / Windows Terminal 也是 Ctrl+Shift+F）。
    if (meta)
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
          const TerminalSearchIntent()
    else
      const SingleActivator(
        LogicalKeyboardKey.keyF,
        control: true,
        shift: true,
      ): const TerminalSearchIntent(),
    // X11 / Windows Terminal 的老键位：Shift+Insert 粘贴、Ctrl+Insert 复制。
    // Apple 平台 Cmd+C/V 已覆盖，不绑。
    if (!meta)
      const SingleActivator(LogicalKeyboardKey.insert, shift: true):
          const PasteTextIntent(SelectionChangedCause.keyboard),
    if (!meta)
      const SingleActivator(LogicalKeyboardKey.insert, control: true):
          CopySelectionTextIntent.copy,
  };
}

Map<ShortcutActivator, Intent> _zoomKeys({
  required bool modifier,
  required List<SingleActivator> activators,
  required Intent intent,
}) => {
  for (final activator in activators)
    modifier
            ? SingleActivator(
                activator.trigger,
                meta: true,
                shift: activator.shift,
              )
            : SingleActivator(
                activator.trigger,
                control: true,
                shift: activator.shift,
              ):
        intent,
};

/// 链接点击等「Apple 系用 Cmd、其余用 Ctrl」场景的平台判断。
/// web 上 defaultTargetPlatform 报告的是浏览器所在系统，一并覆盖。
bool isAppleLikePlatform() =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// 打开链接的修饰键是否正按着：Apple 用 Cmd，其余用 Ctrl。
bool isLinkModifierPressed() => isAppleLikePlatform()
    ? HardwareKeyboard.instance.isMetaPressed
    : HardwareKeyboard.instance.isControlPressed;

/// 把当前选区写入剪贴板。没有选区返回 false，调用方无需重复判空。
Future<bool> copyTerminalSelection(
  Terminal terminal,
  TerminalController controller,
) async {
  final selection = controller.selection;
  if (selection == null) return false;
  await Clipboard.setData(
    ClipboardData(text: terminal.buffer.getText(selection)),
  );
  return true;
}

/// 读剪贴板写入终端（等价于包内 PasteTextIntent 的动作）。
/// 剪贴板为空时不动缓冲区。
Future<void> pasteIntoTerminal(Terminal terminal) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text;
  if (text != null && text.isNotEmpty) {
    terminal.paste(text);
  }
}

/// 全选缓冲区（与包内 SelectAllTextIntent 同一实现）。
void selectAllInTerminal(Terminal terminal, TerminalController controller) {
  controller.setSelection(
    terminal.buffer.createAnchor(
      0,
      terminal.buffer.height - terminal.viewHeight,
    ),
    terminal.buffer.createAnchor(
      terminal.viewWidth,
      terminal.buffer.height - 1,
    ),
    mode: SelectionMode.line,
  );
}

/// URL 匹配：协议限定 http / https / ftp / ftps，行内非空白连续段。
final RegExp _linkPattern = RegExp(
  r'(?:https?|ftps?)://\S+',
  caseSensitive: false,
);

/// 会跟在 URL 后面的句尾标点与引号，点击时裁掉（含中英文两套）。
const String _trailingPunctuation = "\"'.,;:!?。，、；：！？「」『』》〉”’";

/// 命中的链接：URL 文本 + 它在缓冲区里占的格子。
///
/// 格子跨度是给「按住 Cmd/Ctrl 悬停时画下划线」用的，所以必须和文本一起
/// 算出来：宽字符占两格，字符串下标与格列不能互相当（映射见 [findLinkAtCell]）。
final class TerminalLink {
  const TerminalLink({
    required this.url,
    required this.row,
    required this.startCell,
    required this.endCell,
  });

  /// URL 文本，已裁掉行尾句读。
  final String url;

  /// 缓冲区行号（与 `CellOffset.y` 同一坐标系，含回滚）。
  final int row;

  /// 起始格列（含）。
  final int startCell;

  /// 结束格列（不含）：最后一个字符所在格列加上它自己的宽度。
  final int endCell;

  @override
  bool operator ==(Object other) =>
      other is TerminalLink &&
      other.url == url &&
      other.row == row &&
      other.startCell == startCell &&
      other.endCell == endCell;

  @override
  int get hashCode => Object.hash(url, row, startCell, endCell);
}

/// 一行的文本 + 「字符串下标 → 起始格列 / 格宽」映射。
///
/// 三者必须一起逐格构建：宽字符占两格，格列与字符串下标不能互相当。
/// 宽字符的占位格 codepoint 恒为 0（见 xterm `Buffer.writeChar`），跳过即是。
final class BufferLineText {
  BufferLineText(BufferLine line) {
    final buffer = StringBuffer();
    for (var i = 0; i < line.length; i++) {
      final codePoint = line.getCodePoint(i);
      if (codePoint == 0) continue;
      starts.add(i);
      widths.add(line.getWidth(i));
      buffer.writeCharCode(codePoint);
    }
    text = buffer.toString();
  }

  late final String text;
  final List<int> starts = [];
  final List<int> widths = [];

  /// 第 [index] 个字符占的格子区间（含首不含尾）。
  (int, int) cellSpanOf(int index, int length) =>
      (starts[index], starts[index + length - 1] + widths[index + length - 1]);
}

/// 点击的格子落在 URL 上时返回该链接，否则返回 null。
///
/// 跨度覆盖正则匹配到的整段（含被裁掉的句尾标点）：下划线画的就是点击
/// 认的那一段，「看起来能点」与「点得动」因此完全一致。
TerminalLink? findLinkAtCell(Terminal terminal, CellOffset cell) {
  final buffer = terminal.buffer;
  if (cell.y < 0 || cell.y >= buffer.height) return null;
  final line = BufferLineText(buffer.lines[cell.y]);

  for (final match in _linkPattern.allMatches(line.text)) {
    final (startCell, endCell) = line.cellSpanOf(
      match.start,
      match.end - match.start,
    );
    if (cell.x >= startCell && cell.x < endCell) {
      return TerminalLink(
        url: _trimTrailingPunctuation(match.group(0)!),
        row: cell.y,
        startCell: startCell,
        endCell: endCell,
      );
    }
  }
  return null;
}

/// 回滚缓冲里的一处命中：行号（与 `CellOffset.y` 同一坐标系，含回滚）与
/// 它在行内占的格子区间（含首不含尾）。
final class TerminalMatch {
  const TerminalMatch({
    required this.row,
    required this.startCell,
    required this.endCell,
  });

  final int row;
  final int startCell;
  final int endCell;

  @override
  bool operator ==(Object other) =>
      other is TerminalMatch &&
      other.row == row &&
      other.startCell == startCell &&
      other.endCell == endCell;

  @override
  int get hashCode => Object.hash(row, startCell, endCell);

  @override
  String toString() => 'TerminalMatch(row: $row, $startCell..$endCell)';
}

/// 在缓冲区（含回滚）里找 [query] 的全部出现，大小写不敏感；[query] 为空
/// 返回空表。
///
/// 不跨行匹配：终端里一行就是一条记录，跨行命中在日志里几乎没有意义，
/// 而实现代价是多一倍的边界处理。
///
/// 每次输入都重扫一遍整块缓冲区（50000 行满缓冲是最坏情况）。没有加去抖：
/// 一屏日志量级下这是微不足道的一次遍历，真在低端机上感到卡顿再加。
List<TerminalMatch> findTerminalMatches(Buffer buffer, String query) {
  if (query.isEmpty) return const [];
  final out = <TerminalMatch>[];
  for (var row = 0; row < buffer.height; row++) {
    final line = BufferLineText(buffer.lines[row]);
    if (line.text.isEmpty) continue;
    // 大小写转换可能改变长度（如 'İ'），那样下标就对不上格列映射了——
    // 这种行退回大小写敏感，宁可少命中几个，也不能把高亮画错格子。
    final folded = line.text.toLowerCase();
    final caseInsensitive = folded.length == line.text.length;
    final haystack = caseInsensitive ? folded : line.text;
    final needle = caseInsensitive ? query.toLowerCase() : query;

    var from = 0;
    while (from <= haystack.length - needle.length) {
      final at = haystack.indexOf(needle, from);
      if (at < 0) break;
      final (startCell, endCell) = line.cellSpanOf(at, needle.length);
      out.add(TerminalMatch(row: row, startCell: startCell, endCell: endCell));
      from = at + 1; // 允许重叠：'aa' 在 'aaa' 里算两处
    }
  }
  return out;
}

/// 裁掉 URL 尾部的句读。右括号 / 右方括号只在括号不配对时才裁：
/// 维基式 URL 里配对的括号属于链接本身。
String _trimTrailingPunctuation(String url) {
  var end = url.length;
  while (end > 0) {
    final ch = url[end - 1];
    if (ch == ')' || ch == ']') {
      final segment = url.substring(0, end);
      final opener = ch == ')' ? '(' : '[';
      if (_count(segment, opener) >= _count(segment, ch)) break;
      end--;
      continue;
    }
    if (_trailingPunctuation.contains(ch)) {
      end--;
      continue;
    }
    break;
  }
  return url.substring(0, end);
}

int _count(String text, String char) => text.split(char).length - 1;

/// 用系统方式打开链接；web 上开新标签页（不能把 SSH 应用自己导航走）。
/// 打不开（无浏览器 / 平台通道异常）返回 false，由调用方提示。
Future<bool> openTerminalLink(Uri uri) async {
  try {
    return await launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );
  } catch (_) {
    return false;
  }
}
