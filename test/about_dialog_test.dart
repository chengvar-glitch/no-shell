import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:no_shell/theme.dart';
import 'package:no_shell/widgets/about_dialog.dart';
import 'package:no_shell/widgets/window_caption.dart';

/// 「关于」在 macOS 上会被左上角红绿灯压住返回键：
/// [AboutDialog] 里的「查看许可」按钮由 Flutter 内部推 [LicensePage]，
/// 那条 AppBar 的返回键落在 x≈16，正好在红绿灯（21~82）底下。
/// [showAppAboutDialog] 把让位主题带进许可页，这里验证让位确实生效、
/// 且只对 macOS 生效。
void main() {
  /// 走一遍「关于 → 查看许可」，量许可页返回键字形与左侧列表的左边缘。
  ///
  /// 列表左边缘用来钉住「只挪 AppBar」：整页内容不能被平移。
  Future<({double backLeft, double listLeft})> openLicense(
    WidgetTester tester,
    TargetPlatform platform,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await tester.pumpWidget(
        MaterialApp(
          // 每次量一个平台都换 key：换掉整棵树，上一轮的许可页路由不会留在
          // 栈上（Navigator 被复用的话，首页会因离屏而找不到入口按钮）。
          key: ValueKey(platform),
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showAppAboutDialog(
                    context: context,
                    applicationName: 'NoShell',
                    applicationVersion: '3.1.0',
                  ),
                  child: const Text('about'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('about'));
      await tester.pumpAndSettle();
      // 对话框的按钮顺序与 AboutDialog 一致：先「查看许可」后「关闭」。
      // 不按文案找，免得跟着界面语言漂。
      await tester.tap(
        find
            .descendant(
              of: find.byType(AboutDialog),
              matching: find.byType(TextButton),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      return (
        backLeft: tester.getRect(find.byType(BackButtonIcon)).left,
        listLeft: tester.getRect(find.byType(Scrollable).first).left,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('macOS 上许可页返回键让开红绿灯，其他桌面端维持原样', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final linux = await openLicense(tester, TargetPlatform.linux);
    final windows = await openLicense(tester, TargetPlatform.windows);
    final macOS = await openLicense(tester, TargetPlatform.macOS);

    // 其他桌面端维持现状：没有浮在内容上的窗口按钮，返回键不动。
    expect(windows.backLeft, linux.backLeft);
    expect(linux.backLeft, lessThan(kMacOSTrafficLightsIndent));

    // macOS 的平移量正好是红绿灯缩进，返回键落在红绿灯右缘（约 82）之外。
    expect(macOS.backLeft - linux.backLeft, kMacOSTrafficLightsIndent);
    expect(macOS.backLeft, greaterThanOrEqualTo(kMacOSTrafficLightsIndent));

    // 让位只发生在 AppBar 的 leading 槽位里，页面内容与两端一致。
    expect(macOS.listLeft, linux.listLeft);
  });
}
