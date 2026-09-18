// 临时真机链路验证：在 iOS 模拟器中驱动真实应用，经真实 UI 流程
// （列表行连接按钮 → 凭据弹窗 → 终端 Tab）连接一台真实 SSH 服务器。
// 凭据一律经 --dart-define 注入（模拟器进程不继承宿主环境变量），
// 值只进构建产物，不写入代码：
//   --dart-define=REAL_SSH_HOST=... REAL_SSH_PORT REAL_SSH_USER
//   REAL_SSH_PASS REAL_SSH_NAME（列表展示名，默认 target）
// 运行：
//   flutter test integration_test/real_connect_test.dart -d <simulator> \
//     --dart-define=REAL_SSH_HOST=8.x.x.x --dart-define=REAL_SSH_PASS=...
// 截图输出到 REAL_SHOTS_DIR（默认 /tmp/noshell_ios_real），禁止提交含真实主机信息的截图。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:no_shell/main.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/ssh/terminal_view.dart';
import 'package:no_shell/store.dart';

import '../test/support/credential_store_fake.dart';
import '../test/support/host_key_store_fake.dart';

// --dart-define 注入点（String.fromEnvironment 要求常量键名，只能逐个声明）。
const _kDefineHost = String.fromEnvironment('REAL_SSH_HOST');
const _kDefinePort = String.fromEnvironment('REAL_SSH_PORT');
const _kDefineUser = String.fromEnvironment('REAL_SSH_USER');
const _kDefinePass = String.fromEnvironment('REAL_SSH_PASS');
const _kDefineName = String.fromEnvironment('REAL_SSH_NAME');
const _kDefineShots = String.fromEnvironment('REAL_SHOTS_DIR');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('模拟器内连接真实服务器', timeout: const Timeout(Duration(minutes: 3)), (tester) async {
    // 模拟器进程不继承宿主环境变量，define 优先；macOS 直跑可退回环境变量。
    String pick({required String define, required String envKey}) =>
        define.isNotEmpty ? define : Platform.environment[envKey] ?? '';

    final host = pick(define: _kDefineHost, envKey: 'REAL_SSH_HOST');
    final port =
        int.tryParse(pick(define: _kDefinePort, envKey: 'REAL_SSH_PORT')) ?? 22;
    final user = pick(define: _kDefineUser, envKey: 'REAL_SSH_USER');
    final pass = pick(define: _kDefinePass, envKey: 'REAL_SSH_PASS');
    final name = pick(define: _kDefineName, envKey: 'REAL_SSH_NAME').isNotEmpty
        ? pick(define: _kDefineName, envKey: 'REAL_SSH_NAME')
        : 'target';
    // 缺前置一律跳过（而不是 fail）：这条要真机 + 真凭据，别人顺手把它
    // 加进 CI 时应当安静跳过，不该变成一盏红灯。
    final missing = [
      if (host.isEmpty) 'REAL_SSH_HOST',
      if (user.isEmpty) 'REAL_SSH_USER',
      if (pass.isEmpty) 'REAL_SSH_PASS',
    ];
    if (missing.isNotEmpty) {
      markTestSkipped('缺少 ${missing.join(' / ')}，跳过真实主机连接验证');
      return;
    }
    final shotsDir = _kDefineShots.isNotEmpty
        ? _kDefineShots
        : Platform.environment['REAL_SHOTS_DIR'] ?? '/tmp/noshell_ios_real';
    Directory(shotsDir).createSync(recursive: true);

    // 与 README 截图生成器保持一致：钉英文界面，查找器用英文文案。
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    final shotKey = GlobalKey();
    final store = ServerStore(
      seed: [
        SshServer(
          id: 'target',
          group: 'Real',
          name: name,
          host: host,
          port: port,
          username: user,
          authMethod: AuthMethod.password,
        ),
      ],
    );

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
    Future<void> settle([int ms = 400]) =>
        tester.pump(Duration(milliseconds: ms));

    Future<void> shot(String file) async {
      await settle();
      final boundary =
          shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$shotsDir/$file.png').writeAsBytesSync(data!.buffer.asUint8List());
    }

    // 1. 服务器列表：目标主机已在列表中。
    await settle(600);
    await shot('01-host-list');

    // 2. 行尾连接按钮 → 凭据弹窗，输入密码（打点显示）。
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await settle(600);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      pass,
    );
    await settle();
    await shot('02-credentials');

    // 3. 提交凭据开始连接，切到终端 Tab。
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Connect'),
      ),
    );
    await settle(600);
    await tester.tap(find.text('Terminal'));
    await settle(600);

    // 4. 等会话瓦片出现，点进去等真实连接建立（真实网络，放宽到 45s）。
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (DateTime.now().isBefore(deadline)) {
        if (find.text(name).evaluate().isNotEmpty) return;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      fail('15s 内终端 Tab 未出现会话');
    });
    await tester.tap(find.text(name));
    await settle(400);

    final failure = await tester.runAsync<String?>(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (DateTime.now().isBefore(deadline)) {
        final views = tester
            .widgetList<SshTerminalView>(find.byType(SshTerminalView))
            .toList();
        if (views.isNotEmpty) {
          final session = views.first.session;
          if (session.phase == TerminalPhase.connected) return null;
          if (session.phase == TerminalPhase.failed) {
            return '${session.errorKind}: ${session.error}';
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      return '45s 内未进入 connected 状态';
    });
    await shot('debug-connect-state');
    if (failure != null) fail(failure);

    // 5. 已连上：跑两条真实命令让终端有实际输出，再截图。
    final session = tester
        .widget<SshTerminalView>(find.byType(SshTerminalView))
        .session;
    session.terminal.onOutput?.call('whoami && uname -a && uptime\r');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1500)),
    );
    await shot('03-terminal-connected');
  });
}
