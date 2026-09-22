// 终端桌面复制体验的判定逻辑：双击选词的分隔符表、Insert 系复制 / 粘贴
// 键位、智能 Ctrl+C 的处置。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/core.dart';

import 'package:no_shell/ssh/terminal_interactions.dart';

/// 按终端的格子宽算 [text] 占的列数：CJK / 全角字符占两格。
int _cellWidth(String text) =>
    text.runes.fold(0, (sum, rune) => sum + (rune > 0xFF ? 2 : 1));

/// [needle] 在 [line] 里首次出现处的起始格列。
int _cellIndexOf(String line, String needle) =>
    _cellWidth(line.substring(0, line.indexOf(needle)));

void main() {
  group('双击选词（kTerminalWordSeparators）', () {
    const uuid = 'c8cf4fd4-ed93-47d5-b4b5-afb92f08e843';
    const path = '/var/log/app/error.log';
    const timestamp = '18:51:06.276';

    late Terminal terminal;

    setUp(() {
      terminal = Terminal(
        maxLines: 100,
        wordSeparators: kTerminalWordSeparators,
      );
      terminal.write('日志编号：$uuid 已受理\r\n');
      terminal.write('看下 $path 里的报错\r\n');
      terminal.write('耗时 $timestamp 秒');
    });

    test('UUID 整条选中，中文前缀（全角冒号）不带进来', () {
      const line = '日志编号：$uuid 已受理';
      final range = terminal.buffer.getWordBoundary(
        CellOffset(_cellIndexOf(line, uuid) + 10, 0),
      );
      expect(range, isNotNull);
      expect(range!.begin.x, _cellIndexOf(line, uuid));
      expect(range.end.x, _cellIndexOf(line, uuid) + uuid.length);
    });

    test('文件路径整条选中（含开头的斜杠）', () {
      const line = '看下 $path 里的报错';
      final range = terminal.buffer.getWordBoundary(
        CellOffset(_cellIndexOf(line, path) + 5, 1),
      );
      expect(range, isNotNull);
      expect(range!.begin.x, _cellIndexOf(line, path));
      expect(range.end.x, _cellIndexOf(line, path) + path.length);
    });

    test('时间戳整条选中（冒号不断词）', () {
      const line = '耗时 $timestamp 秒';
      final range = terminal.buffer.getWordBoundary(
        CellOffset(_cellIndexOf(line, timestamp) + 4, 2),
      );
      expect(range, isNotNull);
      expect(range!.begin.x, _cellIndexOf(line, timestamp));
      expect(range.end.x, _cellIndexOf(line, timestamp) + timestamp.length);
    });

    test('落在全角冒号的占位格上拿不到词（两侧都是分隔符）', () {
      // 「日志编号：」共占 0..9 十格，全角冒号在 8..9，第 9 格是占位。
      final range = terminal.buffer.getWordBoundary(const CellOffset(9, 0));
      expect(range, isNull);
    });
  });

  group('terminalShortcuts 键位表', () {
    test('Shift+Insert 粘贴、Ctrl+Insert 复制', () {
      final shortcuts = terminalShortcuts();
      final insert = shortcuts.entries
          .map((e) => e)
          .where(
            (e) =>
                (e.key as SingleActivator).trigger == LogicalKeyboardKey.insert,
          )
          .toList();
      expect(insert, hasLength(2));
      expect(
        insert.any(
          (e) => (e.key as SingleActivator).shift && e.value is PasteTextIntent,
        ),
        isTrue,
      );
      expect(
        insert.any(
          (e) =>
              (e.key as SingleActivator).control &&
              e.value == CopySelectionTextIntent.copy,
        ),
        isTrue,
      );
    });

    test('Ctrl+A 不再绑全选（readline 的回行首要进 shell）', () {
      final shortcuts = terminalShortcuts();
      final keyA = shortcuts.keys
          .whereType<SingleActivator>()
          .where((a) => a.trigger == LogicalKeyboardKey.keyA)
          .toList();
      expect(keyA, isEmpty);
    });
  });

  group('resolveCtrlC（智能 Ctrl+C）', () {
    final keyCDown = KeyDownEvent(
      logicalKey: LogicalKeyboardKey.keyC,
      physicalKey: PhysicalKeyboardKey.keyC,
      timeStamp: Duration.zero,
    );
    final keyCUp = KeyUpEvent(
      logicalKey: LogicalKeyboardKey.keyC,
      physicalKey: PhysicalKeyboardKey.keyC,
      timeStamp: Duration.zero,
    );

    testWidgets('有选区时截下复制', (tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      addTearDown(() => tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft));
      expect(
        resolveCtrlC(keyCDown, hasSelection: true),
        TerminalCtrlCDisposition.copy,
      );
    });

    testWidgets('没有选区仍是中断', (tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      addTearDown(() => tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft));
      expect(
        resolveCtrlC(keyCDown, hasSelection: false),
        TerminalCtrlCDisposition.interrupt,
      );
    });

    testWidgets('Ctrl+Shift+C 交给键位表那条路（不拦）', (tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      addTearDown(() => tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft));
      addTearDown(() => tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft));
      expect(
        resolveCtrlC(keyCDown, hasSelection: true),
        TerminalCtrlCDisposition.interrupt,
      );
    });

    test('抬起与别的键都不拦', () {
      expect(
        resolveCtrlC(keyCUp, hasSelection: true),
        TerminalCtrlCDisposition.interrupt,
      );
      final keyDDown = KeyDownEvent(
        logicalKey: LogicalKeyboardKey.keyD,
        physicalKey: PhysicalKeyboardKey.keyD,
        timeStamp: Duration.zero,
      );
      expect(
        resolveCtrlC(keyDDown, hasSelection: true),
        TerminalCtrlCDisposition.interrupt,
      );
    });

    testWidgets('Apple 平台 Cmd+C 已是复制，Ctrl+C 恒中断', (tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(
        resolveCtrlC(keyCDown, hasSelection: true),
        TerminalCtrlCDisposition.interrupt,
      );
      debugDefaultTargetPlatformOverride = null;
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });
  });
}
