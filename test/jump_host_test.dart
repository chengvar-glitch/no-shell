import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/ssh/connect_flow.dart';
import 'package:no_shell/ssh/host_key_store.dart';
import 'package:no_shell/ssh/jump_host.dart';
import 'package:no_shell/ssh/session_manager.dart';
import 'package:no_shell/ssh/sftp.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/store.dart';
import 'package:xterm/core.dart';

import 'support/credential_store_fake.dart';
import 'support/forward_fakes.dart';

SshServer _server({
  required String id,
  required String name,
  String? jump,
  String host = '10.0.0.1',
  AuthMethod auth = AuthMethod.password,
}) => SshServer(
  id: id,
  group: 'g',
  name: name,
  host: host,
  username: 'root',
  authMethod: auth,
  jumpServerId: jump,
);

SshServer? _lookup(List<SshServer> servers, String id) {
  for (final server in servers) {
    if (server.id == id) return server;
  }
  return null;
}

void main() {
  group('resolveJumpChain', () {
    test('没有跳板机时是空链路', () {
      final target = _server(id: 't', name: 'target');
      expect(resolveJumpChain(target, (id) => null), isEmpty);
    });

    test('链路按由外到内排列，最后一项最靠近目标', () {
      final outer = _server(id: 'a', name: 'outer');
      final middle = _server(id: 'b', name: 'middle', jump: 'a');
      final target = _server(id: 't', name: 'target', jump: 'b');
      final chain = resolveJumpChain(
        target,
        (id) => _lookup([outer, middle, target], id),
      );
      expect(chain.map((s) => s.id), ['a', 'b']);
      expect(
        connectionChain(
          target,
          (id) => _lookup([outer, middle, target], id),
        ).map((s) => s.id),
        ['a', 'b', 't'],
      );
    });

    test('跳板机指向自己 → cycle', () {
      final target = _server(id: 't', name: 'target', jump: 't');
      expect(
        () => resolveJumpChain(target, (id) => _lookup([target], id)),
        throwsA(
          isA<JumpChainException>().having(
            (e) => e.kind,
            'kind',
            JumpChainErrorKind.cycle,
          ),
        ),
      );
    });

    test('A→B→A 的环也能在有限步内报出来', () {
      final a = _server(id: 'a', name: 'a', jump: 'b');
      final b = _server(id: 'b', name: 'b', jump: 'a');
      expect(
        () => resolveJumpChain(a, (id) => _lookup([a, b], id)),
        throwsA(
          isA<JumpChainException>().having(
            (e) => e.kind,
            'kind',
            JumpChainErrorKind.cycle,
          ),
        ),
      );
    });

    test('跳板机已被删除 → missing，且指名是哪台主机指向了它', () {
      final target = _server(id: 't', name: 'target', jump: 'gone');
      expect(
        () => resolveJumpChain(target, (id) => null),
        throwsA(
          isA<JumpChainException>()
              .having((e) => e.kind, 'kind', JumpChainErrorKind.missing)
              .having((e) => e.hostName, 'hostName', 'target'),
        ),
      );
    });

    test('层数超过上限 → tooDeep（不会无限往下走）', () {
      // 造一条比上限更长的合法链路（上限本身是允许的层数，再多一层才报错）。
      final servers = <SshServer>[];
      for (var i = 0; i <= kMaxJumpDepth + 1; i++) {
        servers.add(
          _server(id: 'h$i', name: 'h$i', jump: i == 0 ? null : 'h${i - 1}'),
        );
      }
      final target = servers.last;
      expect(
        () => resolveJumpChain(target, (id) => _lookup(servers, id)),
        throwsA(
          isA<JumpChainException>().having(
            (e) => e.kind,
            'kind',
            JumpChainErrorKind.tooDeep,
          ),
        ),
      );
    });
  });

  group('jumpHostCandidates', () {
    test('排除自己与所有会连成环的主机', () {
      final a = _server(id: 'a', name: 'a');
      final b = _server(id: 'b', name: 'b', jump: 'a');
      final c = _server(id: 'c', name: 'c', jump: 'b');
      final free = _server(id: 'd', name: 'd');
      final all = [a, b, c, free];

      // 给 c 选跳板机：自己不能选；其余都是合法候选（b 跳向 a，不与 c 成环）。
      expect(jumpHostCandidates(c, all).map((s) => s.id), ['a', 'b', 'd']);
      // 给 a 选跳板机：b 与 c 都在链路上依赖 a，选下去就成环。
      expect(jumpHostCandidates(a, all).map((s) => s.id), ['d']);
      // 新建（没有自己）时全部可选。
      expect(jumpHostCandidates(null, all).map((s) => s.id), [
        'a',
        'b',
        'c',
        'd',
      ]);
    });
  });

  group('SshHopException 的归类与解包', () {
    test('跳板机认证失败按 auth 归类，并指出是哪一跳', () async {
      final hop = _server(id: 'j', name: 'jump-host');
      final error = SshHopException(hop, SSHAuthFailError('Permission denied'));
      final session = TerminalSession(
        server: _server(id: 't', name: 'target'),
        credentials: const SshCredentials(),
        transport: _FailingTransport(error),
      );
      await session.start();
      expect(session.phase, TerminalPhase.failed);
      expect(session.errorKind, TerminalErrorKind.auth);
      expect(session.failedHop, 'jump-host');
      session.dispose();
    });

    test('嵌套两层的失败也能剥到真正的原因', () {
      final inner = _server(id: 'j2', name: 'inner');
      final outer = _server(id: 'j1', name: 'outer');
      final error = SshHopException(
        outer,
        SshHopException(inner, SSHAuthFailError('denied')),
      );
      expect(unwrapHopError(error), isA<SSHAuthFailError>());
    });

    test('跳板机主机密钥不一致时，hostKeyChanged 指向那一跳的地址', () async {
      final hop = _server(id: 'j', name: 'jump-host', host: '10.0.0.9');
      final error = SshHopException(
        hop,
        const HostKeyChangedException(
          host: '10.0.0.9',
          port: 2222,
          keyType: 'ssh-ed25519',
          fingerprint: 'SHA256:abc',
        ),
      );
      final session = TerminalSession(
        server: _server(id: 't', name: 'target'),
        credentials: const SshCredentials(),
        transport: _FailingTransport(error),
      );
      await session.start();
      expect(session.errorKind, TerminalErrorKind.hostKey);
      expect(session.hostKeyChanged?.host, '10.0.0.9');
      expect(session.hostKeyChanged?.port, 2222);
      session.dispose();
    });
  });

  group('连接流程与跳板机', () {
    testWidgets('已存凭据的两跳：不弹窗，按由外到内把链路交给会话', (tester) async {
      final servers = [
        _server(id: 'jump', name: 'jump-host', host: '10.0.0.9'),
        _server(id: 'target', name: 'target', jump: 'jump'),
      ];
      final credentials = FakeCredentialStore()
        ..write('jump', const SshCredentials(password: 'jump-pw'))
        ..write('target', const SshCredentials(password: 'target-pw'));
      final harness = await _pump(
        tester,
        servers: servers,
        credentials: credentials,
        target: servers[1],
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('连接「target」'), findsNothing);
      expect(
        harness.sessions.byServerId('target')?.phase,
        TerminalPhase.connected,
      );
      final jumps = harness.jumps.single;
      expect(jumps.map((hop) => hop.server.id), ['jump']);
      expect(jumps.single.credentials.password, 'jump-pw');
    });

    testWidgets('跳板机没存凭据时弹的是跳板机的框，取消则整条连接取消', (tester) async {
      final servers = [
        _server(id: 'jump', name: 'jump-host', host: '10.0.0.9'),
        _server(id: 'target', name: 'target', jump: 'jump'),
      ];
      final credentials = FakeCredentialStore()
        ..write('target', const SshCredentials(password: 'target-pw'));
      final harness = await _pump(
        tester,
        servers: servers,
        credentials: credentials,
        target: servers[1],
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // 先要跳板机的凭据，并且说明这是跳板机。
      expect(find.text('连接「jump-host」'), findsOneWidget);
      expect(find.textContaining('跳板机'), findsWidgets);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(harness.jumps, isEmpty);
      expect(harness.sessions.sessionCount, 0);
    });

    testWidgets('填入跳板机凭据后继续连目标，两跳都记在会话上', (tester) async {
      final servers = [
        _server(id: 'jump', name: 'jump-host', host: '10.0.0.9'),
        _server(id: 'target', name: 'target', jump: 'jump'),
      ];
      final credentials = FakeCredentialStore()
        ..write('target', const SshCredentials(password: 'target-pw'));
      final harness = await _pump(
        tester,
        servers: servers,
        credentials: credentials,
        target: servers[1],
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'jump-pw');
      await tester.tap(find.text('连接'));
      await tester.pumpAndSettle();

      // 勾选框默认未选：跳板机凭据只留在内存里。
      expect(credentials['jump'], isNull);
      expect(harness.jumps.single.single.credentials.password, 'jump-pw');
      expect(
        harness.sessions.byServerId('target')?.phase,
        TerminalPhase.connected,
      );
    });

    testWidgets('跳板环 → 提示且不建立任何会话', (tester) async {
      final servers = [
        _server(id: 'a', name: 'a', jump: 'b'),
        _server(id: 'b', name: 'b', jump: 'a'),
      ];
      final credentials = FakeCredentialStore()
        ..write('a', const SshCredentials(password: 'pw'))
        ..write('b', const SshCredentials(password: 'pw'));
      final harness = await _pump(
        tester,
        servers: servers,
        credentials: credentials,
        target: servers[0],
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.textContaining('形成了环'), findsOneWidget);
      expect(harness.sessions.sessionCount, 0);
      expect(harness.jumps, isEmpty);
    });

    testWidgets('跳板机被删除 → 提示且不建立任何会话', (tester) async {
      final target = _server(id: 't', name: 'target', jump: 'gone');
      final harness = await _pump(
        tester,
        servers: [target],
        credentials: FakeCredentialStore()
          ..write('t', const SshCredentials(password: 'pw')),
        target: target,
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.textContaining('已被删除'), findsOneWidget);
      expect(harness.sessions.sessionCount, 0);
    });

    testWidgets('跳板机没存凭据时静默试 agent，免弹窗直连', (tester) async {
      final servers = [
        _server(id: 'jump', name: 'jump-host', host: '10.0.0.9'),
        _server(id: 'target', name: 'target', jump: 'jump'),
      ];
      final credentials = FakeCredentialStore()
        ..write('target', const SshCredentials(password: 'target-pw'));
      final harness = await _pump(
        tester,
        servers: servers,
        credentials: credentials,
        target: servers[1],
        hopAgent: (server, upstream) async {
          // 只有跳板机这一跳走 agent；上游链路为空。
          expect(server.id, 'jump');
          expect(upstream, isEmpty);
          return const SshCredentials(useAgent: true);
        },
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // 全程没弹凭据框，跳板链路带着 agent 凭据连上了目标。
      expect(find.text('连接「jump-host」'), findsNothing);
      expect(harness.jumps.single.single.credentials.useAgent, isTrue);
      expect(
        harness.sessions.byServerId('target')?.phase,
        TerminalPhase.connected,
      );
    });
  });
}

/// 直接以给定错误结束的假传输（用来驱动会话的失败归类）。
final class _FailingTransport with NoForwardingTransport {
  _FailingTransport(this.error);

  final Object error;

  @override
  Future<void> attach(
    Terminal terminal, {
    required void Function() onConnected,
    required void Function() onClosed,
  }) async => throw error;

  @override
  Future<SftpFileSystem> openSftp() async => throw UnimplementedError();

  @override
  void dispose() {}
}

final class _Harness {
  late SessionManager sessions;
  late FakeCredentialStore credentials;

  /// 每次建会话时拿到的跳板链路（由外到内）。
  late List<List<SshHop>> jumps;
}

/// 记录会话建连时拿到的跳板链路。
final class _JumpAwareTransport with NoForwardingTransport {
  @override
  Future<void> attach(
    Terminal terminal, {
    required void Function() onConnected,
    required void Function() onClosed,
  }) async => onConnected();

  @override
  Future<SftpFileSystem> openSftp() async => throw UnimplementedError();

  @override
  void dispose() {}
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required List<SshServer> servers,
  required FakeCredentialStore credentials,
  required SshServer target,
  AgentKeysProbe? agentKeys,
  HopAgentProbe? hopAgent,
}) async {
  final harness = _Harness()
    ..credentials = credentials
    ..jumps = [];
  final store = ServerStore(seed: servers);
  final sessions = SessionManager(
    store: store,
    // 探针默认「本机没有 agent」：不注入就会碰真实 SSH_AUTH_SOCK，
    // 结果随开发机环境漂移。
    agentKeysProbe: agentKeys ?? () async => false,
    hopAgentProbe: hopAgent,
    sessionFactory: (server, creds, jumps) {
      harness.jumps.add(jumps);
      return TerminalSession(
        server: server,
        credentials: creds,
        transport: _JumpAwareTransport(),
      );
    },
  );
  harness.sessions = sessions;

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
                server: target,
                credentials: credentials,
                store: store,
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
