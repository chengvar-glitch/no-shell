// 移动端真实链路自测：在 iPhone 模拟器（或任意移动布局）上驱动真实应用，
// 完成 连接 → 终端输出 → SFTP 列目录 → 断开 的全流程。
// 依赖 tool/dev_sftp_server.py（127.0.0.1:2222，账号 smoke/smoke）先在本机跑起来：
//
//   /tmp/sftp-venv/bin/python tool/dev_sftp_server.py /tmp/noshell-smoke-root 2222
//   flutter test integration_test/mobile_connect_test.dart -d <模拟器或设备>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:no_shell/main.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/store.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_view.dart';

import '../test/support/credential_store_fake.dart';
import '../test/support/host_key_store_fake.dart';

/// 终端缓冲区的全部文本（供包含性断言）。
String terminalText(dynamic terminal) {
  final lines = terminal.buffer.lines as dynamic;
  final buffer = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    buffer.writeln((lines[i] as dynamic).getText());
  }
  return buffer.toString();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('移动端真实连接：终端输出与 SFTP 列目录', (tester) async {
    // 与 README 截图同一策略：钉英文界面，finder 文案确定。
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    // 固定窄视口：任何平台（含 macOS 桌面）都走移动端骨架，便于调试。
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = ServerStore(
      seed: const [
        SshServer(
          id: 'srv-e2e',
          group: 'Local',
          name: 'demo-ssh',
          host: '127.0.0.1',
          port: 2222,
          username: 'smoke',
          authMethod: AuthMethod.password,
        ),
      ],
    );
    // 预存密码：点连接直接走真实链路，不弹凭据对话框。
    final credentials = FakeCredentialStore()
      ..write('srv-e2e', const SshCredentials(password: 'smoke'));

    await tester.pumpWidget(
      NoShellApp(
        store: store,
        credentials: credentials,
        hostKeys: FakeHostKeyStore(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // 进入详情页并连接；终端光标会闪，一律定长推进，不用 pumpAndSettle。
    await tester.tap(find.text('demo-ssh'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byIcon(Icons.bolt_rounded));

    // 等真实连接建立：底部按钮从「Connect now」翻转为「Disconnect」。
    // 注意 hasActive 含 connecting 阶段，此按钮出现不代表握手已完成。
    var connecting = false;
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      if (find.text('Disconnect').evaluate().isNotEmpty) {
        connecting = true;
        break;
      }
    }
    expect(connecting, isTrue, reason: '30s 内未开始连接本地演示服务端');

    // 详情页的 Tab 标签必须限定在 TabBar 里找：底部导航在底层路由里
    // 也有同名的「Terminal」，无范围限定会点到被遮住的坐标上。
    Finder detailTab(String label) => find.descendant(
      of: find.byType(TabBar),
      matching: find.text(label),
    );

    // 等终端视图就绪并真正连上（缓冲区出现演示提示符）。
    await tester.tap(detailTab('Terminal'));
    var sessionReady = false;
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final candidates = find.byType(SshTerminalView);
      if (candidates.evaluate().isNotEmpty) {
        final session = tester.widget<SshTerminalView>(candidates).session;
        if (terminalText(session.terminal).contains('demo@localhost')) {
          sessionReady = true;
          break;
        }
      }
    }
    expect(sessionReady, isTrue, reason: '30s 内终端未收到演示提示符');

    // 跑一条 ls，等 PTY 输出落进缓冲区。
    final session = tester
        .widget<SshTerminalView>(find.byType(SshTerminalView))
        .session;
    session.terminal.onOutput?.call('ls -la\n');
    var lsEchoed = false;
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump(const Duration(milliseconds: 250));
      if (terminalText(session.terminal).contains('hello.txt')) {
        lsEchoed = true;
        break;
      }
    }
    expect(lsEchoed, isTrue, reason: '10s 内终端未收到 ls 输出');
    // SFTP Tab：复用同一 SSH 连接的通道列出目录。
    await tester.tap(detailTab('SFTP'));
    var listed = false;
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      if (find.text('hello.txt').evaluate().isNotEmpty) {
        listed = true;
        break;
      }
    }
    expect(listed, isTrue, reason: '20s 内 SFTP 未列出演示目录');

    // 断开：会话结束、主机回到未连接，按钮翻回「Connect now」。
    await tester.tap(find.text('Disconnect'));
    var closed = false;
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump(const Duration(milliseconds: 250));
      if (find.text('Connect now').evaluate().isNotEmpty) {
        closed = true;
        break;
      }
    }
    expect(closed, isTrue, reason: '断开后未回到未连接状态');
    expect(store.byId('srv-e2e')?.status, ServerStatus.idle);
  });
}
