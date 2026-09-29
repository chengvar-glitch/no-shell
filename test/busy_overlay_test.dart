import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:no_shell/widgets/busy_overlay.dart';

/// 遮罩的纪律：慢才现身、现身时收不掉、跑完（含抛错）必须收走——
/// 卡住一层模态遮罩等于把整个界面锁死。
void main() {
  const message = '正在导入主机…';
  late BuildContext context;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (builderContext) {
              context = builderContext;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }

  testWidgets('瞬时完成的动作不闪遮罩', (tester) async {
    await pump(tester);

    final result = await runWithBusyOverlay(
      context,
      message: message,
      run: () async => 42,
    );
    await tester.pump();

    expect(result, 42);
    expect(find.text(message), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('慢动作盖上遮罩，点遮罩外面收不掉，跑完收走', (tester) async {
    await pump(tester);
    final gate = Completer<int>();

    final running = runWithBusyOverlay(
      context,
      message: message,
      run: () => gate.future,
    );
    // 到点之前先不现身。
    await tester.pump();
    expect(find.text(message), findsNothing);

    await tester.pump(kBusyShowDelay + const Duration(milliseconds: 50));
    expect(find.text(message), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    expect(find.text(message), findsOneWidget);

    gate.complete(42);
    expect(await running, 42);
    // 退场过渡走完才真的没了。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(message), findsNothing);
  });

  testWidgets('动作抛错也收走遮罩', (tester) async {
    await pump(tester);
    final gate = Completer<int>();

    final running = runWithBusyOverlay(
      context,
      message: message,
      run: () => gate.future,
    );
    await tester.pump(kBusyShowDelay + const Duration(milliseconds: 50));
    expect(find.text(message), findsOneWidget);

    gate.completeError(StateError('boom'));
    await expectLater(running, throwsStateError);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(message), findsNothing);
  });
}
