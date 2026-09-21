// 移动端真实链路自测：在 iPhone 模拟器（或任意移动布局）上驱动真实应用，
// 完成 连接 → 终端输出 → SFTP 列目录 → 断开 的全流程。
// 依赖 tool/dev_sftp_server.py（127.0.0.1:2222，账号 smoke/smoke）先在本机跑起来：
//
//   /tmp/sftp-venv/bin/python tool/dev_sftp_server.py /tmp/noshell-smoke-root 2222
//   flutter test integration_test/mobile_connect_test.dart -d <模拟器或设备>
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:no_shell/main.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/settings.dart';
import 'package:no_shell/store.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_key_bar.dart';
import 'package:no_shell/ssh/terminal_view.dart';
import 'package:xterm/ui.dart';

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

  testWidgets(
    '移动端真实连接：终端输出与 SFTP 列目录',
    timeout: const Timeout(Duration(minutes: 3)),
    (tester) async {
      // 前置是本地一次性服务端（tool/dev_sftp_server.py，默认 2222）：
      // 没起就跳过——否则本机跑一遍集成测试要先干等 30 秒再收一盏红灯。
      if (!await _portOpen('127.0.0.1', 2222)) {
        markTestSkipped('127.0.0.1:2222 没有演示服务端，跳过移动端真实链路');
        return;
      }
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
      Finder detailTab(String label) =>
          find.descendant(of: find.byType(TabBar), matching: find.text(label));

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

      // ---- 移动端手势与键条 ----
      //
      // 这一段只验本机就能判定的东西（键条接线、菜单、手柄、查找、捏合），
      // 不依赖远端行为：手机上的软键盘、外接指针、真机触摸采样这些，
      // 只有真跑一次才知道，也正是这里唯一能覆盖它们的场合。
      //
      // **只在触屏平台上跑**：本测试也允许在 macOS 桌面上跑（见文件头的
      // 「任意移动布局」），而键条与选区手柄本来就只在 iOS / Android 挂载，
      // 桌面端不该因此变红。
      final touchPlatform =
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android;
      if (!touchPlatform) {
        debugPrint('非触屏平台：跳过键条 / 手柄 / 捏合这一段');
      }
      if (touchPlatform) {
        final scope = TerminalStyleScope.of(
          tester.element(find.byType(SshTerminalView)),
        );
        expect(
          find.byType(TerminalKeyBar),
          findsOneWidget,
          reason: '触屏平台应当挂上快捷键条',
        );

        // 粘滞 Ctrl：点一下进入待命，再点一下取消（读的是会话自己的状态，
        // 不依赖远端回显什么）。
        Finder barKey(String label) => find.descendant(
          of: find.byType(TerminalKeyBar),
          matching: find.text(label),
        );
        await tester.tap(barKey('ctrl'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(session.inputModifiers.ctrl, isTrue, reason: 'ctrl 该进入待命');
        await tester.tap(barKey('ctrl'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(session.inputModifiers.ctrl, isFalse, reason: '再点该取消');

        // 字号键：窄屏上它在键条的可滚动区里，先滚到可见再点。
        final barScroll = find.descendant(
          of: find.byType(TerminalKeyBar),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          barKey('A+'),
          60,
          scrollable: barScroll,
        );
        await tester.pump(const Duration(milliseconds: 200));
        final fontBefore = scope.notifier.value.fontSize;
        await tester.tap(barKey('A+'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          scope.notifier.value.fontSize,
          fontBefore + 1,
          reason: '键条上的 A+ 该改全局字号',
        );
        await tester.tap(barKey('A-'));
        await tester.pump(const Duration(milliseconds: 300));

        // 长按终端：弹「复制 / 粘贴 / 全选」，全选后出现首尾手柄。
        final terminalCenter = tester.getCenter(find.byType(TerminalView));
        await tester.longPressAt(terminalCenter);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Select All'), findsOneWidget, reason: '长按该弹出终端菜单');
        await tester.tap(find.text('Select All'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.byKey(const ValueKey('selection-handle-end')),
          findsOneWidget,
          reason: '触屏上选中之后应当出现选区手柄',
        );

        // 查找：工具栏放大镜 → 查找栏 → 命中高亮。
        await tester.tap(find.byIcon(Icons.search_rounded).first);
        await tester.pump(const Duration(milliseconds: 300));
        final searchField = find.descendant(
          of: find.byType(SshTerminalView),
          matching: find.byType(TextField),
        );
        expect(searchField, findsOneWidget, reason: '工具栏放大镜该展开查找栏');
        await tester.enterText(searchField, 'demo');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          tester
              .widget<TerminalView>(find.byType(TerminalView))
              .controller!
              .highlights,
          isNotEmpty,
          reason: '在回滚里查到 demo，应当有命中高亮',
        );
        await tester.tap(
          find.descendant(
            of: find.byType(SshTerminalView),
            matching: find.byIcon(Icons.close_rounded),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // 双指捏合：手势期间只出预览，抬手才改字号。
        final pinchBefore = scope.notifier.value.fontSize;
        final left = await tester.startGesture(
          terminalCenter - const Offset(30, 0),
        );
        await tester.pump(const Duration(milliseconds: 80));
        final right = await tester.startGesture(
          terminalCenter + const Offset(30, 0),
        );
        await tester.pump(const Duration(milliseconds: 80));
        await left.moveTo(terminalCenter - const Offset(85, 0));
        await right.moveTo(terminalCenter + const Offset(85, 0));
        await tester.pump(const Duration(milliseconds: 120));
        expect(
          scope.notifier.value.fontSize,
          pinchBefore,
          reason: '捏合期间只该出预览，不写偏好',
        );
        await left.up();
        await right.up();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          scope.notifier.value.fontSize,
          greaterThan(pinchBefore),
          reason: '抬手之后字号该落定',
        );

        // 字号改过之后复原，别把后面的步骤带上（这里只是自测，不落盘也行）。
        await tester.tap(barKey('A-'));
        await tester.pump(const Duration(milliseconds: 200));
      } // touchPlatform

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
    },
  );
}

/// 本机端口上有没有人监听（用来判断演示服务端在不在）。
Future<bool> _portOpen(String host, int port) async {
  try {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 1),
    );
    socket.destroy();
    return true;
  } on Object {
    return false;
  }
}
