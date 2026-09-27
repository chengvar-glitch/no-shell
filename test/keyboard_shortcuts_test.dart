import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:no_shell/main.dart';
import 'package:no_shell/store.dart';
import 'package:no_shell/theme.dart';
import 'package:no_shell/widgets/shortcut_help_dialog.dart';

import 'support/credential_store_fake.dart';
import 'support/demo_servers.dart';

void main() {
  // 桌面全局快捷键（HomePage 的 CallbackShortcuts）与它们的提示。
  // 键盘注入用 platform: 'linux'（Ctrl 修饰）；macOS 的 ⌘ 走同一张绑定表，
  // 只差文案写法，不在测试里分叉。
  Future<void> pumpDesktop(WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      NoShellApp(
        store: ServerStore(seed: demoServers),
        credentials: FakeCredentialStore(),
        agentKeysProbe: () async => false,
      ),
    );
    await tester.pump();
  }

  setUp(AppTheme.resetCache);

  /// 按一次 Ctrl+K：修饰键要显式按下再松开（sendKeyEvent 的 platform 参数
  /// 只影响字符模拟，不会自动带 Ctrl）。
  Future<void> pressCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('Ctrl+N 打开新建连接弹窗', (tester) async {
    await pumpDesktop(tester);

    await pressCtrl(tester, LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();

    expect(find.text('新建连接'), findsWidgets);
    await pressCtrl(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('Ctrl+, 打开设置弹窗', (tester) async {
    await pumpDesktop(tester);

    await pressCtrl(tester, LogicalKeyboardKey.comma);
    await tester.pumpAndSettle();

    // 设置弹窗是自绘 Dialog（非 AlertDialog），用「关于」按钮确认开到位。
    expect(find.widgetWithText(Dialog, '关于'), findsOneWidget);
    await pressCtrl(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('Ctrl+/ 打开快捷键帮助弹窗', (tester) async {
    await pumpDesktop(tester);

    await pressCtrl(tester, LogicalKeyboardKey.slash);
    await tester.pumpAndSettle();

    expect(find.byType(ShortcutHelpDialog), findsOneWidget);
    // 汇总里必须有「搜索主机」这一条（Ctrl+F 的去向要能查到）。
    expect(find.text('搜索主机'), findsOneWidget);
    expect(find.text('Ctrl+F'), findsOneWidget);
    await pressCtrl(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('Ctrl+F 聚焦侧边栏搜索框并可直接输入', (tester) async {
    await pumpDesktop(tester);

    await pressCtrl(tester, LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    tester.testTextInput.enterText('db');
    await tester.pump();

    expect(find.text('db-primary'), findsOneWidget);
    expect(find.text('web-prod-01'), findsNothing);
  });

  testWidgets('侧边栏收起时 Ctrl+F 先展开侧边栏再聚焦搜索', (tester) async {
    await pumpDesktop(tester);

    await tester.tap(find.byIcon(Icons.menu_open));
    await tester.pumpAndSettle();
    final slot = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('sidebar-slot')),
    );
    expect(slot.size.width, 0);

    await pressCtrl(tester, LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    expect(slot.size.width, 264);
    tester.testTextInput.enterText('db');
    await tester.pump();
    expect(find.text('db-primary'), findsOneWidget);
  });

  testWidgets('底部设置行带键位标注，键盘按钮打开帮助弹窗', (tester) async {
    await pumpDesktop(tester);

    expect(find.text('Ctrl+,'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(ShortcutHelpDialog), findsOneWidget);
  });
}
