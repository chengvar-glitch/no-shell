/// 弹窗的两种关法各有各的规矩：
/// - 点遮罩不关（误点窗口空白处不再把弹窗连输入一起收走）；
/// - Esc 照旧关（框架把这两件事挂在同一个 `barrierDismissible` 开关上，
///   所以补回来的那层在 `showAppDialog` 里，见 confirm_dialog.dart）。
///
/// 行为靠两条用例守着（点遮罩、按 Esc 各一条），另加一条不变量：`lib/` 里
/// 不许出现裸 `showDialog`——新弹窗漏走 `showAppDialog` 就会被这条拦下。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/theme.dart';
import 'package:no_shell/widgets/busy_overlay.dart';
import 'package:no_shell/widgets/confirm_dialog.dart';

Widget _app(Widget Function(BuildContext) body) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: AppTheme.light(),
  home: Scaffold(body: Builder(builder: body)),
);

void main() {
  setUp(AppTheme.resetCache);

  test('lib 里不许有裸 showDialog（弹窗一律走 showAppDialog）', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // 唯一允许直呼 showDialog 的地方就是那个入口自己。
      if (entity.path.endsWith('confirm_dialog.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // 注释里提到 showDialog（说明、文档）不算调用点。
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (lines[i].contains('showDialog')) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty, reason: '改用 showAppDialog：遮罩不关、Esc 照常关');
  });

  testWidgets('点遮罩不关，Esc 关', (tester) async {
    await tester.pumpWidget(
      _app(
        (context) => TextButton(
          onPressed: () => unawaited(
            showConfirmDialog(
              context,
              title: '标题',
              body: '正文',
              confirmLabel: '确认',
            ),
          ),
          child: const Text('开'),
        ),
      ),
    );
    await tester.tap(find.text('开'));
    await tester.pumpAndSettle();
    expect(find.text('正文'), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('正文'), findsOneWidget, reason: '点遮罩不该关');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('正文'), findsNothing, reason: 'Esc 该关');
  });

  testWidgets('等待遮罩按 Esc 也不关（它护的就是那段不可取消的窗口）', (tester) async {
    final run = Completer<void>();
    await tester.pumpWidget(
      _app(
        (context) => TextButton(
          onPressed: () => unawaited(
            runWithBusyOverlay(context, message: '正在导出', run: () => run.future),
          ),
          child: const Text('开'),
        ),
      ),
    );
    await tester.tap(find.text('开'));
    await tester.pump();
    await tester.pump(kBusyShowDelay);
    await tester.pump();
    expect(find.text('正在导出'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('正在导出'), findsOneWidget, reason: '不可取消的遮罩不能被 Esc 收掉');

    run.complete();
    await tester.pumpAndSettle();
    expect(find.text('正在导出'), findsNothing, reason: '动作收尾时照常收走');
  });
}
