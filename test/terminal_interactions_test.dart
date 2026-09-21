import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/ssh/terminal_interactions.dart';
import 'package:no_shell/ssh/terminal_mouse.dart';
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
        findLinkAtCell(terminal, const CellOffset(10, 0))?.url,
        'https://example.com/x',
      );
      expect(
        findLinkAtCell(terminal, const CellOffset(4, 0))?.url,
        'https://example.com/x',
      );
      expect(
        findLinkAtCell(terminal, const CellOffset(24, 0))?.url,
        'https://example.com/x',
      );
      expect(findLinkAtCell(terminal, const CellOffset(25, 0))?.url, isNull);
      expect(findLinkAtCell(terminal, const CellOffset(3, 0))?.url, isNull);
      expect(findLinkAtCell(terminal, const CellOffset(26, 0))?.url, isNull);
    });

    test('行尾句读与引号裁掉', () {
      final terminal = Terminal(maxLines: 100)
        ..write('go https://example.com/a)." now');
      expect(
        findLinkAtCell(terminal, const CellOffset(5, 0))?.url,
        'https://example.com/a',
      );
    });

    test('配对的括号属于链接本身，不裁', () {
      final terminal = Terminal(maxLines: 100)
        ..write('see https://en.wikipedia.org/wiki/OS_(computing) end');
      expect(
        findLinkAtCell(terminal, const CellOffset(6, 0))?.url,
        'https://en.wikipedia.org/wiki/OS_(computing)',
      );
    });

    test('不配对的右括号是句子成分，裁掉', () {
      final terminal = Terminal(maxLines: 100)
        ..write('(see https://example.com/a)');
      expect(
        findLinkAtCell(terminal, const CellOffset(6, 0))?.url,
        'https://example.com/a',
      );
    });

    test('宽字符占两格：URL 的起始格列按格宽算', () {
      final terminal = Terminal(maxLines: 100)..write('目录 https://example.com');
      // 「目录」占 0-3 格，空格第 4 格，URL 从第 5 格开始。
      expect(
        findLinkAtCell(terminal, const CellOffset(5, 0))?.url,
        'https://example.com',
      );
      expect(findLinkAtCell(terminal, const CellOffset(4, 0))?.url, isNull);
      expect(findLinkAtCell(terminal, const CellOffset(3, 0))?.url, isNull);
      expect(findLinkAtCell(terminal, const CellOffset(1, 0))?.url, isNull);
    });

    test('协议大小写不敏感，URL 原样返回', () {
      final terminal = Terminal(maxLines: 100)
        ..write('HTTPS://Example.COM/Path');
      expect(
        findLinkAtCell(terminal, const CellOffset(0, 0))?.url,
        'HTTPS://Example.COM/Path',
      );
    });

    test('ftp 协议也识别', () {
      final terminal = Terminal(maxLines: 100)
        ..write('ftp://files.example.com/pub');
      expect(
        findLinkAtCell(terminal, const CellOffset(0, 0))?.url,
        'ftp://files.example.com/pub',
      );
    });

    test('无协议的域名不识别', () {
      final terminal = Terminal(maxLines: 100)..write('visit example.com ok');
      expect(findLinkAtCell(terminal, const CellOffset(6, 0))?.url, isNull);
    });

    test('行号越界返回 null', () {
      final terminal = Terminal(maxLines: 100)..write('https://example.com');
      expect(findLinkAtCell(terminal, const CellOffset(0, 5))?.url, isNull);
    });

    test('多行内容按行各自识别', () {
      // 终端的 LF 不回列，换行必须 \r\n，这与真实远端输出一致。
      final terminal = Terminal(maxLines: 100)
        ..write('https://first.example\r\nplain row\r\nhttps://second.example');
      expect(
        findLinkAtCell(terminal, const CellOffset(0, 0))?.url,
        'https://first.example',
      );
      expect(findLinkAtCell(terminal, const CellOffset(3, 1))?.url, isNull);
      expect(
        findLinkAtCell(terminal, const CellOffset(0, 2))?.url,
        'https://second.example',
      );
    });

    test('跨度就是点击数得动的那一段', () {
      final terminal = Terminal(maxLines: 100)
        ..write('see https://example.com/x now');
      final link = findLinkAtCell(terminal, const CellOffset(10, 0));
      expect(link, isNotNull);
      expect(link!.url, 'https://example.com/x');
      expect(link.row, 0);
      // 'see ' 占 0-3 格，URL 从第 4 格起、长 21 格 → 结束格列是 25。
      expect(link.startCell, 4);
      expect(link.endCell, 25);
    });

    test('句尾标点被裁掉，但跨度仍是点击认的那一段', () {
      final terminal = Terminal(maxLines: 100)
        ..write('go https://example.com/a)." now');
      final link = findLinkAtCell(terminal, const CellOffset(5, 0))!;
      expect(link.url, 'https://example.com/a');
      // 匹配到的是 https://example.com/a)."（第 3 格起、长 24 格）。
      expect(link.startCell, 3);
      expect(link.endCell, 27);
    });

    test('宽字符按格宽算跨度，下划线不会与文字错位', () {
      final terminal = Terminal(maxLines: 100)..write('目录 https://example.com');
      final link = findLinkAtCell(terminal, const CellOffset(5, 0))!;
      // 「目录」占 0-3 格，空格第 4 格，URL 从第 5 格起、长 19 格。
      expect(link.startCell, 5);
      expect(link.endCell, 24);
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

  group('findTerminalMatches 回滚搜索', () {
    test('大小写不敏感，同一行多处命中都算', () {
      final terminal = Terminal(maxLines: 100)
        ..write('Beta beta BETA\nnothing here\n');

      final hits = findTerminalMatches(terminal.buffer, 'beta');
      expect(hits, const [
        TerminalMatch(row: 0, startCell: 0, endCell: 4),
        TerminalMatch(row: 0, startCell: 5, endCell: 9),
        TerminalMatch(row: 0, startCell: 10, endCell: 14),
      ]);
    });

    test('空查询与查不到都是空表', () {
      final terminal = Terminal(maxLines: 100)..write('alpha\n');
      expect(findTerminalMatches(terminal.buffer, ''), isEmpty);
      expect(findTerminalMatches(terminal.buffer, 'zeta'), isEmpty);
    });

    test('重叠命中按两处算', () {
      final terminal = Terminal(maxLines: 100)..write('aaaa\n');
      expect(findTerminalMatches(terminal.buffer, 'aa'), const [
        TerminalMatch(row: 0, startCell: 0, endCell: 2),
        TerminalMatch(row: 0, startCell: 1, endCell: 3),
        TerminalMatch(row: 0, startCell: 2, endCell: 4),
      ]);
    });

    test('宽字符按格子算跨度，不按字符串下标', () {
      final terminal = Terminal(maxLines: 100)..write('中文 log\n');
      // 「中文」各占两格：'log' 是第 5 个字符，但落在第 5 格起
      // （中 0-1、文 2-3、空格 4、l 5）。
      expect(findTerminalMatches(terminal.buffer, 'log'), const [
        TerminalMatch(row: 0, startCell: 5, endCell: 8),
      ]);
      // 命中汉字本身时跨度是两格。
      expect(findTerminalMatches(terminal.buffer, '中'), const [
        TerminalMatch(row: 0, startCell: 0, endCell: 2),
      ]);
    });

    test('回滚里的行也在搜索范围内', () {
      final terminal = Terminal(maxLines: 100)
        ..write('first needle\n')
        ..write(List.generate(40, (i) => 'line $i\n').join());
      final hits = findTerminalMatches(terminal.buffer, 'needle');
      expect(hits, hasLength(1));
      expect(hits.single.row, 0, reason: '第 0 行就是最早那行，仍在缓冲区里');
    });

    test('Cmd/Ctrl+F 那一支键位已绑上查找意图', () {
      final shortcuts = terminalShortcuts();
      final searchKeys = shortcuts.entries
          .where((entry) => entry.value is TerminalSearchIntent)
          .toList();
      expect(searchKeys, hasLength(1), reason: '每个平台只绑一个组合');
      final activator = searchKeys.single.key as SingleActivator;
      expect(activator.trigger, LogicalKeyboardKey.keyF);
      // 非 Apple 平台必须是 Ctrl+Shift+F：裸 Ctrl+F 是 readline 的光标右移。
      expect(activator.control, isTrue);
      expect(activator.shift, isTrue);
    });
  });

  group('鼠标拖动编码', () {
    const cell = CellOffset(4, 2);
    // 1 起算：格 (4,2) → 坐标 (5,3)。
    test('SGR：按下 / 移动 / 抬起', () {
      expect(
        encodeMouseEvent(
          phase: MouseDragPhase.down,
          cell: cell,
          reportMode: MouseReportMode.sgr,
        ),
        '\x1b[<0;5;3M',
      );
      // 移动事件的按钮号加 32。
      expect(
        encodeMouseEvent(
          phase: MouseDragPhase.move,
          cell: cell,
          reportMode: MouseReportMode.sgr,
        ),
        '\x1b[<32;5;3M',
      );
      expect(
        encodeMouseEvent(
          phase: MouseDragPhase.up,
          cell: cell,
          reportMode: MouseReportMode.sgr,
        ),
        '\x1b[<0;5;3m',
      );
    });

    test('urxvt：按钮号整体加 32，抬起固定报 3', () {
      expect(
        encodeMouseEvent(
          phase: MouseDragPhase.down,
          cell: cell,
          reportMode: MouseReportMode.urxvt,
        ),
        '\x1b[32;5;3M',
      );
      expect(
        encodeMouseEvent(
          phase: MouseDragPhase.move,
          cell: cell,
          reportMode: MouseReportMode.urxvt,
        ),
        '\x1b[64;5;3M',
      );
      expect(
        encodeMouseEvent(
          phase: MouseDragPhase.up,
          cell: cell,
          reportMode: MouseReportMode.urxvt,
        ),
        '\x1b[35;5;3M',
      );
    });

    test('普通模式：三个字节，越界发 NUL', () {
      expect(
        encodeMouseEvent(
          phase: MouseDragPhase.down,
          cell: const CellOffset(0, 0),
          reportMode: MouseReportMode.normal,
        ),
        '\x1b[M\x20\x21\x22',
      );
      // 第 224 列超出普通模式的编码上限（223）。
      expect(
        encodeMouseEvent(
          phase: MouseDragPhase.move,
          cell: const CellOffset(223, 0),
          reportMode: MouseReportMode.normal,
        ),
        '\x1b[M\x40\x00\x22',
      );
    });
  });
}
