import 'package:dartssh2/dartssh2.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/ssh/auto_reconnect.dart';
import 'package:no_shell/ssh/session_manager.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/ssh/ssh_transport.dart';
import 'package:no_shell/store.dart';

import 'support/transport_fakes.dart';

SshServer _server() => SshServer(
  id: 'srv-01',
  group: 'g',
  name: 'reconnect-test',
  host: '10.0.0.1',
  username: 'root',
);

SessionManager _manager(
  ServerStore store,
  List<SshTransport> transports, {
  bool autoReconnect = true,
}) => SessionManager(
  store: store,
  autoReconnect: autoReconnect,
  sessionFactory: (server, credentials, _) => TerminalSession(
    server: server,
    credentials: credentials,
    transport: transports.removeAt(0),
  ),
);

const _credentials = SshCredentials(password: 'pw');

/// 推进到排队的微任务与毫秒级延迟任务都跑完（假传输的握手延迟 1ms）。
void _settle(FakeAsync async) => async.elapse(const Duration(milliseconds: 5));

/// 本文件的假传输：握手延迟 1ms（与真实网络一致，connecting 可被观察）。
FakeTransport _transport({Object? error}) => FakeTransport(
  error: error,
  handshakeDelay: const Duration(milliseconds: 1),
);

void main() {
  group('ReconnectBackoff', () {
    test('默认节奏 2s 起步、逐次翻倍、60s 封顶', () {
      const backoff = ReconnectBackoff();
      expect(backoff.delayFor(1), const Duration(seconds: 2));
      expect(backoff.delayFor(2), const Duration(seconds: 4));
      expect(backoff.delayFor(3), const Duration(seconds: 8));
      expect(backoff.delayFor(5), const Duration(seconds: 32));
      // 128s 会被压到 60s，之后一直 60s。
      expect(backoff.delayFor(7), const Duration(seconds: 60));
      expect(backoff.delayFor(1000), const Duration(seconds: 60));
    });

    test('可注入节奏', () {
      const backoff = ReconnectBackoff(
        initial: Duration(milliseconds: 3),
        factor: 3,
        max: Duration(milliseconds: 30),
      );
      expect(backoff.delayFor(1), const Duration(milliseconds: 3));
      expect(backoff.delayFor(2), const Duration(milliseconds: 9));
      expect(backoff.delayFor(3), const Duration(milliseconds: 27));
      expect(backoff.delayFor(4), const Duration(milliseconds: 30));
    });
  });

  group('SessionManager 空闲重连退避', () {
    test('默认关闭：断开不自动重连', () {
      fakeAsync((async) {
        final transport = _transport();
        final sessions = _manager(ServerStore(seed: [_server()]), [
          transport,
        ], autoReconnect: false);
        sessions.open(_server(), _credentials);
        _settle(async);
        expect(sessions.activeOf('srv-01')!.phase, TerminalPhase.connected);

        transport.closeFromRemote();
        expect(sessions.activeOf('srv-01')!.phase, TerminalPhase.closed);
        expect(sessions.reconnectPlanOf(current(sessions)), isNull);
        async.elapse(const Duration(minutes: 10));
        expect(sessions.sessionCount, 1);
      });
    });

    test('意外断开排一次退避，到点换新传输重连并复用原会话参数', () {
      fakeAsync((async) {
        final first = _transport();
        final second = _transport();
        final sessions = _manager(ServerStore(seed: [_server()]), [
          first,
          second,
        ]);
        sessions.open(_server(), _credentials);
        _settle(async);
        final original = sessions.activeOf('srv-01')!;
        expect(original.phase, TerminalPhase.connected);

        first.closeFromRemote();
        final plan = sessions.reconnectPlanOf(current(sessions));
        expect(plan, isNotNull);
        expect(plan!.attempt, 1);
        expect(plan.delay, const Duration(seconds: 2));

        // 退避期内保持断开，主机状态是 idle。
        async.elapse(const Duration(seconds: 1));
        expect(sessions.activeOf('srv-01')!.phase, TerminalPhase.closed);
        expect(statusOf(sessions), ServerStatus.idle);

        async.elapse(const Duration(seconds: 1));
        _settle(async);
        final session = sessions.activeOf('srv-01')!;
        expect(session.phase, TerminalPhase.connected);
        // 旧会话已被替换回收，新会话用的是第二台假传输。
        expect(identical(original, session), isFalse);
        expect(identical(session.terminal, second.attachedTerminal), isTrue);
        expect(sessions.reconnectPlanOf(current(sessions)), isNull);
        expect(statusOf(sessions), ServerStatus.connected);
      });
    });

    test('重连再失败时退避递增（4s → 8s），暂不放弃', () {
      fakeAsync((async) {
        final first = _transport();
        final sessions = _manager(ServerStore(seed: [_server()]), [
          first,
          _transport(error: Exception('connection refused')),
          _transport(error: Exception('connection refused')),
          _transport(), // 第三次成功
        ]);
        sessions.open(_server(), _credentials);
        _settle(async);

        first.closeFromRemote();
        expect(sessions.reconnectPlanOf(current(sessions))!.attempt, 1);

        async.elapse(const Duration(seconds: 2));
        _settle(async);
        expect(sessions.activeOf('srv-01')!.phase, TerminalPhase.failed);
        expect(statusOf(sessions), ServerStatus.error);
        final plan = sessions.reconnectPlanOf(current(sessions))!;
        expect(plan.attempt, 2);
        expect(plan.delay, const Duration(seconds: 4));

        async.elapse(const Duration(seconds: 4));
        _settle(async);
        expect(sessions.activeOf('srv-01')!.phase, TerminalPhase.failed);
        expect(sessions.reconnectPlanOf(current(sessions))!.attempt, 3);

        async.elapse(const Duration(seconds: 8));
        _settle(async);
        expect(sessions.activeOf('srv-01')!.phase, TerminalPhase.connected);
        expect(sessions.reconnectPlanOf(current(sessions)), isNull);
      });
    });

    test('认证失败不自动重试：停下来把错误交还用户', () {
      fakeAsync((async) {
        final first = _transport();
        final sessions = _manager(ServerStore(seed: [_server()]), [
          first,
          _transport(error: SSHAuthFailError('Permission denied')),
        ]);
        sessions.open(_server(), _credentials);
        _settle(async);

        first.closeFromRemote();
        expect(sessions.reconnectPlanOf(current(sessions)), isNotNull);

        async.elapse(const Duration(seconds: 2));
        _settle(async);
        final session = sessions.activeOf('srv-01')!;
        expect(session.phase, TerminalPhase.failed);
        expect(session.errorKind, TerminalErrorKind.auth);
        // 重试多少次都一样的失败，不该在后台无限循环。
        expect(sessions.reconnectPlanOf(current(sessions)), isNull);
        async.elapse(const Duration(minutes: 5));
        expect(sessions.sessionCount, 1);
      });
    });

    test('用户主动断开会取消退避计划', () {
      fakeAsync((async) {
        final transport = _transport();
        final sessions = _manager(ServerStore(seed: [_server()]), [transport]);
        sessions.open(_server(), _credentials);
        _settle(async);

        transport.closeFromRemote();
        expect(sessions.reconnectPlanOf(current(sessions)), isNotNull);

        sessions.closeAll('srv-01');
        expect(sessions.reconnectPlanOf(current(sessions)), isNull);
        async.elapse(const Duration(minutes: 10));
        expect(sessions.sessionCount, 0);
      });
    });

    test('用户手动重连接管后不再自动重连', () {
      fakeAsync((async) {
        final first = _transport();
        final second = _transport();
        final sessions = _manager(ServerStore(seed: [_server()]), [
          first,
          second,
        ]);
        sessions.open(_server(), _credentials);
        _settle(async);

        first.closeFromRemote();
        sessions.retry(current(sessions)!);
        expect(sessions.reconnectPlanOf(current(sessions)), isNull);
        _settle(async);
        expect(sessions.activeOf('srv-01')!.phase, TerminalPhase.connected);
        async.elapse(const Duration(minutes: 10));
        expect(sessions.sessionCount, 1);
      });
    });

    test('cancelAutoReconnect 只停计划，保留断开的会话', () {
      fakeAsync((async) {
        final transport = _transport();
        final sessions = _manager(ServerStore(seed: [_server()]), [transport]);
        sessions.open(_server(), _credentials);
        _settle(async);

        transport.closeFromRemote();
        sessions.cancelAutoReconnect(current(sessions)!);
        expect(sessions.reconnectPlanOf(current(sessions)), isNull);
        expect(sessions.activeOf('srv-01')!.phase, TerminalPhase.closed);
        async.elapse(const Duration(minutes: 10));
        expect(sessions.sessionCount, 1);
      });
    });

    test('首次手动连接就失败不触发退避', () {
      fakeAsync((async) {
        final sessions = _manager(ServerStore(seed: [_server()]), [
          _transport(error: Exception('no route to host')),
        ]);
        sessions.open(_server(), _credentials);
        _settle(async);
        expect(sessions.activeOf('srv-01')!.phase, TerminalPhase.failed);
        expect(sessions.reconnectPlanOf(current(sessions)), isNull);
        async.elapse(const Duration(minutes: 10));
        expect(sessions.sessionCount, 1);
      });
    });

    test('两条会话各自退避：掉线的那条重连，另一条不被替换', () {
      fakeAsync((async) {
        final first = _transport();
        final second = _transport();
        final sessions = _manager(ServerStore(seed: [_server()]), [
          first,
          second,
          _transport(), // 第一条重连时换上的新传输
        ]);
        final server = _server();
        sessions.open(server, _credentials);
        _settle(async);
        final one = sessions.activeOf('srv-01')!;
        sessions.openNew(server, _credentials);
        _settle(async);
        final two = sessions.activeOf('srv-01')!;
        expect(sessions.sessionCount, 2);

        // 第一条掉线：只有它排退避，当前会话仍是第二条。
        first.closeFromRemote();
        expect(one.phase, TerminalPhase.closed);
        expect(sessions.reconnectPlanOf(one)!.attempt, 1);
        expect(sessions.reconnectPlanOf(two), isNull);
        expect(identical(sessions.activeOf('srv-01'), two), isTrue);

        async.elapse(const Duration(seconds: 2));
        _settle(async);

        // 就地重开第一条：编号仍是 1，第二条对象与连接都没被动过。
        final reopened = sessions.sessionsOf('srv-01').first;
        expect(identical(reopened, one), isFalse);
        expect(reopened.phase, TerminalPhase.connected);
        expect(sessions.ordinalOf(reopened), 1);
        expect(sessions.ordinalOf(two), 2);
        expect(two.phase, TerminalPhase.connected);
        expect(identical(sessions.activeOf('srv-01'), two), isTrue);
        expect(sessions.reconnectPlanOf(reopened), isNull);
      });
    });

    test('retry 只重开被点的那一条：编号与当前身份都保持', () {
      fakeAsync((async) {
        final first = _transport();
        final second = _transport();
        final sessions = _manager(ServerStore(seed: [_server()]), [
          first,
          second,
          _transport(), // retry 换上的新传输
        ]);
        final server = _server();
        sessions.open(server, _credentials);
        _settle(async);
        final one = sessions.activeOf('srv-01')!;
        sessions.openNew(server, _credentials);
        _settle(async);
        final two = sessions.activeOf('srv-01')!;

        // 当前这条断了：手动重连接管，退避计划作废。
        second.closeFromRemote();
        expect(two.phase, TerminalPhase.closed);
        final fresh = sessions.retry(two)!;
        _settle(async);

        expect(fresh.phase, TerminalPhase.connected);
        expect(sessions.ordinalOf(fresh), 2);
        expect(identical(sessions.activeOf('srv-01'), fresh), isTrue);
        // 另一条会话对象原封不动，连接也还在。
        expect(identical(sessions.sessionsOf('srv-01').first, one), isTrue);
        expect(one.phase, TerminalPhase.connected);
        expect(sessions.sessionCount, 2);
      });
    });

    test('关掉一条会话不影响同主机另一条排着的退避', () {
      fakeAsync((async) {
        final first = _transport();
        final second = _transport();
        final sessions = _manager(ServerStore(seed: [_server()]), [
          first,
          second,
          _transport(),
        ]);
        final server = _server();
        sessions.open(server, _credentials);
        _settle(async);
        final one = sessions.activeOf('srv-01')!;
        sessions.openNew(server, _credentials);
        _settle(async);
        final two = sessions.activeOf('srv-01')!;

        first.closeFromRemote();
        expect(sessions.reconnectPlanOf(one)!.attempt, 1);

        // 关掉另一条（当前会话）：退避计划属于掉线的那一条，不该被带走。
        sessions.closeSession(two);
        expect(sessions.sessionCount, 1);
        expect(sessions.reconnectPlanOf(one), isNotNull);

        async.elapse(const Duration(seconds: 2));
        _settle(async);
        expect(sessions.sessionCount, 1);
        expect(sessions.activeOf('srv-01')!.phase, TerminalPhase.connected);
      });
    });
  });
}

/// 该主机的当前会话；重连会换掉会话对象、但当前身份跟着走，所以每次现取。
TerminalSession? current(SessionManager sessions) =>
    sessions.activeOf('srv-01');

/// 从会话管理器里读该主机的展示状态。
ServerStatus statusOf(SessionManager sessions) =>
    sessions.store.byId('srv-01')?.status ?? ServerStatus.idle;
