import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/theme.dart';
import 'package:no_shell/widgets/overview_metrics.dart';
import 'package:no_shell/widgets/tab_visibility.dart';

import 'support/demo_servers.dart';
import 'support/transport_fakes.dart';

/// 一段完整的 Linux 采集输出：概览负载分区的四张卡片都能画出来。
const String _metricsOutput = '''
@@hostname
web-prod-01
@@os
Linux
@@kernel
6.8.0-45-generic
@@arch
x86_64
@@kind
linux
@@load
0.52 0.58 0.59 1/523 45678
@@uptime
123456.78 987654.32
@@cpu
cpu 100 0 0 900 0 0 0 0 0 0
@@cores
8
@@mem
MemTotal: 1048576 kB
MemAvailable: 262144 kB
@@net
eth0: 1000 0 0 0 0 0 0 0 2000 0 0 0 0 0 0 0
@@df
Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/sda1 1000000 250000 750000 25% /
''';

final _server = demoServers.first;

Future<TerminalSession> _connect(
  WidgetTester tester,
  FakeTransport transport,
) async {
  final session = TerminalSession(
    server: _server,
    credentials: const SshCredentials(password: 'pw'),
    transport: transport,
  );
  session.start();
  await tester.pump();
  await tester.pump();
  expect(session.phase, TerminalPhase.connected);
  return session;
}

Future<void> _pumpSection(
  WidgetTester tester, {
  required TerminalSession? session,
  bool visible = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: TabVisibilityScope(
            visible: visible,
            child: ServerLoadSection(server: _server, session: session),
          ),
        ),
      ),
    ),
  );
  // 采样是「启动 → 定时器 → 命令完成 → 通知重建」的异步链。零延迟的
  // 启动定时器只有在 elapse 里才会跑，所以先给 1ms 再补一帧。
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump();
}

Future<void> _disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets('未连接时只给连接提示，不发任何远端命令', (tester) async {
    final transport = FakeTransport(commandResult: _metricsOutput);
    await _pumpSection(tester, session: null);

    expect(find.text('服务器负载'), findsOneWidget);
    expect(find.text('连接主机后可查看 CPU、内存、磁盘与网络负载。'), findsOneWidget);
    expect(find.text('主机名'), findsNothing);
    expect(transport.commands, isEmpty);
  });

  testWidgets('已连接时采样并渲染系统信息与四张指标卡', (tester) async {
    final transport = FakeTransport(commandResult: _metricsOutput);
    final session = await _connect(tester, transport);
    await _pumpSection(tester, session: session);

    expect(transport.commands, isNotEmpty);
    // 系统信息卡：主机名来自远端采集（不是本机配置里的地址）。
    expect(find.text('主机名'), findsOneWidget);
    expect(find.text('web-prod-01'), findsOneWidget);
    expect(find.text('Linux 6.8.0-45-generic'), findsOneWidget);
    // 四张指标卡的标题。
    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('内存'), findsOneWidget);
    expect(find.text('磁盘'), findsOneWidget);
    expect(find.text('网络'), findsOneWidget);
    // 首帧没有差分基准，CPU 显示占位；内存 / 磁盘是立即可用的百分比。
    expect(find.text('75%'), findsOneWidget);
    // 磁盘百分比同时出现在卡片数值与环形图中心。
    expect(find.text('25%'), findsWidgets);
    expect(find.text('8 核'), findsOneWidget);

    await _disposeTree(tester);
    session.dispose();
  });

  testWidgets('远端没有指标能力时显示「不支持」且不再重试', (tester) async {
    final transport = FakeTransport();
    final session = await _connect(tester, transport);
    await _pumpSection(tester, session: session);

    // 分区标题旁的状态与说明面板各一处。
    expect(find.text('该主机不提供系统指标。'), findsWidgets);
    expect(find.text('主机名'), findsNothing);
    expect(transport.commands, hasLength(1));

    // 等过一个采样周期，没有新的命令发出去。
    await tester.pump(const Duration(seconds: 10));
    expect(transport.commands, hasLength(1));

    await _disposeTree(tester);
    session.dispose();
  });

  testWidgets('Tab 不可见时不采样，重新可见后立刻补采', (tester) async {
    final transport = FakeTransport(commandResult: _metricsOutput);
    final session = await _connect(tester, transport);
    await _pumpSection(tester, session: session, visible: false);
    await tester.pump(const Duration(seconds: 6));
    expect(transport.commands, isEmpty);

    await _pumpSection(tester, session: session, visible: true);
    expect(transport.commands, hasLength(1));

    await _disposeTree(tester);
    session.dispose();
  });

  testWidgets('组件卸载后停止轮询，不再产生远端命令', (tester) async {
    final transport = FakeTransport(commandResult: _metricsOutput);
    final session = await _connect(tester, transport);
    await _pumpSection(tester, session: session);
    final calls = transport.commands.length;
    expect(calls, greaterThan(0));

    await _disposeTree(tester);
    await tester.pump(const Duration(seconds: 12));
    expect(transport.commands.length, calls);
    session.dispose();
  });
}
