import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:no_shell/main.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/settings.dart';
import 'package:no_shell/store.dart';
import 'package:no_shell/widgets/settings_controls.dart';

import 'support/credential_store_fake.dart';
import 'support/demo_servers.dart';

Finder navLabel(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  // 390x844（iPhone 14 尺寸），让 LayoutBuilder 走移动端分支。
  // 应用已国际化，钉住中文系统语言以匹配下方中文断言。
  // 凭据存储注入内存假实现：真插件在测试环境无平台注册，调用会挂起。
  Future<void> pumpMobile(
    WidgetTester tester, {
    ServerStore? store,
    FakeCredentialStore? credentials,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(
      NoShellApp(
        // 未显式传 store 时注入示例数据，非空列表语义由测试自持。
        store: store ?? ServerStore(seed: demoServers),
        credentials: credentials ?? FakeCredentialStore(),
      ),
    );
    await tester.pump();
  }

  testWidgets('窄屏显示底部导航骨架，可切换到终端与设置', (tester) async {
    await pumpMobile(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('web-prod-01'), findsOneWidget);

    await tester.tap(navLabel('终端'));
    await tester.pumpAndSettle();
    // 连接状态由真实 SSH 会话驱动：刚启动还没有会话，展示空态引导。
    expect(find.text('暂无活跃会话'), findsOneWidget);

    await tester.tap(navLabel('设置'));
    await tester.pumpAndSettle();
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
  });

  testWidgets('点击主机进入移动端详情页，连接前弹出凭据确认', (tester) async {
    await pumpMobile(tester);

    await tester.tap(find.text('db-primary'));
    await tester.pumpAndSettle();

    expect(find.text('未连接'), findsOneWidget);
    expect(find.text('主机地址'), findsOneWidget);

    // 真实连接需要凭据：弹出认证弹窗，取消后不建立会话。
    await tester.tap(find.text('立即连接'));
    await tester.pumpAndSettle();
    expect(find.text('连接「db-primary」'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('连接「db-primary」'), findsNothing);
    expect(find.text('立即连接'), findsOneWidget);

    // 终端 Tab 在未建立会话时展示引导文案。
    await tester.tap(
      find.descendant(of: find.byType(TabBar), matching: find.text('终端')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('会话未建立', findRichText: true), findsOneWidget);
  });

  testWidgets('新建连接表单可校验并保存', (tester) async {
    await pumpMobile(tester);

    await tester.tap(find.text('新建连接'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('请输入名称'), findsOneWidget);
    expect(find.text('请输入主机'), findsOneWidget);
    expect(find.text('请输入用户名'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'test-mobile');
    await tester.enterText(find.byType(TextFormField).at(1), '1.2.3.4');
    await tester.enterText(find.byType(TextFormField).at(3), 'root');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 新主机落在「默认分组」，位于长列表底部（ListView 懒加载），需滚动到可见。
    await tester.dragUntilVisible(
      find.text('test-mobile'),
      find.byType(ListView),
      const Offset(0, -60),
    );
    expect(find.text('test-mobile'), findsOneWidget);
  });

  testWidgets('粘贴元数据填表后仍可手改，保存时记住密码', (tester) async {
    final store = ServerStore(seed: const []);
    final credentials = FakeCredentialStore();
    await pumpMobile(tester, store: store, credentials: credentials);

    await tester.tap(find.text('新建连接'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '粘贴元数据（可选）'),
      '名称: fofo\n地址: 127.0.0.1\n端口: 22\n用户: root\n密码: password',
    );
    await tester.pump();

    // 元数据已填进下方表单。
    expect(find.widgetWithText(TextFormField, 'fofo'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '127.0.0.1'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'root'), findsOneWidget);

    // 手动覆盖端口，两处输入共存。
    await tester.enterText(find.byType(TextFormField).at(2), '2222');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final server = store.servers.single;
    expect(server.name, 'fofo');
    expect(server.host, '127.0.0.1');
    expect(server.port, 2222);
    expect(server.username, 'root');
    expect(server.authMethod, AuthMethod.password);
    expect(credentials[server.id]?.password, 'password');
    expect(find.text('fofo'), findsWidgets);
  });

  testWidgets('设置面板可切换界面字体与终端配色预设', (tester) async {
    await pumpMobile(tester);

    await tester.tap(navLabel('设置'));
    await tester.pumpAndSettle();
    expect(find.text('界面字体'), findsOneWidget);
    expect(find.text('终端主题'), findsOneWidget);
    expect(find.text('终端字体'), findsOneWidget);
    // 与桌面设置弹窗共用同一套分组卡片：没有分隔线，靠底色与间距分层。
    // （ListView 只挂载可见子树，分区数量断言留给桌面弹窗那份用例。）
    expect(find.byType(Divider), findsNothing);
    expect(find.byType(SettingsSection), findsWidgets);

    // 界面字体：选择 PingFang 后，ThemeData 文本主题的字体随之生效。
    await tester.tap(find.byType(DropdownButtonFormField<UiFont>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PingFang 苹方').last);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('外观')))
          .textTheme
          .bodyMedium
          ?.fontFamily,
      'PingFang SC',
    );

    // 终端预设：切换为 Dracula 后写入全局终端样式作用域。
    await tester.tap(find.byType(DropdownButtonFormField<TerminalPreset>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dracula').last);
    await tester.pumpAndSettle();
    expect(
      TerminalStyleScope.of(tester.element(find.text('外观')))
          .notifier
          .value
          .preset,
      TerminalPreset.dracula,
    );

    // 底部信息行在折叠区外，滚到底才参与布局：这里顺带守住不溢出。
    await tester.scrollUntilVisible(find.text('关于'), 200);
    expect(find.text('即将推出'), findsOneWidget);

    // 窄屏下分段标签必须单行：段内边距收窄一档就是为了这个（见 AppTheme）。
    expect(tester.getSize(find.text('English')).height, lessThan(20));
  });
}
