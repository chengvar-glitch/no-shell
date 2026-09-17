import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/ssh/terminal_interactions.dart';
import 'package:xterm/core.dart';
import 'package:xterm/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 剪贴板平台通道在测试里没有宿主，挂一个内存假实现。
  String clipboardText = '';
  setUp(() {
    clipboardText = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboardText = call.arguments['text'] as String? ?? '';
              return null;
            case 'Clipboard.getData':
              return {'text': clipboardText};
            default:
              return null;
          }
        });
  });

  group('findLinkAtCell 链接识别', () {
    test('点击落在 URL 上返回 URL，落在旁边返回 null', () {
      final terminal = Terminal(maxLines: 100)
        ..write('see https://example.com/x now');
      // 'see ' 占 0-3 列，URL 占 4-24 列，空格 25，「now」26 起。
      expect(
        findLinkAtCell(terminal, const CellOffset(10, 0)),
        'https://example.com/x',
      );
      expect(
        findLinkAtCell(terminal, const CellOffset(4, 0)),
        'https://example.com/x',
      );
      expect(
        findLinkAtCell(terminal, const CellOffset(24, 0)),
        'https://example.com/x',
      );
      expect(findLinkAtCell(terminal, const CellOffset(25, 0)), isNull);
      expect(findLinkAtCell(terminal, const CellOffset(3, 0)), isNull);
      expect(findLinkAtCell(terminal, const CellOffset(26, 0)), isNull);
    });

    test('行尾句读与引号裁掉', () {
      final terminal = Terminal(maxLines: 100)
        ..write('go https://example.com/a)." now');
      expect(
        findLinkAtCell(terminal, const CellOffset(5, 0)),
        'https://example.com/a',
      );
    });

    test('配对的括号属于链接本身，不裁', () {
      final terminal = Terminal(maxLines: 100)
        ..write('see https://en.wikipedia.org/wiki/OS_(computing) end');
      expect(
        findLinkAtCell(terminal, const CellOffset(6, 0)),
        'https://en.wikipedia.org/wiki/OS_(computing)',
      );
    });

    test('不配对的右括号是句子成分，裁掉', () {
      final terminal = Terminal(maxLines: 100)
        ..write('(see https://example.com/a)');
      expect(
        findLinkAtCell(terminal, const CellOffset(6, 0)),
        'https://example.com/a',
      );
    });

    test('宽字符占两格：URL 的起始格列按格宽算', () {
      final terminal = Terminal(maxLines: 100)..write('目录 https://example.com');
      // 「目录」占 0-3 格，空格第 4 格，URL 从第 5 格开始。
      expect(
        findLinkAtCell(terminal, const CellOffset(5, 0)),
        'https://example.com',
      );
      expect(findLinkAtCell(terminal, const CellOffset(4, 0)), isNull);
      expect(findLinkAtCell(terminal, const CellOffset(3, 0)), isNull);
      expect(findLinkAtCell(terminal, const CellOffset(1, 0)), isNull);
    });

    test('协议大小写不敏感，URL 原样返回', () {
      final terminal = Terminal(maxLines: 100)
        ..write('HTTPS://Example.COM/Path');
      expect(
        findLinkAtCell(terminal, const CellOffset(0, 0)),
        'HTTPS://Example.COM/Path',
      );
    });

    test('ftp 协议也识别', () {
      final terminal = Terminal(maxLines: 100)
        ..write('ftp://files.example.com/pub');
      expect(
        findLinkAtCell(terminal, const CellOffset(0, 0)),
        'ftp://files.example.com/pub',
      );
    });

    test('无协议的域名不识别', () {
      final terminal = Terminal(maxLines: 100)..write('visit example.com ok');
      expect(findLinkAtCell(terminal, const CellOffset(6, 0)), isNull);
    });

    test('行号越界返回 null', () {
      final terminal = Terminal(maxLines: 100)..write('https://example.com');
      expect(findLinkAtCell(terminal, const CellOffset(0, 5)), isNull);
    });

    test('多行内容按行各自识别', () {
      // 终端的 LF 不回列，换行必须 \r\n，这与真实远端输出一致。
      final terminal = Terminal(maxLines: 100)
        ..write('https://first.example\r\nplain row\r\nhttps://second.example');
      expect(
        findLinkAtCell(terminal, const CellOffset(0, 0)),
        'https://first.example',
      );
      expect(findLinkAtCell(terminal, const CellOffset(3, 1)), isNull);
      expect(
        findLinkAtCell(terminal, const CellOffset(0, 2)),
        'https://second.example',
      );
    });
  });

  group('terminalShortcuts 键位表', () {
    test('合并包默认键位，复制粘贴快捷键不丢', () {
      final shortcuts = terminalShortcuts();
      for (final entry in defaultTerminalShortcuts.entries) {
        expect(shortcuts[entry.key], entry.value);
      }
    });

    test('包含放大 / 缩小 / 重置三组键位', () {
      final deltas = terminalShortcuts().values
          .whereType<TerminalFontSizeAdjustIntent>()
          .map((intent) => intent.delta)
          .toSet();
      expect(deltas, containsAll([1, -1]));
      expect(
        terminalShortcuts().values.whereType<TerminalFontSizeResetIntent>(),
        isNotEmpty,
      );
    });

    test('缩放修饰键与平台约定一致（Apple 用 Cmd，其余用 Ctrl）', () {
      final useMeta = isAppleLikePlatform();
      for (final entry in terminalShortcuts().entries) {
        final intent = entry.value;
        if (intent is! TerminalFontSizeAdjustIntent &&
            intent is! TerminalFontSizeResetIntent) {
          continue;
        }
        final activator = entry.key as SingleActivator;
        expect(activator.meta, useMeta);
        expect(activator.control, !useMeta);
      }
    });
  });

  group('复制 / 粘贴 / 全选助手', () {
    test('copyTerminalSelection 没有选区返回 false', () async {
      final terminal = Terminal(maxLines: 100)..write('hello');
      final controller = TerminalController();
      expect(await copyTerminalSelection(terminal, controller), isFalse);
    });

    test('全选后复制，剪贴板得到缓冲区文本（尾随空行只贡献换行）', () async {
      final terminal = Terminal(maxLines: 100)..write('hello\nworld');
      final controller = TerminalController();
      selectAllInTerminal(terminal, controller);
      expect(controller.selection, isNotNull);
      expect(await copyTerminalSelection(terminal, controller), isTrue);
      expect(clipboardText, startsWith('hello\nworld'));
    });

    test('pasteIntoTerminal 空剪贴板不动缓冲区', () async {
      final terminal = Terminal(maxLines: 100)..write('abc');
      await pasteIntoTerminal(terminal);
      expect(terminal.buffer.currentLine.getText(), 'abc');
    });

    test('pasteIntoTerminal 把剪贴板作为输入发往终端', () async {
      final terminal = Terminal(maxLines: 100)..write('abc');
      // 粘贴等价于把文本敲进键盘：经 onOutput 发给 PTY，缓冲区由远端回显更新。
      final output = <String>[];
      terminal.onOutput = output.add;
      clipboardText = 'XYZ';
      await pasteIntoTerminal(terminal);
      expect(output, contains('XYZ'));
      expect(
        terminal.buffer.currentLine.getText(),
        'abc',
        reason: '本地缓冲区不该被粘贴直接改写',
      );
    });
  });
}
