import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/ssh/connect_flow.dart';
import 'package:no_shell/ssh/session_manager.dart';
import 'package:no_shell/ssh/sftp.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/store.dart';
import 'package:xterm/core.dart';

import 'support/credential_store_fake.dart';
import 'support/forward_fakes.dart';

/// 可编程假传输：成功时向终端写入欢迎语，可配置抛错模拟认证失败。
final class _FakeTransport with NoForwardingTransport {
  _FakeTransport({this.error});

  final Object? error;

  bool disposed = false;

  @override
  Future<void> attach(
    Terminal terminal, {
    required void Function() onConnected,
    required void Function() onClosed,
  }) async {
    // 模拟真实网络的异步握手，让直连失败可被观察。
    await Future<void>.delayed(Duration.zero);
    if (error != null) throw error!;
    terminal.write('welcome');
    onConnected();
  }

  @override
  Future<SftpFileSystem> openSftp() async =>
      throw const SftpException(SftpErrorKind.unsupported, 'fake transport');

  @override
  void dispose() => disposed = true;
}

final class _Harness {
  late SessionManager sessions;
  late List<_FakeTransport> transports;
  late FakeCredentialStore credentials;
}

SshServer _server() => const SshServer(
  id: 'srv-1',
  group: 'g',
  name: 'test-host',
  host: '10.0.0.1',
  username: 'root',
  // 让凭据弹窗落在密码分支，便于 enterText 直达密码框。
  authMethod: AuthMethod.password,
);

