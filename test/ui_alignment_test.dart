import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:no_shell/main.dart';
import 'package:no_shell/store.dart';
import 'package:no_shell/widgets/settings_controls.dart';

import 'support/credential_store_fake.dart';
import 'support/demo_servers.dart';

/// 视觉对齐的回归用例。
///
/// 这些断言守的不是「好看」，而是几条一改就会歪的几何关系：图标列与文字
/// 起点、行高一致、卡片内控件等高。它们此前各自由数字硬编码，改一处忘一处
/// 就会出现「同一列的行首左右错开半格」这种只有肉眼能看出来的问题。
void main() {
  Future<void> pumpDesktop(WidgetTester tester) async {
    // 平台覆盖是 foundation 全局变量，框架在测试体内校验复位，须 try/finally。
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      NoShellApp(
        store: ServerStore(seed: demoServers),
        credentials: FakeCredentialStore(),
      ),
    );
    await tester.pump();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await tester.pumpAndSettle();
  }

  testWidgets('侧边栏：分组名、主机名与底部设置入口同一列', (tester) async {
    try {
      await pumpDesktop(tester);

      final groupName = tester.getTopLeft(find.text('生产环境'));
      final hostName = tester.getTopLeft(find.text('web-prod-01'));
      expect(
        hostName.dx,
        closeTo(groupName.dx, 0.5),
        reason: '分组头与主机行的文字起点必须共用一行图标列',
      );

      final settings = tester.getTopLeft(find.text('设置').first);
      expect(settings.dx, closeTo(hostName.dx, 0.5));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('设置面板：分区标题与行标签同一列，三个控件同宽同高', (tester) async {
    try {
      await pumpDesktop(tester);
      await openSettings(tester);

      final sectionText = tester.getTopLeft(find.text('外观'));
      final rowLabel = tester.getTopLeft(find.text('主题'));
      expect(
        rowLabel.dx,
        closeTo(sectionText.dx, 0.5),
        reason: '行标签与分区标题文字同一列（图标 + 间距）',
      );

      // 撑满整行的两个控件同宽（分段控件按设计保持自身宽度，不参与）。
      final widths = [
        tester.getSize(find.byType(TerminalFontDropdown)).width,
        tester.getSize(find.byType(TerminalFontSizeControl)).width,
      ];
      expect(widths[0], widths[1]);

      // 字体下拉与字号步进等高（此前 40 / 46 混着）。
      expect(
        tester.getSize(find.byType(TerminalFontDropdown)).height,
        tester.getSize(find.byType(TerminalFontSizeControl)).height,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('设置面板：卡片内相邻两项之间有分隔线', (tester) async {
    try {
      await pumpDesktop(tester);
      await openSettings(tester);
      expect(find.byType(SettingsDivider), findsWidgets);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
