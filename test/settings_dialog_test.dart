import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:no_shell/main.dart';
import 'package:no_shell/settings.dart';
import 'package:no_shell/theme.dart';
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

    // 头部只剩一行标题（版本号收进「关于」），三段分区齐全、没有说明小字。
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('终端'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);
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
    expect(find.byType(Dialog), findsNothing, reason: '弹窗应已关闭');
  });

  test('终端样式偏好：默认字体是随包内置，字号越界夹住', () {
    const defaults = TerminalStylePrefs();
    // 旧版写死 13，用户反馈偏小：默认值上调两号。
    expect(TerminalStylePrefs.defaultFontSize, 15);
    expect(defaults.fontSize, 15);
    expect(defaults.font, TerminalFont.jetBrainsMono);
    expect(
      defaults.resolvedFontFamily,
      'NoShell JetBrains Mono',
      reason: '默认终端字体是随包内置的族，任何平台都必定命中',
    );

    expect(
      defaults.withFontSize(TerminalStylePrefs.minFontSize - 5).fontSize,
      TerminalStylePrefs.minFontSize,
    );
    expect(
      defaults.withFontSize(TerminalStylePrefs.maxFontSize + 5).fontSize,
      TerminalStylePrefs.maxFontSize,
    );

    // 「系统等宽」走通用族名，由平台解析成真正的等宽字体（不会是比例字体）。
    const system = TerminalStylePrefs(font: TerminalFont.systemMonospace);
    expect(system.resolvedFontFamily, 'monospace');
    // 回退链只用于「缺字形」，末尾必须落在等宽族名上：比例字体落进终端网格
    // 比缺字更难看，所以链里不能出现 sans-serif。
    expect(system.fontFallback.last, 'monospace');
    expect(system.fontFallback, isNot(contains('sans-serif')));
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

  testWidgets('设置弹窗：终端字体只能在随包内置与系统等宽之间选', (tester) async {
    await pumpDesktop(tester);
    await openSettings(tester);
    await tester.ensureVisible(find.text('终端字体'));
    await tester.pumpAndSettle();

    final scope = TerminalStyleScope.of(tester.element(find.text('终端字体')));
    expect(scope.notifier.value.font, TerminalFont.jetBrainsMono);

    // 没有自由填写字体名的入口：那个入口正是 Linux 上被 fontconfig 顶替成
    // 比例字体、终端网格散架的事故来源（见 TerminalFont 注释）。
    // （弹窗背后侧边栏还有搜索框，这里限定在弹窗内。）
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );

    await tester.tap(find.byType(DropdownButtonFormField<TerminalFont>));
    await tester.pumpAndSettle();
    // 选到内置 Fira Code：族名换成随包声明的那一个，预览同步。
    await tester.tap(find.text('Fira Code').last);
    await tester.pumpAndSettle();

    expect(scope.notifier.value.font, TerminalFont.firaCode);
    expect(scope.notifier.value.resolvedFontFamily, 'NoShell Fira Code');
    final preview = tester.widget<Text>(
      find.textContaining('ssh deploy@10.0.0.1'),
    );
    expect(
      (preview.textSpan! as TextSpan).style!.fontFamily,
      'NoShell Fira Code',
    );
  });

  testWidgets('设置弹窗：卡片不描边、不画分隔线，标签与分区标题同一列', (tester) async {
    await pumpDesktop(tester);
    await openSettings(tester);

    // 弹窗里一根分隔线都没有：头部 / 底部 / 卡片内全靠间距与底色分层。
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.byType(Divider)),
      findsNothing,
    );

    // 分组卡片是面板底色的实心块（比页面底色亮一档），没有边框。
    final section = find.byType(SettingsSection).first;
    final card = tester.widget<Container>(
      find.descendant(of: section, matching: find.byType(Container)).first,
    );
    final decoration = card.decoration! as BoxDecoration;
    expect(decoration.border, isNull);
    expect(
      decoration.color,
      Theme.of(tester.element(section)).panelBackground,
      reason: '卡片靠底色（比页面亮一档）分层，不靠描边',
    );

    // 行标签与分区标题文字落在同一条竖线上（图标宽 14 + 间距 7）。
    expect(
      tester.getTopLeft(find.text('主题')).dx,
      tester.getTopLeft(find.text('外观')).dx,
    );
  });

  testWidgets('下拉按钮与菜单项的文字颜色必须显式给出', (tester) async {
    // 回归：DropdownButton 内部用 DefaultTextStyle(style: 传入的 style) **替换**
    // 环境样式（不是 merge），样式里漏掉 color 就等于把文字颜色一起丢了，
    // 按钮和整个菜单会一起变成近白色（浅色主题下就是「泛白」）。
    await pumpDesktop(tester);
    await openSettings(tester);

    await tester.tap(find.byType(DropdownButtonFormField<TerminalFont>));
    await tester.pumpAndSettle();

    final itemContext = tester.element(find.text('系统等宽').last);
    final color = DefaultTextStyle.of(itemContext).style.color;
    expect(color, isNotNull);
    expect(
      color,
      Theme.of(itemContext).colorScheme.onSurface,
      reason: '菜单项文字用主题前景色，才与菜单底色分得开',
    );
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
