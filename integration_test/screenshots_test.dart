// README 截图生成器：驱动真实应用（macOS 窗口、真实字体、真实 SSH 链路），
// 在渲染层直接导出窗口 PNG。演示链路指向本机一次性 SFTP 服务端
// （tool/dev_sftp_server.py，仅绑定 127.0.0.1，账号 smoke/smoke）。
//
// 运行：先起本地服务端，再执行
//   flutter test integration_test/screenshots_test.dart -d macos
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

import 'package:no_shell/main.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/ssh/terminal_view.dart';
import 'package:no_shell/store.dart';

import '../test/support/credential_store_fake.dart';
import '../test/support/host_key_store_fake.dart';

/// 英文示例数据：截图界面与数据全部英文化，避免与应用中文种子混排。
final List<SshServer> demoSeed = [
  SshServer(
    id: 'srv-01',
    group: 'Production',
    name: 'web-prod-01',
    host: '10.0.1.11',
    username: 'deploy',
    tags: const ['nginx', 'web'],
    notes: 'Front-end load balancer. Changes require approval.',
  ),
  const SshServer(
    id: 'srv-02',
    group: 'Production',
    name: 'web-prod-02',
    host: '10.0.1.12',
    username: 'deploy',
    tags: ['nginx', 'web'],
  ),
  const SshServer(
    id: 'srv-03',
    group: 'Production',
    name: 'api-gateway',
    host: '10.0.1.20',
    port: 2222,
    username: 'ops',
    authMethod: AuthMethod.password,
    tags: ['gateway', 'api'],
  ),
  const SshServer(
    id: 'srv-04',
    group: 'Development',
    name: 'db-primary',
    host: '10.0.2.31',
    username: 'root',
    tags: ['postgres'],
  ),
  const SshServer(
    id: 'srv-05',
    group: 'Development',
    name: 'redis-cache',
    host: '10.0.2.32',
    username: 'root',
  ),
  const SshServer(
    id: 'srv-06',
    group: 'Development',
    name: 'ci-runner',
    host: '10.0.2.40',
    username: 'ci',
    tags: ['jenkins'],
  ),
  const SshServer(
    id: 'srv-07',
    group: 'Personal',
    name: 'nas-home',
    host: '192.168.1.10',
    username: 'admin',
    tags: ['nas', 'home'],
  ),
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  // README 截图面向桌面宽屏（1280 宽的分栏、侧边栏流程）；
  // 移动端布局流程不同，由 mobile_connect_test.dart 单独覆盖。
  final isDesktop =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);
  if (!isDesktop) {
    test('README 截图仅在桌面端生成（移动端见 mobile_connect_test）', () {
      markTestSkipped('README 截图只在桌面平台生成');
    });
    return;
  }

  testWidgets('生成 README 截图', (tester) async {
    // README 以英文为主文档，截图统一钉英文界面。
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    // 桌面端固定截图窗口尺寸；移动端没有 window_manager 实现，
    // 且模拟器屏幕本身就是目标截图尺寸，无需设置。
    if (isDesktop) {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1280, 820));
    }

    // macOS 应用进程被沙盒重定向了工作目录，输出目录用环境变量显式指定。
    // 移动端应用沙盒只写临时目录，模拟器跑测试时截图不进仓库。
    final shotsDir = Platform.environment['SSH_SHOTS_DIR'] ??
        (isDesktop
            ? 'docs/screenshots'
            : Directory.systemTemp.createTempSync().path);
    Directory(shotsDir).createSync(recursive: true);
    final shotKey = GlobalKey();
    final store = ServerStore(seed: demoSeed);

    await tester.pumpWidget(
      RepaintBoundary(
        key: shotKey,
        child: NoShellApp(
          store: store,
          credentials: FakeCredentialStore(),
          hostKeys: FakeHostKeyStore(),
        ),
      ),
    );

    // 终端光标持续闪烁，不能用 pumpAndSettle，一律定长推进。
    Future<void> settle([int ms = 400]) =>
        tester.pump(Duration(milliseconds: ms));

    Future<void> shot(String name) async {
      await settle();
      final boundary =
          shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$shotsDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    }

    // 1. 桌面主界面：选中 web-prod-01 的概览详情。
    await tester.tap(find.text('web-prod-01'));
    await settle();
    await shot('01-desktop-overview');

    // 2. 新建连接对话框：本机演示服务端。
    await tester.tap(find.byIcon(Icons.add_rounded));
    await settle(600);
    final dialogFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(dialogFields.at(0), 'demo-server');
    await tester.enterText(dialogFields.at(1), '127.0.0.1');
    await tester.enterText(dialogFields.at(2), '2222');
    await tester.enterText(dialogFields.at(3), 'smoke');
    await tester.tap(find.text('Password').last);
    await settle();
    await shot('02-new-connection');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(600);

    // 3. 连接：凭据弹窗（密码打点显示，不勾选记住凭据）。
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await settle(600);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'smoke',
    );
    await settle();
    await shot('03-credentials');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Connect'),
      ),
    );

    // 4. 终端：切到终端 Tab，等真实连接建立后整理出干净的演示提示符。
    await settle(600);
    await tester.tap(find.text('Terminal'));
    await settle();
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        if (find.text('Disconnect').evaluate().isNotEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      await shot('debug-connect-state');
      fail('30s 内未连接上本地演示服务端');
    });
    await settle();
    final session = tester
        .widget<SshTerminalView>(find.byType(SshTerminalView))
        .session;
    // 演示 shell（tool 同款一次性服务端）：清屏 + 列目录，固定 demo 提示符。
    session.terminal.onOutput?.call('clear\r');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    session.terminal.onOutput?.call('ls -la\r');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await shot('04-terminal');

    // 5. SFTP：进入 Tab 等目录列表渲染完成。
    await tester.tap(find.text('SFTP'));
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(deadline)) {
        if (find.text('hello.txt').evaluate().isNotEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      fail('20s 内未列出演示目录');
    });
    await settle();
    await shot('05-sftp');

    // 6. 设置对话框。
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await settle(600);
    await shot('06-settings');

    // 7. 深色主题：设置内主题分段切到 Dark（即时生效），关闭后截主界面。
    await tester.tap(find.text('Dark'));
    await settle(600);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await settle(600);
    await shot('07-dark');

    // 8. 窄约束 → 移动端底部导航骨架。
    // macOS 原生窗口有最小宽度限制，直接改窗口尺寸到 430 会被拒绝；
    // 改为在窄 SizedBox 约束下重新挂载应用（数据层重新播种为示例数据）。
    await tester.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 430,
          height: 930,
          child: RepaintBoundary(
            key: shotKey,
            child: NoShellApp(
              store: store,
              credentials: FakeCredentialStore(),
              hostKeys: FakeHostKeyStore(),
            ),
          ),
        ),
      ),
    );
    await settle(800);
    await shot('08-mobile');
  });
}
