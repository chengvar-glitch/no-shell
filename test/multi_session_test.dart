import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/settings.dart';
import 'package:no_shell/ssh/session_manager.dart';
import 'package:no_shell/ssh/sftp.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/ssh/terminal_view.dart';
import 'package:no_shell/store.dart';
import 'package:no_shell/theme.dart';
import 'package:no_shell/widgets/server_detail.dart';
import 'package:no_shell/widgets/sftp_browser.dart';
import 'package:xterm/core.dart';

import 'support/credential_store_fake.dart';
import 'support/forward_fakes.dart';

/// 桌面端同一主机多开会话的界面行为：
/// 单会话时界面与多开功能之前完全一样（胶囊点开是会话日志、没有 ⊕），
/// 多开了才多出计数、会话菜单与切换。
const _server = SshServer(
  id: 'srv-multi',
  group: 'g',
  name: 'multi-test',
  host: '10.0.0.9',
  username: 'root',
);

/// 连上后把 [banner] 写进终端，便于按会话区分画面 / 日志内容。
final class _FakeTransport with NoForwardingTransport {
  _FakeTransport({this.banner = 'welcome'});

  final String banner;

  bool disposed = false;

  @override
  Future<void> attach(
    Terminal terminal, {
    required void Function() onConnected,
    required void Function() onClosed,
  }) async {
    await Future<void>.delayed(Duration.zero);
    terminal.write(banner);
    onConnected();
  }

  @override
  Future<SftpFileSystem> openSftp() async =>
      throw const SftpException(SftpErrorKind.unsupported, 'fake transport');

  @override
  void dispose() => disposed = true;
}

Widget _host(Widget child) {
  final style = ValueNotifier(const TerminalStylePrefs());
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: AppTheme.light(),
    home: Scaffold(body: child),
    // 与正式入口一致：终端样式作用域包住 Navigator，弹窗路由也读得到。
    builder: (context, navigator) => TerminalStyleScope(
      notifier: style,
      child: navigator ?? const SizedBox.shrink(),
    ),
  );
}

