import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:no_shell/main.dart';
import 'package:no_shell/theme.dart';

import 'support/credential_store_fake.dart';

void main() {
  // 主题切换的顺滑度取决于语义色是否参与 ThemeData.lerp：
  // 只按 brightness 现算的色值会在动画中点硬切，观感就是「卡顿」。
  test('语义色随 ThemeData.lerp 逐帧插值，不再跟着 brightness 在中点硬切', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();
    expect(light.sidebarBackground, AppPalette.sidebarLight);
    expect(dark.sidebarBackground, AppPalette.sidebarDark);

    final quarter = ThemeData.lerp(light, dark, 0.25);
    // 亮度仍是浅色（brightness 走的是 t < 0.5 的硬切换），面板色却已经在路上：
    // 两者解耦，才不会出现「先不动、到中点整体跳一下」。
    expect(quarter.brightness, Brightness.light);
    expect(
      quarter.sidebarBackground,
      Color.lerp(AppPalette.sidebarLight, AppPalette.sidebarDark, 0.25),
    );
    expect(
      quarter.panelBackground,
      Color.lerp(AppPalette.panelLight, AppPalette.panelDark, 0.25),
    );
    expect(
      ThemeData.lerp(light, dark, 1).sidebarBackground,
      AppPalette.sidebarDark,
    );
  });

  // 切 Tab 卡顿回归护栏：TabBar 选中 / 未选中的字重一旦不同，M3 会用
  // AnimatedDefaultTextStyle 逐帧插值标签样式，每帧都让标签段落重新排版，
  // 本机（Linux + Impeller）实测单帧阻塞 1.5~2.1s（release 同样复现），
  // 三个 Tab 切起来像卡死；字重统一后单帧回到 4~6ms。选中态只靠颜色 +
  // 指示器区分，样式里的字重必须保持相等。
  test('TabBar 选中 / 未选中字重一致（字重不同会让切 Tab 单帧阻塞 1.5s+）', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final tabBar = theme.tabBarTheme;
      expect(
        tabBar.unselectedLabelStyle?.fontWeight,
        tabBar.labelStyle?.fontWeight,
        reason: '字重不同会触发逐帧文本重排',
      );
      // 颜色仍要区分选中态，否则选中反馈就没了。
      expect(tabBar.labelColor, isNot(tabBar.unselectedLabelColor));
    }
  });

  testWidgets('切换主题时面板色逐帧过渡，动画结束落到深色', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    await tester.pumpWidget(NoShellApp(credentials: FakeCredentialStore()));
    await tester.pump();

    Color sidebarColor() =>
        Theme.of(tester.element(find.text('NoShell'))).sidebarBackground;
    expect(sidebarColor(), AppPalette.sidebarLight);

    // 主题切换收进了设置弹窗：打开它，点「深色」分段。
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pump(); // 动画第 0 帧
    await tester.pump(const Duration(milliseconds: 60)); // 240ms 的 1/4

    final mid = sidebarColor();
    expect(mid, isNot(AppPalette.sidebarLight), reason: '刚切换就该开始过渡');
    expect(mid, isNot(AppPalette.sidebarDark), reason: '不该一步到位');

    await tester.pumpAndSettle();
    expect(sidebarColor(), AppPalette.sidebarDark);
  });
}
