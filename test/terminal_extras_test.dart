import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/settings.dart';
import 'package:no_shell/snippets.dart';
import 'package:no_shell/ssh/auto_reconnect.dart';
import 'package:no_shell/ssh/session_manager.dart';
import 'package:no_shell/ssh/sftp.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/ssh/terminal_view.dart';
import 'package:no_shell/store.dart';
import 'package:no_shell/theme.dart';
import 'package:no_shell/widgets/server_detail.dart';
import 'package:xterm/core.dart';

import 'support/forward_fakes.dart';

const _server = SshServer(
  id: 'srv-ui',
  group: 'g',
  name: 'ui-test',
  host: '10.0.0.9',
  username: 'root',
);

/// 连接成功、可捕获「发往远端」内容、可模拟远端断开的假传输。
final class _ConnectedTransport with NoForwardingTransport {
  _ConnectedTransport({this.banner = 'banner\n'});

  /// 连上后立刻写进终端的远端输出；传空串即「还没输出过的会话」。
  final String banner;

  final sent = <String>[];

  void Function()? _onClosed;

  /// 模拟远端断开。
  void closeFromRemote() => _onClosed?.call();

  @override
  Future<void> attach(
    Terminal terminal, {
    required void Function() onConnected,
    required void Function() onClosed,
  }) async {
    _onClosed = onClosed;
    terminal.onOutput = sent.add;
    if (banner.isNotEmpty) terminal.write(banner);
    onConnected();
  }

  @override
  Future<SftpFileSystem> openSftp() async =>
      throw const SftpException(SftpErrorKind.unsupported, 'fake');

  @override
  void dispose() {}
}

Widget _host(Widget child, {SnippetStore? snippets}) {
  final style = ValueNotifier(const TerminalStylePrefs());
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: AppTheme.light(),
    home: Scaffold(body: child),
    // 与正式入口一致：作用域包住 Navigator，弹窗路由也能读到。
    builder: (context, navigator) {
      Widget scoped = TerminalStyleScope(
        notifier: style,
        child: navigator ?? const SizedBox.shrink(),
      );
      if (snippets != null) {
        scoped = SnippetScope(store: snippets, child: scoped);
      }
      return scoped;
    },
  );
}

Future<TerminalSession> _connectedSession(_ConnectedTransport transport) async {
  final session = TerminalSession(
    server: _server,
    credentials: const SshCredentials(password: 'pw'),
    transport: transport,
  );
  await session.start();
  return session;
}

