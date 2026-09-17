import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:no_shell/main.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/store.dart';
import 'package:no_shell/widgets/window_caption.dart';

import 'support/credential_store_fake.dart';
import 'support/demo_servers.dart';

void main() {
  // 应用已国际化，钉住中文系统语言以匹配下方中文断言。
  // 凭据存储注入内存假实现：真插件在测试环境无平台注册，调用会挂起。
  Future<void> pumpDesktop(WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(
      NoShellApp(
        store: ServerStore(seed: demoServers),
        credentials: FakeCredentialStore(),
      ),
    );
    await tester.pump();
  }

  RenderBox sidebarSlot(WidgetTester tester) => tester.renderObject<RenderBox>(
    find.byKey(const ValueKey('sidebar-slot')),
  );

  testWidgets('分栏布局：侧边栏渲染，选中主机后展示详情', (tester) async {
    await pumpDesktop(tester);

    expect(find.text('NoShell'), findsOneWidget);
    expect(find.text('选择左侧主机开始'), findsOneWidget);

    await tester.tap(find.text('web-prod-01'));
    await tester.pump();

    expect(find.text('概览'), findsOneWidget);
    expect(find.text('主机地址'), findsOneWidget);
    expect(find.text('10.0.1.11'), findsOneWidget);
  });

  testWidgets('搜索框过滤主机列表', (tester) async {
    await pumpDesktop(tester);

    await tester.enterText(find.byType(TextField), 'db');
    await tester.pump();

    expect(find.text('db-primary'), findsOneWidget);
    expect(find.text('web-prod-01'), findsNothing);
    expect(find.text('没有匹配的主机', skipOffstage: false), findsNothing);
  });

  testWidgets('删除主机先弹确认框：取消保留，确认后删除', (tester) async {
    await pumpDesktop(tester);

    Future<void> askDelete() async {
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除主机'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('web-prod-01'));
    await tester.pump();
    await askDelete();

    // 确认框出现，取消后主机仍在列表里。
    expect(find.text('删除「web-prod-01」？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('web-prod-01'), findsWidgets);

    // 再次发起并确认，主机被移除并出现可撤销提示。
    await askDelete();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('web-prod-01'), findsNothing);
    expect(find.text('已删除 web-prod-01'), findsOneWidget);
  });

  testWidgets('新建连接弹窗粘贴元数据后保存，密码写入凭据存储', (tester) async {
    final store = ServerStore(seed: const []);
    final credentials = FakeCredentialStore();
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(NoShellApp(store: store, credentials: credentials));
    await tester.pump();

    await tester.tap(find.byTooltip('新建连接'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '粘贴元数据（可选）'),
      '名称: fofo\n地址: 127.0.0.1\n端口: 2222\n用户: root\n密码: password',
    );
    await tester.pump();
    expect(find.widgetWithText(TextFormField, 'fofo'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '127.0.0.1'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final server = store.servers.single;
    expect(server.host, '127.0.0.1');
    expect(server.port, 2222);
    expect(server.username, 'root');
    expect(server.authMethod, AuthMethod.password);
    expect(credentials[server.id]?.password, 'password');
    expect(find.text('fofo'), findsWidgets);
  });

  testWidgets('侧边栏可收起与展开', (tester) async {
    await pumpDesktop(tester);

    RenderBox sidebarSlot() => tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('sidebar-slot')),
    );
    expect(sidebarSlot().size.width, 264);

    await tester.tap(find.byIcon(Icons.menu_open));
    await tester.pumpAndSettle();
    expect(sidebarSlot().size.width, 0);
    expect(find.byIcon(Icons.view_sidebar), findsOneWidget);

    await tester.tap(find.byIcon(Icons.view_sidebar));
    await tester.pumpAndSettle();
    expect(sidebarSlot().size.width, 264);
    expect(find.byIcon(Icons.view_sidebar), findsNothing);
  });

  testWidgets('macOS 收起侧边栏：标签行跟随头部缩进，行内按钮可展开', (tester) async {
    // 回归：收起侧边栏后头部平移到红绿灯右侧（96），标签行却留在面板
    // 常规内边距 16，孤零零挂在红绿灯那一列；且收起态没有行内展开按钮，
    // 只能靠 ⌘B 找回侧边栏。
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pumpDesktop(tester);

      await tester.tap(find.text('web-prod-01'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.menu_open));
      await tester.pumpAndSettle();

      // 标签行与收起后的头部同一列：缩进 96（红绿灯右缘约 82）。
      final tagsRow = find.descendant(
        of: find.byKey(const ValueKey('detail-header-tags')),
        matching: find.byType(Wrap),
      );
      expect(tester.getRect(tagsRow).left, kMacOSTrafficLightsIndent);

      // 行内展开按钮可见，点击后侧边栏恢复、标签回到常规内边距。
      expect(find.byIcon(Icons.view_sidebar), findsOneWidget);
      await tester.tap(find.byIcon(Icons.view_sidebar));
      await tester.pumpAndSettle();
      expect(sidebarSlot(tester).size.width, 264);
      // 详情面板起点 = 侧边栏 264 + 拖拽条 9，标签回到面板常规内边距 16。
      expect(tester.getRect(tagsRow).left, 264 + 9 + 16);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS 空态收起侧边栏：浮动展开按钮与红绿灯同一中心线', (tester) async {
    // 回归：展开按钮用过旧的红绿灯参数（top 3，中心 y≈16），红绿灯北移后
    // 按钮浮在灯上方 11pt、且左缘贴着灯位；应落在头部行中心线 y≈27、
    // 缩进 96 与详情头部同列。
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pumpDesktop(tester);

      await tester.tap(find.byIcon(Icons.menu_open));
      await tester.pumpAndSettle();

      // 只断言不随主题密度漂移的几何：本文件里更早的用例以默认平台（Android）
      // 先建过缓存主题（main.dart 的 static final ThemeData），visualDensity
      // / 触达目标尺寸已被固化，按钮渲染高度会随先到平台变化；
      // 而定位由外层 Padding 决定，恒为 left 96、top 中心线 27 - 半高 13。
      // find.ancestor 由近及远排列，最后一个才是我们加的定位 Padding。
      final padding = tester.widget<Padding>(
        find
            .ancestor(
              of: find.byIcon(Icons.view_sidebar),
              matching: find.byType(Padding),
            )
            .last,
      );
      expect(
        padding.padding,
        EdgeInsets.only(
          left: kMacOSTrafficLightsIndent,
          top: kMacOSTrafficLightsCenterY - 13,
        ),
      );
      final buttonRect = tester.getRect(
        find.ancestor(
          of: find.byIcon(Icons.view_sidebar),
          matching: find.byType(IconButton),
        ),
      );
      expect(buttonRect.top, kMacOSTrafficLightsCenterY - 13);
      expect(buttonRect.left, kMacOSTrafficLightsIndent);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('主题默认跟随系统：系统浅色 → 浅色界面', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    await tester.pumpWidget(const NoShellApp());
    await tester.pump();
    expect(
      Theme.of(tester.element(find.text('NoShell'))).brightness,
      Brightness.light,
    );
  });

  testWidgets('主题默认跟随系统：系统深色 → 深色界面', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    await tester.pumpWidget(const NoShellApp());
    await tester.pump();
    expect(
      Theme.of(tester.element(find.text('NoShell'))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('跟随系统深色时可手动切换浅色', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    await tester.pumpWidget(const NoShellApp());
    await tester.pump();
    expect(
      Theme.of(tester.element(find.text('NoShell'))).brightness,
      Brightness.dark,
    );

    // 主题切换收在设置弹窗里。「浅色」既是主题分段也是终端浅色预设的名字，
    // 断言限定在主题分段控件内。
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<ThemeMode>),
        matching: find.text('浅色'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('NoShell'))).brightness,
      Brightness.light,
    );
  });
}
