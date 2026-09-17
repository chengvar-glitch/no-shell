import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm/core.dart';
import 'package:xterm/ui.dart';

/// 终端便捷交互的公共件：字号缩放键位、复制 / 粘贴 / 全选动作、
/// 超链接识别。只依赖 xterm 公共 API，web 也要能编译。

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

/// 点击的格子落在 URL 上时返回该 URL（已裁句尾标点），否则返回 null。
String? findLinkAtCell(Terminal terminal, CellOffset cell) {
  final buffer = terminal.buffer;
  if (cell.y < 0 || cell.y >= buffer.height) return null;
  final line = buffer.lines[cell.y];

  // 行文本与「字符串下标 → 起始格列」的映射必须一起逐格构建：
  // 宽字符占两格，格列和字符串下标不能互相当。宽字符的占位格
  // codepoint 恒为 0（见 xterm Buffer.writeChar），跳过即是。
  final text = StringBuffer();
  final starts = <int>[];
  final widths = <int>[];
  for (var i = 0; i < line.length; i++) {
    final codePoint = line.getCodePoint(i);
    if (codePoint == 0) continue;
    starts.add(i);
    widths.add(line.getWidth(i));
    text.writeCharCode(codePoint);
  }
  final lineText = text.toString();

  for (final match in _linkPattern.allMatches(lineText)) {
    final startCell = starts[match.start];
    final endCell = starts[match.end - 1] + widths[match.end - 1];
    if (cell.x >= startCell && cell.x < endCell) {
      return _trimTrailingPunctuation(match.group(0)!);
    }
  }
  return null;
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
