import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/ssh/port_forward_runtime.dart';
import 'package:no_shell/ssh/session_manager.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/store.dart';
import 'package:no_shell/theme.dart';
import 'package:no_shell/widgets/port_forward_panel.dart';

import 'support/forward_fakes.dart';

/// 一台带两条规则的主机；规则由 store 持有，面板只是读写它。
SshServer _server({List<PortForwardRule> forwards = const []}) => SshServer(
  id: 'srv-1',
  group: 'g',
  name: 'test-host',
  host: '10.0.0.1',
  username: 'root',
  authMethod: AuthMethod.password,
  forwards: forwards,
);

const _localRule = PortForwardRule(
  id: 'fwd-local',
  mode: PortForwardMode.local,
  localHost: '127.0.0.1',
  localPort: 8080,
  remoteHost: '10.0.0.5',
  remotePort: 80,
);

final class _Harness {
  late ServerStore store;
  late SessionManager sessions;
  late FakeForwardTransport transport;
  late FakeTunnelGateway gateway;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  List<PortForwardRule> forwards = const [],
  bool connect = false,
}) async {
  final harness = _Harness()
    ..store = ServerStore(seed: [_server(forwards: forwards)])
    ..transport = FakeForwardTransport()
    ..gateway = FakeTunnelGateway();
  harness.sessions = SessionManager(
    store: harness.store,
    sessionFactory: (server, credentials, jumps) => TerminalSession(
      server: server,
      credentials: credentials,
      transport: harness.transport,
      tunnelGateway: harness.gateway,
    ),
  );
  if (connect) {
    harness.sessions.open(
      harness.store.servers.single,
      const SshCredentials(password: 'pw'),
    );
    // 会话建立是异步的（attach → onConnected）。
    await tester.pump();
    await tester.pump();
  }

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      theme: AppTheme.light(),
      home: Scaffold(
        body: PortForwardPanel(
          server: harness.store.servers.single,
          store: harness.store,
          sessions: harness.sessions,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  testWidgets('没有规则时是空态，新建一条后写进 store', (tester) async {
    final harness = await _pump(tester);

    expect(find.text('还没有转发规则'), findsOneWidget);
    await tester.tap(find.text('新建转发'));
    await tester.pumpAndSettle();

    // 弹窗默认本地转发，地址预填回环；端口需要用户填。
    expect(find.text('本地转发 (-L)'), findsOneWidget);
    final ports = find.byType(TextFormField);
    await tester.enterText(ports.at(1), '8080');
    await tester.enterText(ports.at(3), '80');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = harness.store.servers.single.forwards;
    expect(saved, hasLength(1));
    expect(saved.single.mode, PortForwardMode.local);
    expect(saved.single.localPort, 8080);
    expect(saved.single.remotePort, 80);
    expect(saved.single.isRunnable, isTrue);
    // 规则落到了列表上，空态消失。
    expect(find.text('还没有转发规则'), findsNothing);
    expect(find.textContaining('127.0.0.1:8080'), findsOneWidget);
  });

  testWidgets('端口填得不合法时拦在弹窗里，不落库', (tester) async {
    final harness = await _pump(tester);
    await tester.tap(find.text('新建转发'));
    await tester.pumpAndSettle();

    final ports = find.byType(TextFormField);
    await tester.enterText(ports.at(1), '70000');
    await tester.enterText(ports.at(3), '80');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('1-65535'), findsOneWidget);
    expect(harness.store.servers.single.forwards, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets('会话未建立时开关禁用，并提示先连接', (tester) async {
    await _pump(tester, forwards: [_localRule]);

    expect(find.textContaining('会话未建立'), findsOneWidget);
    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.onChanged, isNull);
    expect(toggle.value, isFalse);
  });

  testWidgets('会话建立后打开开关就真的起转发，状态变成运行中', (tester) async {
    final harness = await _pump(tester, forwards: [_localRule], connect: true);

    expect(
      harness.sessions.byServerId('srv-1')!.phase,
      TerminalPhase.connected,
      reason: '会话应当已经连上',
    );
    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.onChanged, isNotNull, reason: '会话在跑时开关必须可点');

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final status = harness.sessions
        .byServerId('srv-1')!
        .forwards
        .statusOf('fwd-local');
    expect(status.phase, PortForwardPhase.running);
    expect(harness.gateway.listenerFor('127.0.0.1', 8080), isNotNull);
    expect(find.text('运行中'), findsOneWidget);

    // 再点一次停掉：监听关掉，状态回到未启动。
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(harness.gateway.listenerFor('127.0.0.1', 8080)!.closed, isTrue);
    expect(find.text('未启动'), findsOneWidget);
  });

  testWidgets('启动失败时行内显示原因', (tester) async {
    final harness = await _pump(tester, forwards: [_localRule], connect: true);
    harness.gateway.listenError = UnsupportedError('no raw TCP');

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('启动失败'), findsOneWidget);
    expect(find.textContaining('当前平台不支持端口转发'), findsOneWidget);
  });

  testWidgets('编辑保留规则 id，删除先停掉再移除', (tester) async {
    final harness = await _pump(tester, forwards: [_localRule], connect: true);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    final ports = find.byType(TextFormField);
    await tester.enterText(ports.at(3), '8081');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final edited = harness.store.servers.single.forwards.single;
    // id 不变：编辑是覆盖，不是「删一条再加一条」（否则运行中的那条会失联）。
    expect(edited.id, 'fwd-local');
    expect(edited.remotePort, 8081);

    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除这条转发？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(harness.store.servers.single.forwards, isEmpty);
    // 规则被删掉时运行中的监听必须一起关掉，不留没人管的隧道。
    expect(harness.gateway.listenerFor('127.0.0.1', 8080)!.closed, isTrue);
  });

  testWidgets('动态转发的弹窗不出现目标地址字段', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('新建转发'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('动态转发 (-D)'));
    await tester.pumpAndSettle();

    expect(find.text('监听地址'), findsOneWidget);
    expect(find.text('目标地址'), findsNothing);
    expect(find.textContaining('SOCKS5'), findsWidgets);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
}