Future<_Harness> _pump(
  WidgetTester tester, {
  required List<_FakeTransport> transports,
  FakeCredentialStore? credentials,
  AgentKeysProbe? agentKeys,
}) async {
  final harness = _Harness()
    ..transports = transports
    ..credentials = credentials ?? FakeCredentialStore();
  final sessions = SessionManager(
    store: ServerStore(),
    // 探针默认「本机没有 agent」：测试机可能真挂着 agent，不注入就会
    // 走到真实 SSH_AUTH_SOCK 上，结果随开发机环境漂移。
    agentKeysProbe: agentKeys ?? () async => false,
    sessionFactory: (server, creds, _) => TerminalSession(
      server: server,
      credentials: creds,
      transport: transports.removeAt(0),
    ),
  );
  harness.sessions = sessions;
  final server = _server();

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => toggleSession(
                context,
                sessions: sessions,
                server: server,
                credentials: harness.credentials,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  return harness;
}

Finder get _dialogTitle => find.text('连接「test-host」');

void main() {
  testWidgets('已存凭据直连，不弹凭据框', (tester) async {
    final harness = await _pump(
      tester,
      transports: [_FakeTransport()],
      credentials: FakeCredentialStore()
        ..write('srv-1', const SshCredentials(password: 'saved')),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(
      harness.sessions.byServerId('srv-1')?.phase,
      TerminalPhase.connected,
    );
    expect(_dialogTitle, findsNothing);
  });

  testWidgets('直连认证失败回退预填弹窗，改密提交后覆盖存档并重连', (tester) async {
    final credentials = FakeCredentialStore()
      ..write('srv-1', const SshCredentials(password: 'wrong'));
    final harness = await _pump(
      tester,
      transports: [
        _FakeTransport(error: SSHAuthFailError('Permission denied')),
        _FakeTransport(),
      ],
      credentials: credentials,
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // 回退弹窗出现，旧密码已预填，「记住」保持勾选。
    expect(_dialogTitle, findsOneWidget);
    expect(find.text('wrong'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );

    await tester.enterText(find.byType(TextFormField).first, 'right');
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();

    expect(credentials['srv-1']?.password, 'right');
    expect(
      harness.sessions.byServerId('srv-1')?.phase,
      TerminalPhase.connected,
    );
    expect(harness.transports, isEmpty);
  });

  testWidgets('无存档时弹窗，勾选记住提交后写入安全存储', (tester) async {
    final harness = await _pump(tester, transports: [_FakeTransport()]);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(_dialogTitle, findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );

    await tester.enterText(find.byType(TextFormField).first, 'pw');
    await tester.tap(find.text('记住凭据'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();

    expect(harness.credentials.writeCount, 1);
    expect(harness.credentials['srv-1']?.password, 'pw');
    expect(
      harness.sessions.byServerId('srv-1')?.phase,
      TerminalPhase.connected,
    );
  });

  testWidgets('上次认证失败后不再直连旧凭据；取消记住则清除存档', (tester) async {
    final credentials = FakeCredentialStore()
      ..write('srv-1', const SshCredentials(password: 'old'));
    final harness = await _pump(
      tester,
      transports: [
        _FakeTransport(error: SSHAuthFailError('Permission denied')),
        _FakeTransport(),
      ],
      credentials: credentials,
    );

    // 先用旧凭据制造一次失败会话（消耗第 1 个传输）。
    harness.sessions.open(_server(), const SshCredentials(password: 'old'));
    await tester.pumpAndSettle();
    expect(harness.sessions.byServerId('srv-1')?.phase, TerminalPhase.failed);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // 未消耗传输再撞一次墙，直接弹预填弹窗。
    expect(_dialogTitle, findsOneWidget);
    expect(harness.transports, hasLength(1));

    await tester.tap(find.text('记住凭据'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();

    expect(harness.credentials.deleteCount, 1);
    expect(harness.credentials['srv-1'], isNull);
    expect(
      harness.sessions.byServerId('srv-1')?.phase,
      TerminalPhase.connected,
    );
  });

  testWidgets('活跃会话再次点连接即断开', (tester) async {
    final harness = await _pump(
      tester,
      transports: [_FakeTransport()],
      credentials: FakeCredentialStore()
        ..write('srv-1', const SshCredentials(password: 'saved')),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(harness.sessions.byServerId('srv-1')?.isActive, isTrue);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(harness.sessions.byServerId('srv-1'), isNull);
  });

  testWidgets('无存档凭据时静默试 agent，成功则免弹窗直连', (tester) async {
    final harness = await _pump(
      tester,
      transports: [_FakeTransport()],
      agentKeys: () async => true,
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // 会话用 agent 凭据直连上了，凭据框全程没出现。
    final session = harness.sessions.byServerId('srv-1');
    expect(session?.phase, TerminalPhase.connected);
    expect(session?.credentials.useAgent, isTrue);
    expect(_dialogTitle, findsNothing);
    expect(harness.transports, isEmpty);
  });

  testWidgets('agent 钥匙被拒后悄悄收场，回退常规凭据框', (tester) async {
    final harness = await _pump(
      tester,
      transports: [
        // 第 1 个：agent 探测，认证被拒。
        _FakeTransport(error: SSHAuthFailError('Permission denied')),
        // 第 2 个：弹窗提交后的正式连接。
        _FakeTransport(),
      ],
      agentKeys: () async => true,
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // 探测会话已收掉，不留失败现场；弹窗照常出现。
    expect(harness.sessions.byServerId('srv-1'), isNull);
    expect(_dialogTitle, findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'pw');
    await tester.tap(find.text('连接'));
    await tester.pumpAndSettle();

    expect(
      harness.sessions.byServerId('srv-1')?.phase,
      TerminalPhase.connected,
    );
    expect(harness.transports, isEmpty);
  });

  testWidgets('agent 探测遇到网络类失败时保留错误现场，不弹框掩盖', (tester) async {
    final harness = await _pump(
      tester,
      transports: [_FakeTransport(error: TimeoutException('network'))],
      agentKeys: () async => true,
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(_dialogTitle, findsNothing);
    final session = harness.sessions.byServerId('srv-1');
    expect(session?.phase, TerminalPhase.failed);
    expect(session?.errorKind, TerminalErrorKind.network);
  });
}