/// 推进两帧：一帧让假传输的握手回调落地，一帧让界面跟着重建。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  late ServerStore store;
  late SessionManager sessions;
  late List<_FakeTransport> transports;
  late FakeCredentialStore credentials;

  setUp(() {
    store = ServerStore(seed: [_server]);
    credentials = FakeCredentialStore();
    transports = [];
    sessions = SessionManager(
      store: store,
      sessionFactory: (server, creds, jumps) {
        final transport = _FakeTransport(
          banner: 'banner-${transports.length + 1}',
        );
        transports.add(transport);
        return TerminalSession(
          server: server,
          credentials: creds,
          transport: transport,
        );
      },
    );
  });

  tearDown(() {
    sessions.dispose();
    store.dispose();
  });

  /// 与 HomePage 同一套接线：主机实例取自 store（状态回写才看得见），
  /// 面板自身订阅会话注册表（见 _ServerDetailState）。
  Widget panel() => ListenableBuilder(
    listenable: store,
    builder: (context, _) => ServerDetailPanel(
      server: store.byId(_server.id),
      store: store,
      sessions: sessions,
      credentials: credentials,
      onConnect: (_) {},
      onCreate: () {},
    ),
  );

  Future<void> connectFirst(WidgetTester tester) async {
    sessions.open(_server, const SshCredentials(password: 'pw'));
    await _settle(tester);
  }

  testWidgets('单会话：胶囊不带计数、没有 ⊕，点开仍是会话日志', (tester) async {
    await tester.pumpWidget(_host(panel()));
    await tester.pump();

    // 还没有会话：胶囊退化成灰点提示，⊕ 不出现。
    expect(find.byTooltip('新建会话'), findsNothing);

    await connectFirst(tester);

    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('已连接 · 2'), findsNothing);
    expect(find.byTooltip('新建会话'), findsOneWidget);

    await tester.tap(find.byTooltip('会话日志'));
    await tester.pumpAndSettle();
    // 单会话点胶囊进的还是日志（内容即该会话的画面前缀）。
    expect(find.text('banner-1'), findsOneWidget);
  });

  testWidgets('多会话：胶囊带计数，点开是会话菜单，切换后终端换成那一条', (tester) async {
    await tester.pumpWidget(_host(panel()));
    await connectFirst(tester);
    final first = sessions.activeOf(_server.id)!;
    sessions.openNew(_server, const SshCredentials(password: 'pw'));
    await _settle(tester);
    final second = sessions.activeOf(_server.id)!;

    expect(find.text('已连接 · 2'), findsOneWidget);
    // 当前会话是刚开的那条，终端视图也挂在它身上。
    expect(
      tester.widget<SshTerminalView>(find.byType(SshTerminalView)).session,
      same(second),
    );

    // 点胶囊弹出会话菜单（此时不再直接进日志）。
    await tester.tap(find.byTooltip('会话'));
    await tester.pumpAndSettle();
    expect(find.text('会话 1'), findsOneWidget);
    expect(find.text('会话 2'), findsOneWidget);

    await tester.tap(find.text('会话 1'));
    await tester.pumpAndSettle();

    expect(identical(sessions.activeOf(_server.id), first), isTrue);
    expect(
      tester.widget<SshTerminalView>(find.byType(SshTerminalView)).session,
      same(first),
    );
    // 终端视图按会话换了 key：xterm 的 TerminalView 不处理 terminal 更换，
    // 不换 key 就会继续画旧缓冲区。
    expect(find.byKey(ObjectKey(first)), findsOneWidget);

    // SFTP 面板也绑在切换后的那条会话上。
    expect(tester.widget<SftpTab>(find.byType(SftpTab)).session, same(first));
  });

  testWidgets('菜单里能看到远端标题，切换回合并关掉一条', (tester) async {
    await tester.pumpWidget(_host(panel()));
    await connectFirst(tester);
    final first = sessions.activeOf(_server.id)!;
    sessions.openNew(_server, const SshCredentials(password: 'pw'));
    await _settle(tester);
    final second = sessions.activeOf(_server.id)!;

    first.terminal.setTitle('root@web1: /var/log');
    await _settle(tester);

    await tester.tap(find.byTooltip('会话'));
    await tester.pumpAndSettle();
    expect(find.text('root@web1: /var/log'), findsOneWidget);

    // 行尾 × 关掉这一条：菜单收起、会话被移除、另一条不受影响。
    await tester.tap(find.byTooltip('关闭会话').first);
    await tester.pumpAndSettle();

    expect(sessions.sessionCount, 1);
    expect(identical(sessions.activeOf(_server.id), second), isTrue);
    expect(transports.first.disposed, isTrue);
  });

  testWidgets('⊕ 与菜单都能再开一条：复用现有会话手头的凭据，不弹凭据框', (tester) async {
    await tester.pumpWidget(_host(panel()));
    await connectFirst(tester);

    await tester.tap(find.byTooltip('新建会话'));
    await _settle(tester);

    expect(sessions.sessionCount, 2);
    expect(sessions.ordinalOf(sessions.activeOf(_server.id)!), 2);
    // 凭据框没出现（复用第一条会话内存里的密码，没走安全存储）。
    expect(find.text('连接「multi-test」'), findsNothing);
    expect(find.text('已连接 · 2'), findsOneWidget);
  });

  testWidgets('会话全失败时胶囊显示聚合状态与条数', (tester) async {
    await tester.pumpWidget(_host(panel()));
    sessions.open(_server, const SshCredentials(password: 'pw'));
    await _settle(tester);

    // 手动断开：会话留在菜单里，主机回到未连接。
    sessions.closeAll(_server.id);
    await _settle(tester);

    expect(find.text('已连接'), findsNothing);
    expect(find.byTooltip('新建会话'), findsNothing);
  });
}
