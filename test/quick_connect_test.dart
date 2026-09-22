import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/app_locale.dart';
import 'package:no_shell/home_page.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/settings.dart';
import 'package:no_shell/shell_layout.dart';
import 'package:no_shell/ssh/session_manager.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/ssh/terminal_view.dart';
import 'package:no_shell/store.dart';
import 'package:no_shell/theme.dart';
import 'package:no_shell/widgets/server_detail.dart';
import 'package:no_shell/widgets/sidebar.dart';

import 'support/credential_store_fake.dart';
import 'support/transport_fakes.dart';

/// 桌面端双击主机行直连：选中、详情面板落到终端 Tab、没连上就发起连接。
/// 单击仍只是选中；已连接时双击只跳转，不断开（双击不是连接开关）。
const _alpha = SshServer(
  id: 'srv-alpha',
  group: 'g',
  name: 'alpha',
  host: '10.0.0.1',
  username: 'root',
);
const _beta = SshServer(
  id: 'srv-beta',
  group: 'g',
  name: 'beta',
  host: '10.0.0.2',
  username: 'root',
);

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

/// 双击主机行：两下 tap 落在双击窗口内（检测在 tile 里自己做，真实间隔即可）。
/// 第一击后面板会选中同一台，finder 限定在侧边栏内避免歧义。
Future<void> _doubleTap(WidgetTester tester, String name) async {
  final row = find.descendant(
    of: find.byType(Sidebar),
    matching: find.text(name),
  );
  await tester.tap(row);
  await tester.pump(kDoubleTapMinTime);
  await tester.tap(row);
  await tester.pump();
}

/// 详情面板 TabBar 的当前下标（概览 0 / 终端 1 / SFTP 2 / 转发 3）。
int _tabIndexOf(WidgetTester tester) =>
    tester.widget<TabBar>(find.byType(TabBar)).controller!.index;

void main() {
  late ServerStore store;
  late SessionManager sessions;
  late List<FakeTransport> transports;
  late FakeCredentialStore credentials;
  late ShellLayoutState layout;

  setUp(() async {
    store = ServerStore(seed: [_alpha, _beta]);
    credentials = FakeCredentialStore();
    // 存档凭据让 toggleSession 免弹窗直连，也绕开本机 agent 探针：
    // 默认探针会碰开发机真实的 SSH_AUTH_SOCK，结果随环境漂移。
    await credentials.write(_alpha.id, const SshCredentials(password: 'pw'));
    transports = [];
    sessions = SessionManager(
      store: store,
      sessionFactory: (server, creds, jumps) {
        final transport = FakeTransport(lines: ['banner']);
        transport.captureOutput = true;
        transports.add(transport);
        return TerminalSession(
          server: server,
          credentials: creds,
          transport: transport,
        );
      },
    );
    layout = ShellLayoutState();
  });

  tearDown(() {
    sessions.dispose();
    store.dispose();
  });

  Widget page() => HomePage(
    store: store,
    sessions: sessions,
    credentials: credentials,
    themeMode: ThemeMode.light,
    onThemeModeChanged: (_) {},
    language: AppLanguage.chinese,
    onLanguageChanged: (_) {},
    layout: layout,
  );

  testWidgets('双击未选中的主机：发起连接并落到终端 Tab', (tester) async {
    await tester.pumpWidget(_host(page()));
    await tester.pump();
    // 起点是空态，什么都没连。
    expect(sessions.sessionCount, 0);

    await _doubleTap(tester, 'alpha');
    await _settle(tester);
    // Tab 切换动画推完。
    await tester.pump(const Duration(milliseconds: 350));

    // 会话建立（存档凭据直连，没有弹窗），详情面板落在终端 Tab。
    expect(sessions.sessionCountOf(_alpha.id), 1);
    expect(_tabIndexOf(tester), kTerminalTabIndex);
    expect(layout.detailTab, kTerminalTabIndex);
    expect(
      tester.widget<SshTerminalView>(find.byType(SshTerminalView)).session,
      same(sessions.activeOf(_alpha.id)),
    );

    // 键盘事件落在 xterm 的焦点节点上：双击后不需要再点一下终端。
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(transports.single.sent, contains('\r'));
  });

  testWidgets('单击只选中且当帧生效：不发起连接，Tab 停在概览', (tester) async {
    await tester.pumpWidget(_host(page()));
    await tester.pump();

    // 一帧内就要选中：双击检测是自己在 tile 里量的，不许像框架
    // onDoubleTap 那样把单击在竞技场里扣住 300ms。
    await tester.tap(find.text('beta'));
    await tester.pump();

    expect(sessions.sessionCount, 0);
    expect(layout.selectedId, _beta.id);
    expect(_tabIndexOf(tester), kOverviewTabIndex);
  });

  testWidgets('双击已连接的主机：只跳终端，不断开', (tester) async {
    await tester.pumpWidget(_host(page()));
    sessions.open(_alpha, const SshCredentials(password: 'pw'));
    await _settle(tester);
    expect(sessions.sessionCountOf(_alpha.id), 1);

    await _doubleTap(tester, 'alpha');
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 350));

    // 会话原样保留：没有走 toggleSession 把它断开，也没有多开一条。
    expect(sessions.sessionCountOf(_alpha.id), 1);
    expect(transports.single.disposed, isFalse);
    expect(_tabIndexOf(tester), kTerminalTabIndex);

    // 这条会话挂上来时终端 Tab 还是隐藏的；跳回终端必须重新申请焦点。
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(transports.single.sent, contains('\r'));
  });
}
