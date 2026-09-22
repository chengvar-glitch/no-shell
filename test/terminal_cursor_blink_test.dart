import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/xterm.dart';

void main() {
  testWidgets('聚焦光标按周期闪烁，失焦后回到可见相位', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final terminal = Terminal();

    await tester.pumpWidget(
      MaterialApp(
        home: TerminalView(
          terminal,
          focusNode: focus,
          autofocus: true,
          cursorBlink: true,
        ),
      ),
    );
    await tester.pump();

    final render = tester.allRenderObjects.whereType<RenderTerminal>().single;
    expect(render.cursorShown, isTrue);

    await tester.pump(const Duration(milliseconds: 530));
    expect(render.cursorShown, isFalse);

    await tester.pump(const Duration(milliseconds: 530));
    expect(render.cursorShown, isTrue);

    focus.unfocus();
    await tester.pump();
    expect(render.cursorShown, isTrue);
  });

  testWidgets('默认保持上游静态光标，不启动闪烁计时器', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final terminal = Terminal();

    await tester.pumpWidget(
      MaterialApp(
        home: TerminalView(terminal, focusNode: focus, autofocus: true),
      ),
    );
    await tester.pump();

    final render = tester.allRenderObjects.whereType<RenderTerminal>().single;
    await tester.pump(const Duration(milliseconds: 700));
    expect(render.cursorShown, isTrue);
  });
}