void main() {
  group('SshTerminalView 会话工具条', () {
    testWidgets('展示片段入口，空态可打开可关闭', (tester) async {
      final transport = _ConnectedTransport();
      final session = await _connectedSession(transport);
      addTearDown(session.dispose);

      await tester.pumpWidget(
        _host(SshTerminalView(session: session), snippets: SnippetStore()),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('命令片段'));
      await tester.pumpAndSettle();
      // 没有片段：展示空态，入口本身已验证可用。
      expect(find.text('还没有命令片段'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('还没有命令片段'), findsNothing);
    });

    testWidgets('点按片段把命令连回车发往会话', (tester) async {
      final transport = _ConnectedTransport();
      final session = await _connectedSession(transport);
      addTearDown(session.dispose);

      final snippets = SnippetStore(
        seed: [CommandSnippet(id: 's1', name: '列目录', command: 'ls -la')],
      );
      await tester.pumpWidget(
        _host(SshTerminalView(session: session), snippets: snippets),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('命令片段'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('列目录'));
      await tester.pumpAndSettle();

      expect(transport.sent, ['ls -la\r']);
      // 发送完成弹窗收起。
      expect(find.text('命令片段'), findsNothing);
    });

    testWidgets('会话未连接时片段不可发送，弹窗退化为管理界面', (tester) async {
      final session = TerminalSession(
        server: _server,
        credentials: const SshCredentials(password: 'pw'),
        transport: _ConnectedTransport(),
      );
      addTearDown(session.dispose);
      // start 未被调用：永远停在 connecting。

      final snippets = SnippetStore(
        seed: [CommandSnippet(id: 's1', name: '列目录', command: 'ls -la')],
      );
      await tester.pumpWidget(
        _host(SshTerminalView(session: session), snippets: snippets),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('命令片段'));
      // 浮层里的连接指示器永不停止，不能用 pumpAndSettle，
      // 用两帧把弹窗过渡动画推完即可。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, '列目录'),
      );
      expect(tile.enabled, isFalse);
    });
  });

  group('会话日志入口（状态胶囊）', () {
    // 桌面详情面板：头部是「服务器名 + 状态胶囊 + 连接按钮」，
    // 会话由注入假传输的管理器建立，胶囊可点即代表入口已接通。
    Widget panel(ServerStore store, SessionManager manager) =>
        ServerDetailPanel(
          server: _server,
          store: store,
          sessions: manager,
          onConnect: (_) {},
          onCreate: () {},
        );

    SessionManager managerWith(
      ServerStore store,
      _ConnectedTransport transport, {
      required bool connect,
    }) {
      final manager = SessionManager(
        store: store,
        sessionFactory: (server, credentials, jumps) => TerminalSession(
          server: server,
          credentials: credentials,
          transport: transport,
        ),
      );
      if (connect) manager.open(_server, const SshCredentials(password: 'pw'));
      return manager;
    }

    testWidgets('点状态胶囊打开会话日志，内容与终端画面一致', (tester) async {
      final store = ServerStore(seed: [_server]);
      addTearDown(store.dispose);
      final manager = managerWith(store, _ConnectedTransport(), connect: true);
      addTearDown(manager.dispose);

      await tester.pumpWidget(_host(panel(store, manager)));
      await tester.pump();

      await tester.tap(find.byTooltip('会话日志'));
      await tester.pumpAndSettle();
      // 快照去掉屏幕底部没写到的空行，因此没有结尾换行。
      expect(find.text('banner'), findsOneWidget);
    });

    testWidgets('空日志的「复制 / 保存」按钮禁用', (tester) async {
      final transport = _ConnectedTransport(banner: '');
      final store = ServerStore(seed: [_server]);
      addTearDown(store.dispose);
      final manager = managerWith(store, transport, connect: true);
      addTearDown(manager.dispose);

      await tester.pumpWidget(_host(panel(store, manager)));
      await tester.pump();
      await tester.tap(find.byTooltip('会话日志'));
      await tester.pumpAndSettle();

      expect(find.text('还没有内容——会话运行后输出会出现在这里。'), findsOneWidget);
      final copy = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '复制'),
      );
      expect(copy.onPressed, isNull);
      final save = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '保存日志'),
      );
      expect(save.onPressed, isNull);
    });

    testWidgets('没有会话时状态胶囊不可点', (tester) async {
      final store = ServerStore(seed: [_server]);
      addTearDown(store.dispose);
      final manager = managerWith(store, _ConnectedTransport(), connect: false);
      addTearDown(manager.dispose);

      await tester.pumpWidget(_host(panel(store, manager)));
      await tester.pump();

      expect(find.byTooltip('会话日志'), findsNothing);
    });
  });

  group('SshTerminalView 自动重连浮层', () {
    testWidgets('有重连计划时展示倒计时与停止按钮，点停止触发回调', (tester) async {
      final transport = _ConnectedTransport();
      final session = await _connectedSession(transport);
      addTearDown(session.dispose);
      transport.closeFromRemote();

      var stopped = false;
      await tester.pumpWidget(
        _host(
          SshTerminalView(
            session: session,
            onRetry: () {},
            reconnectPlan: const ReconnectPlan(
              attempt: 3,
              delay: Duration(seconds: 42),
            ),
            onStopAutoReconnect: () => stopped = true,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('将在 42 秒后自动重连（第 3 次）'), findsOneWidget);
      expect(find.text('停止自动重连'), findsOneWidget);

      await tester.tap(find.text('停止自动重连'));
      await tester.pump();
      expect(stopped, isTrue);
    });

    testWidgets('没有计划时不展示倒计时', (tester) async {
      final transport = _ConnectedTransport();
      final session = await _connectedSession(transport);
      addTearDown(session.dispose);
      transport.closeFromRemote();

      await tester.pumpWidget(
        _host(SshTerminalView(session: session, onRetry: () {})),
      );
      await tester.pump();

      expect(find.text('停止自动重连'), findsNothing);
      expect(find.textContaining('自动重连'), findsNothing);
    });
  });
}
