import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:no_shell/app_version.dart';
import 'package:no_shell/main.dart';
import 'package:no_shell/settings.dart';
import 'package:no_shell/widgets/settings_controls.dart';
import 'package:no_shell/widgets/sidebar.dart';

import 'support/credential_store_fake.dart';

void main() {
  Future<void> pumpDesktop(WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NoShellApp(credentials: FakeCredentialStore()));
    await tester.pump();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
  }

  testWidgets('侧边栏：导入导出排在头部第二位，底部只剩设置入口', (tester) async {
    await pumpDesktop(tester);

    // 头部三个同级动作：收起 → 导入导出 → 新建，同一行、顺序固定。
    // 空态里也有一个「新建」图标，断言限定在侧边栏内。
    Finder inSidebar(IconData icon) =>
        find.descendant(of: find.byType(Sidebar), matching: find.byIcon(icon));
    final collapse = tester.getCenter(inSidebar(Icons.menu_open));
    final transfer = tester.getCenter(inSidebar(Icons.import_export_rounded));
    final create = tester.getCenter(inSidebar(Icons.add_rounded));
    expect(collapse.dx, lessThan(transfer.dx));
    expect(transfer.dx, lessThan(create.dx));
    expect(transfer.dy, collapse.dy);
    expect(create.dy, collapse.dy);

    // 主题 / 语言按钮连同版本号都撤出了底部：底部只有设置入口。
    expect(find.byIcon(Icons.dark_mode_outlined), findsNothing);
    expect(find.byIcon(Icons.light_mode_outlined), findsNothing);
    expect(find.byIcon(Icons.language_outlined), findsNothing);
    expect(find.text('v0.4.4'), findsNothing);
    expect(find.text('设置'), findsOneWidget);

    // 导入导出菜单挂在头部按钮上。
    await tester.tap(find.byIcon(Icons.import_export_rounded));
    await tester.pumpAndSettle();
    expect(find.text('导入主机'), findsOneWidget);
    expect(find.text('导出主机'), findsOneWidget);
  });

  testWidgets('设置弹窗：分区、终端配色选择器与实时预览', (tester) async {
    await pumpDesktop(tester);
    await openSettings(tester);

    // 头部带版本号，三段分区说明齐全。
    expect(find.textContaining('v$appVersion'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('终端'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('更改即时生效'), findsOneWidget);
    expect(find.text('预览'), findsOneWidget);

    // 终端配色：九套预设平铺成色卡，点选即时写入全局作用域。
    final scope = TerminalStyleScope.of(tester.element(find.text('终端主题')));
    expect(scope.notifier.value.preset, TerminalPreset.githubDark);
    await tester.ensureVisible(find.text('Dracula'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dracula'));
    await tester.pumpAndSettle();
    expect(scope.notifier.value.preset, TerminalPreset.dracula);

    // 预览区用的是所选配色：背景色随预设变化。
    final preview = tester.widget<Container>(
      find
          .ancestor(
            of: find.textContaining('ssh deploy@10.0.0.1'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (preview.decoration! as BoxDecoration).color,
      TerminalPreset.dracula.theme.background,
    );

    // 主题切到深色，弹窗内的文本主题跟着变。
    // （上一步 ensureVisible 把内容滚到了终端分区，先滚回外观分区。）
    await tester.ensureVisible(find.text('深色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('终端主题'))).brightness,
      Brightness.dark,
    );

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.textContaining('v0.4.4'), findsNothing, reason: '弹窗应已关闭');
  });

  test('终端样式偏好：默认字号比旧版大两号，越界夹住，自定义字体名可解析', () {
    const defaults = TerminalStylePrefs();
    // 旧版写死 13，用户反馈偏小：默认值上调两号。
    expect(TerminalStylePrefs.defaultFontSize, 15);
    expect(defaults.fontSize, 15);
    expect(defaults.resolvedFontFamily, 'monospace', reason: '系统默认走等宽族名');

    expect(
      defaults.withFontSize(TerminalStylePrefs.minFontSize - 5).fontSize,
      TerminalStylePrefs.minFontSize,
    );
    expect(
      defaults.withFontSize(TerminalStylePrefs.maxFontSize + 5).fontSize,
      TerminalStylePrefs.maxFontSize,
    );

    // 自定义字体：名字两端空格不影响，留空退回等宽族名。
    const custom = TerminalStylePrefs(
      font: TerminalFont.custom,
      customFontName: '  Fira Code  ',
    );
    expect(custom.resolvedFontFamily, 'Fira Code');
    expect(
      const TerminalStylePrefs(font: TerminalFont.custom).resolvedFontFamily,
      'monospace',
    );
    // 其它预设不受自定义名影响。
    expect(
      custom.copyWith(font: TerminalFont.menlo).resolvedFontFamily,
      'Menlo',
    );
  });

  testWidgets('设置弹窗：终端字号可增减，预览字号跟着变', (tester) async {
    await pumpDesktop(tester);
    await openSettings(tester);
    await tester.ensureVisible(find.text('终端字号'));
    await tester.pumpAndSettle();

    final scope = TerminalStyleScope.of(tester.element(find.text('终端字号')));
    expect(scope.notifier.value.fontSize, TerminalStylePrefs.defaultFontSize);

    double previewFontSize() {
      final preview = tester.widget<Text>(
        find.textContaining('ssh deploy@10.0.0.1'),
      );
      return (preview.textSpan! as TextSpan).style!.fontSize!;
    }

    expect(previewFontSize(), TerminalStylePrefs.defaultFontSize.toDouble());

    await tester.tap(find.byTooltip('增大字号'));
    await tester.pumpAndSettle();
    expect(
      scope.notifier.value.fontSize,
      TerminalStylePrefs.defaultFontSize + 1,
    );
    expect(previewFontSize(), TerminalStylePrefs.defaultFontSize + 1.0);

    await tester.tap(find.byTooltip('减小字号'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('减小字号'));
    await tester.pumpAndSettle();
    expect(
      scope.notifier.value.fontSize,
      TerminalStylePrefs.defaultFontSize - 1,
    );
    expect(previewFontSize(), TerminalStylePrefs.defaultFontSize - 1.0);
  });

  testWidgets('设置弹窗：选「自定义字体」后填字体名即生效', (tester) async {
    await pumpDesktop(tester);
    await openSettings(tester);
    await tester.ensureVisible(find.text('终端字体'));
    await tester.pumpAndSettle();

    final scope = TerminalStyleScope.of(tester.element(find.text('终端字体')));
    // 「系统默认」在界面字体与终端字体两处都有，这里限定在终端字体控件内。
    await tester.tap(
      find.descendant(
        of: find.byType(TerminalFontDropdown),
        matching: find.text('系统默认'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义字体…').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'Fira Code');
    await tester.pumpAndSettle();

    expect(scope.notifier.value.font, TerminalFont.custom);
    expect(scope.notifier.value.resolvedFontFamily, 'Fira Code');
    final preview = tester.widget<Text>(
      find.textContaining('ssh deploy@10.0.0.1'),
    );
    expect((preview.textSpan! as TextSpan).style!.fontFamily, 'Fira Code');
  });

  testWidgets('设置弹窗在最小窗口下不溢出，内容可滚动到语言分区', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    tester.view.physicalSize = const Size(640, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(NoShellApp(credentials: FakeCredentialStore()));
    await tester.pump();
    await openSettings(tester);

    // 弹窗完整落在窗口内；内容装不下时内部滚动，不撑破窗口。
    final dialog = tester.getRect(find.byType(Dialog));
    expect(dialog.left, greaterThanOrEqualTo(0));
    expect(dialog.top, greaterThanOrEqualTo(0));
    expect(dialog.right, lessThanOrEqualTo(640));
    expect(dialog.bottom, lessThanOrEqualTo(560));

    await tester.ensureVisible(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
  });
}
