import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:no_shell/main.dart';
import 'package:no_shell/mobile/server_edit_page.dart';
import 'package:no_shell/mobile/servers_tab.dart';
import 'package:no_shell/mobile/settings_tab.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/mobile/server_detail_page.dart';
import 'package:no_shell/settings.dart';
import 'package:no_shell/ssh/host_key_store.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/jump_host.dart';
import 'package:no_shell/store.dart';
import 'package:no_shell/widgets/settings_controls.dart';

import 'support/credential_store_fake.dart';
import 'support/demo_servers.dart';
import 'support/host_key_store_fake.dart';

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
    FakeHostKeyStore? hostKeys,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(
      NoShellApp(
        // 未显式传 store 时注入示例数据，非空列表语义由测试自持。
        store: store ?? ServerStore(seed: demoServers),
        credentials: credentials ?? FakeCredentialStore(),
        hostKeys: hostKeys,
        // 测试机可能真挂着 agent，注入「没有」保持确定性。
        agentKeysProbe: () async => false,
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

  testWidgets('详情页删除主机：凭据与指纹一并清理', (tester) async {
    final credentials = FakeCredentialStore();
    final hostKeys = FakeHostKeyStore();
    final store = ServerStore(seed: [demoServers.first]);
    await credentials.write(
      demoServers.first.id,
      const SshCredentials(password: 'pw'),
    );
    await hostKeys.save(
      demoServers.first.host,
      demoServers.first.port,
      const HostKeyRecord(fingerprint: 'SHA256:old'),
    );

    await pumpMobile(
      tester,
      store: store,
      credentials: credentials,
      hostKeys: hostKeys,
    );

    await tester.tap(find.text('web-prod-01'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(ServerDetailPage),
        matching: find.byIcon(Icons.delete_outline_rounded),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(store.byId('srv-01'), isNull);
    expect(credentials.deleteCount, 1, reason: '已存凭据要跟着主机一起清掉');
    // 指纹按 host:port 存：不清的话同地址的新机器会被判成「密钥变了」。
    expect(
      hostKeys.records(demoServers.first.host, demoServers.first.port),
      isEmpty,
      reason: '删除主机要连指纹一起清',
    );
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

  testWidgets('设置面板可切换终端字体与终端配色预设', (tester) async {
    await pumpMobile(tester);

    await tester.tap(navLabel('设置'));
    await tester.pumpAndSettle();
    // 界面字体不提供自定义：外观分区只剩主题一项。
    expect(find.text('界面字体'), findsNothing);
    expect(find.text('终端主题'), findsOneWidget);
    expect(find.text('终端字体'), findsOneWidget);
    // 与桌面设置弹窗共用同一套分组卡片：没有分隔线，靠底色与间距分层。
    // （ListView 只挂载可见子树，分区数量断言留给桌面弹窗那份用例。）
    expect(find.byType(Divider), findsNothing);
    expect(find.byType(SettingsSection), findsWidgets);

    // 终端字体：切到内置 Fira Code 后写入全局终端样式作用域。
    await tester.tap(find.byType(DropdownButtonFormField<TerminalFont>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fira Code').last);
    await tester.pumpAndSettle();
    expect(
      TerminalStyleScope.of(tester.element(find.text('外观')))
          .notifier
          .value
          .font,
      TerminalFont.firaCode,
    );
    // 字体名输入框不存在：字体只能在随包内置与系统等宽之间选。
    // （IndexedStack 里其它 Tab 的搜索框仍在树上，这里限定在设置页内。）
    expect(
      find.descendant(
        of: find.byType(SettingsTab),
        matching: find.byType(TextField),
      ),
      findsNothing,
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
    // （生物识别锁定占位行已移除，信息卡只剩「关于」。）
    await tester.scrollUntilVisible(find.text('关于'), 200);

    // 窄屏下分段标签必须单行：段内边距收窄一档就是为了这个（见 AppTheme）。
    expect(tester.getSize(find.text('English')).height, lessThan(20));
  });

  testWidgets('长按主机可把它移到另一个分组', (tester) async {
    final store = ServerStore(seed: demoServers);
    await pumpMobile(tester, store: store);

    await tester.longPress(find.text('db-primary'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移动到分组…'));
    await tester.pumpAndSettle();
    // 背后的列表里也有同名分组头，这里只要弹层里那一个。
    await tester.tap(
      find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('个人服务器'),
      ),
    );
    await tester.pumpAndSettle();

    expect(store.byId('srv-04')?.group, '个人服务器');
  });

  testWidgets('点分组头折叠，主机行收起来且折叠态进 store', (tester) async {
    final store = ServerStore(seed: demoServers);
    await pumpMobile(tester, store: store);
    expect(find.text('web-prod-01'), findsOneWidget);

    await tester.tap(find.text('生产环境'));
    await tester.pumpAndSettle();

    expect(find.text('web-prod-01'), findsNothing);
    expect(
      store.groups().firstWhere((group) => group.name == '生产环境').collapsed,
      isTrue,
    );
  });

  testWidgets('矮屏横屏下分组菜单与主机菜单靠滚动兜住，不溢出', (tester) async {
    // 568x320：弹层默认限高 9/16 屏高（180），装不下 6 项分组菜单。
    await pumpMobile(tester, size: const Size(568, 320));

    await tester.tap(
      find
          .descendant(
            of: find.byType(ServersTab),
            matching: find.byIcon(Icons.more_horiz_rounded),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 点遮罩收起，再看长按主机那一张（4 项）。
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('web-prod-01'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('分组头「⋯」是触屏上分组管理的唯一入口，命中区给足', (tester) async {
    await pumpMobile(tester);

    final button = find
        .ancestor(
          of: find
              .descendant(
                of: find.byType(ServersTab),
                matching: find.byIcon(Icons.more_horiz_rounded),
              )
              .first,
          matching: find.byType(IconButton),
        )
        .first;
    expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
  });

  testWidgets('主机页导入导出菜单只有两项，且不露出内部实现字样', (tester) async {
    await pumpMobile(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('导入主机'), findsOneWidget);
    expect(find.text('导出主机'), findsOneWidget);
    // 与桌面侧边栏同一条约定：不出现「备份 / 加密」，也不留第二套入口。
    expect(find.textContaining('备份'), findsNothing);
    expect(find.textContaining('加密'), findsNothing);
  });

  group('极窄竖屏不溢出', () {
    // 此前最窄的竖屏用例是 390x844，小屏只有一条 568x320 横屏；
    // 320x568（iPhone SE 一代）这类真实竖屏从未被覆盖过。
    for (final size in const [Size(320, 568), Size(360, 640)]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}：主机页与设置页都不溢出', (
        tester,
      ) async {
        await pumpMobile(tester, size: size);

        // Flutter 的溢出会以异常形式抛出，测试框架会直接判失败；
        // 这里再显式确认关键元素都还在。
        expect(find.text('web-prod-01'), findsOneWidget);
        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsSection), findsWidgets);
      });
    }
  });

  testWidgets('编辑主机：跳板机可选，且不会顺手抹掉端口转发规则', (tester) async {
    // 这两条都是「一次编辑就静默丢配置」的高危路径：编辑页是从零构造
    // SshServer 的，没显式带上的字段全部归零。用测试把契约钉住。
    const jump = SshServer(
      id: 'srv-jump',
      group: '默认分组',
      name: 'jump-host',
      host: '10.0.0.9',
      username: 'root',
    );
    const rule = PortForwardRule(
      id: 'fwd-1',
      mode: PortForwardMode.local,
      localPort: 8080,
      remotePort: 80,
    );
    const target = SshServer(
      id: 'srv-target',
      group: '默认分组',
      name: 'target-host',
      host: '10.0.0.1',
      username: 'root',
      forwards: [rule],
    );
    final store = ServerStore(seed: [jump, target]);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: ServerEditPage(
          store: store,
          credentials: FakeCredentialStore(),
          initial: target,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 跳板机下拉在表单靠下的位置：ListView 懒构建，得先滚到它被建出来
    // 才点得到（分组多了一行说明，它会落在缓存区之外）。
    await tester.dragUntilVisible(
      find.text('不使用'),
      find.byType(ListView),
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    // 默认「不使用」，展开后选中 jump-host。
    await tester.tap(find.text('不使用'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('jump-host').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = store.byId('srv-target')!;
    expect(saved.jumpServerId, 'srv-jump');
    expect(saved.forwards, hasLength(1));
    expect(saved.forwards.single.id, 'fwd-1');
    // 下游连接流程据此解析链路：存进去的必须是「外」那一跳的 id。
    expect(resolveJumpChain(saved, store.byId).map((s) => s.id), ['srv-jump']);
  });
}
