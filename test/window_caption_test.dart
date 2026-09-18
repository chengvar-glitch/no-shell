import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:no_shell/main.dart';
import 'package:no_shell/store.dart';
import 'package:no_shell/widgets/app_icon_mark.dart';
import 'package:no_shell/widgets/window_caption.dart';

import 'support/credential_store_fake.dart';
import 'support/demo_servers.dart';

void main() {
  // 自绘标题条只在 Windows / Linux 生效，测试统一钉在 Linux 平台；
  // window_manager 插件在测试环境无平台实现，mock 掉 method channel。
  // 平台覆盖是 foundation 全局变量，框架在测试体内校验复位，须 try/finally。
  Future<void> pumpLinuxDesktop(
    WidgetTester tester, {
    List<String>? calls,
  }) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async {
        calls?.add(call.method);
        return switch (call.method) {
          'isMaximized' => false,
          _ => null,
        };
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      ),
    );
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

  testWidgets('macOS 不渲染自绘标题条，且启动时不调用窗口插件（避免崩溃）', (tester) async {
    // 回归：initState 无条件调用 isMaximized 时，window_manager 的
    // macOS 原生实现在窗口就绪前强解包 nil，Release 启动即崩。
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      ),
    );
    try {
      await tester.pumpWidget(
        NoShellApp(
          store: ServerStore(seed: demoServers),
          credentials: FakeCredentialStore(),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.minimize), findsNothing);
      expect(calls, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Linux 收起侧边栏后，展开按钮跟着标题条行内走且可点回', (tester) async {
    try {
      await pumpLinuxDesktop(tester);

      expect(sidebarSlot(tester).size.width, 264);
      await tester.tap(find.byIcon(Icons.menu_open));
      await tester.pumpAndSettle();
      expect(sidebarSlot(tester).size.width, 0);

      // 未选中主机时详情区是空状态，展开按钮排进标题条这一行：
      // 与窗口按钮同一条垂直中心线（不再浮到内容左上角、像掉到了下一行），
      // 并且不在拖拽热区里——拖拽区不能吞掉它的点击。
      final expandIcon = find.byIcon(Icons.view_sidebar);
      expect(
        tester.getCenter(expandIcon).dy,
        tester.getCenter(find.byIcon(Icons.minimize)).dy,
      );
      expect(tester.getTopLeft(expandIcon).dx, lessThan(100));

      await tester.tap(expandIcon);
      await tester.pumpAndSettle();
      expect(sidebarSlot(tester).size.width, 264);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Linux：详情头部排进标题条行内，操作按钮跟在服务器名右侧', (tester) async {
    try {
      await pumpLinuxDesktop(tester);
      await tester.tap(find.text('web-prod-01'));
      await tester.pumpAndSettle();

      // 侧边栏主机行与详情头部都会显示主机名，断言限定在标题条里的那一个。
      final title = find.descendant(
        of: find.byType(WindowCaptionBar),
        matching: find.text('web-prod-01'),
      );

      // 内容整体上移：服务器名就在标题条这一行里，而不是另起一行。
      expect(tester.getCenter(title).dy, lessThan(kWindowCaptionHeight));

      // 断开 / 连接按钮跟在名字后面，不再贴面板右端，
      // 免得内容上移后和窗口的关闭按钮挤在一起。
      // 详情头部的「⋯」已移除（删除入口在侧边栏主机右键菜单）。
      final connectRect = tester.getRect(find.byIcon(Icons.bolt_rounded));
      final minimizeLeft = tester.getTopLeft(find.byIcon(Icons.minimize)).dx;
      expect(connectRect.left, greaterThan(tester.getTopRight(title).dx));
      expect(connectRect.right, lessThan(minimizeLeft));

      // 标签行仍然排在标题条之下（不齐进 48px 的行内）。
      expect(
        tester.getTopLeft(find.text('nginx')).dy,
        greaterThanOrEqualTo(kWindowCaptionHeight),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Linux：侧边栏头部顶到窗口最上沿，且与窗口按钮同一行、都不贴边', (tester) async {
    try {
      await pumpLinuxDesktop(tester);

      // 头部品牌标是应用自己的图标（不是通用终端字形占位）。
      final logoTop = tester.getTopLeft(find.byType(AppIconMark)).dy;
      // 头部内容整体落在标题区行内：顶部不再留白，视觉上就没有「侧边栏之上
      // 还有一条标题栏」的观感；同时必须留出呼吸感，不能贴着窗口上沿。
      expect(logoTop, lessThan(kWindowCaptionHeight));
      expect(logoTop, greaterThanOrEqualTo(6));
      expect(
        tester.getTopLeft(find.text('NoShell')).dy,
        lessThan(kWindowCaptionHeight),
      );
      expect(
        tester.getTopLeft(find.byType(TextField)).dy,
        kWindowCaptionHeight + 10,
        reason: '搜索框应紧贴标题区下方，不再多让出一整条标题栏的空档',
      );

      // 侧边栏头部与窗口按钮同一行：垂直中心线对齐。
      expect(
        tester.getCenter(find.byIcon(Icons.menu_open)).dy,
        tester.getCenter(find.byIcon(Icons.minimize)).dy,
      );

      // 窗口按钮不顶到窗口边缘：与面板内边距同一套节奏。
      final closeRight = tester.getRect(find.byIcon(Icons.close_rounded)).right;
      expect(closeRight, lessThanOrEqualTo(1280 - kWindowCaptionButtonInset));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Linux：标题条拖拽区撑满整条高度，拖动直达窗口插件', (tester) async {
    try {
      final calls = <String>[];
      await pumpLinuxDesktop(tester, calls: calls);

      final dragArea = find.byKey(const ValueKey('window-caption-drag'));
      // 回归：行内的拖拽区没有子控件，交叉轴若按 center 布局会被压成 0 高，
      // 整条标题栏就只剩右侧三个按钮可点，窗口拖不动。
      expect(tester.getSize(dragArea).height, kWindowCaptionHeight);

      final gesture = await tester.startGesture(tester.getCenter(dragArea));
      await gesture.moveBy(const Offset(40, 0));
      await gesture.up();
      await tester.pump();
      expect(calls, contains('startDragging'));

      // 标题条同时注册了双击最大化，手势结束后要等双击判定窗口关闭，
      // 否则测试树销毁时会因残留 Timer 报错。
      await tester.pump(const Duration(milliseconds: 400));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Linux：侧边栏头部空白处可拖动窗口，同区域按钮照旧可点', (tester) async {
    try {
      final calls = <String>[];
      await pumpLinuxDesktop(tester, calls: calls);

      expect(
        tester
            .getSize(find.byKey(const ValueKey('sidebar-header-drag')))
            .height,
        kWindowCaptionHeight,
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('NoShell')),
      );
      await gesture.moveBy(const Offset(20, 0));
      await gesture.up();
      await tester.pump();
      expect(calls, contains('startDragging'));

      // 拖拽区不能吞掉同一行里按钮的点击。
      calls.clear();
      await tester.tap(find.byIcon(Icons.menu_open));
      await tester.pumpAndSettle();
      expect(sidebarSlot(tester).size.width, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('自绘标题栏：三个窗口按钮尺寸一致、字形居中且不顶满按钮', (tester) async {
    try {
      await pumpLinuxDesktop(tester);

      const icons = [
        Icons.minimize,
        Icons.crop_square_rounded,
        Icons.close_rounded,
      ];
      for (final icon in icons) {
        final iconRect = tester.getRect(find.byIcon(icon));
        final button = find
            .ancestor(of: find.byIcon(icon), matching: find.byType(Container))
            .first;
        final buttonRect = tester.getRect(button);
        // 命中区按设计常量给尺寸，且比标题区矮——按钮在标题区里垂直居中，
        // 不会顶到窗口上下沿。
        expect(buttonRect.size, kWindowCaptionButtonSize);
        expect(buttonRect.height, lessThan(kWindowCaptionHeight));
        // 字形盒必须小于按钮：无 alignment 时 Container 的紧约束会把
        // 文本盒撑满整个按钮，图标字形被画在左上角，中心重合是假象。
        expect(
          iconRect.size,
          lessThan(kWindowCaptionButtonSize),
          reason: '$icon 的字形盒撑满了整个按钮',
        );
        expect(iconRect.center, buttonRect.center, reason: '$icon 未在按钮内居中');
        // 按钮也垂直居中于标题区。
        expect(buttonRect.center.dy, kWindowCaptionHeight / 2);
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
