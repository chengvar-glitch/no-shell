import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/ssh/session_manager.dart';
import 'package:no_shell/ssh/sftp.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/ssh/ssh_transport.dart';
import 'package:no_shell/store.dart';
import 'package:xterm/core.dart';

import 'support/forward_fakes.dart';
import 'support/transport_fakes.dart';

/// 连接一直建不完的假传输：用来制造「还在 connecting 时用户就断开」的窗口。
final class _HangingTransport with NoForwardingTransport {
  /// 放行后 [attach] 才会走完连接流程，模拟握手终于回来了。
  final gate = Completer<void>();

  bool disposed = false;

  /// attach 是否在 dispose 之后才走完。
  bool connectedAfterDispose = false;

  @override
  Future<void> attach(
    Terminal terminal, {
    required void Function() onConnected,
    required void Function() onClosed,
  }) async {
    await gate.future;
    if (disposed) connectedAfterDispose = true;
    onConnected();
  }

  @override
  Future<SftpFileSystem> openSftp() async =>
      throw const SftpException(SftpErrorKind.unsupported, 'fake transport');

  @override
  void dispose() => disposed = true;
}

SshServer _server() => SshServer(
  // store 必须预置同一 id 的主机，mark* 才能按 id 回写状态。
  id: 'srv-01',
  group: '生产环境',
  name: 'test-host',
  host: '10.0.0.1',
  username: 'root',
);

/// 每次建会话按顺序取一个假传输，便于测试「失败后重连换新传输」。
SessionManager _manager(ServerStore store, List<SshTransport> transports) =>
    SessionManager(
      store: store,
      sessionFactory: (server, credentials, _) => TerminalSession(
        server: server,
        credentials: credentials,
        transport: transports.removeAt(0),
      ),
    );

void main() {
  group('SessionManager', () {
    test('open 后主机状态经历 connecting → connected，会话持有终端缓冲区', () async {
      final store = ServerStore(seed: [_server()]);
      final transport = FakeTransport();
      final sessions = _manager(store, [transport]);

      sessions.open(_server(), const SshCredentials(password: 'pw'));
      expect(store.byId('srv-01')?.status, ServerStatus.connecting);
      expect(sessions.sessionCount, 1);

      await pumpEventQueue();

      final session = sessions.activeOf('srv-01')!;
      expect(session.phase, TerminalPhase.connected);
      expect(session.isActive, isTrue);
      expect(store.byId('srv-01')?.status, ServerStatus.connected);
      // 远端输出已写入会话的终端缓冲区，且缓冲区正是传输层附着的那一个。
      expect(identical(session.terminal, transport.attachedTerminal), isTrue);
    });

    test('重复 open 同一主机时复用活跃会话，不重复建连', () async {
      final store = ServerStore(seed: [_server()]);
      final sessions = _manager(store, [FakeTransport()]);

      final first = sessions.open(
        _server(),
        const SshCredentials(password: 'a'),
      );
      final second = sessions.open(
        _server(),
        const SshCredentials(password: 'b'),
      );

      expect(identical(first, second), isTrue);
      expect(sessions.sessionCount, 1);
    });

    test('close 移除会话、释放传输并把主机置回未连接', () async {
      final store = ServerStore(seed: [_server()]);
      final transport = FakeTransport();
      final sessions = _manager(store, [transport]);
      sessions.open(_server(), const SshCredentials(password: 'pw'));
      await pumpEventQueue();

      sessions.closeAll('srv-01');

      expect(sessions.activeOf('srv-01'), isNull);
      expect(transport.disposed, isTrue);
      expect(store.byId('srv-01')?.status, ServerStatus.idle);
    });

    test('连接还没建好就 close：传输被释放，握手回来也不再算连上', () async {
      final store = ServerStore(seed: [_server()]);
      final transport = _HangingTransport();
      final sessions = _manager(store, [transport]);

      final session = sessions.open(
        _server(),
        const SshCredentials(password: 'pw'),
      );
      await pumpEventQueue();
      expect(session.phase, TerminalPhase.connecting);

      // 用户在转圈时就断开 / 删掉主机。
      sessions.closeAll('srv-01');
      expect(transport.disposed, isTrue);
      expect(store.byId('srv-01')?.status, ServerStatus.idle);

      // 握手这时才回来：不得把已经结束的会话拉回 connected。
      transport.gate.complete();
      await pumpEventQueue();

      expect(transport.connectedAfterDispose, isTrue);
      expect(session.phase, TerminalPhase.closed);
      expect(store.byId('srv-01')?.status, ServerStatus.idle);
    });

    test('改「兼容旧服务器」后新建会话带上新取值，已建的不受影响', () async {
      // 默认会话工厂的闭包必须在**调用时**读字段。若它捕获的是构造参数
      // （与字段同名却有遮蔽），设置改了也永远传不下去，所以断言落在
      // 新建出来的 TerminalSession 上。
      final store = ServerStore(seed: [_server()]);
      final sessions = SessionManager(
        store: store,
        sessionFactory: (server, credentials, _) => TerminalSession(
          server: server,
          credentials: credentials,
          transport: FakeTransport(),
        ),
      );
      addTearDown(sessions.dispose);

      // 用默认工厂的接管路径：先看初始值。
      expect(sessions.allowLegacyHostKeys, isFalse);
      sessions.allowLegacyHostKeys = true;
      expect(sessions.allowLegacyHostKeys, isTrue);

      // 走真实默认工厂（不传 sessionFactory）验证它会下发到会话上。
      final realStore = ServerStore(seed: [_server()]);
      final real = SessionManager(store: realStore, allowLegacyHostKeys: true);
      addTearDown(real.dispose);
      final session = real.open(
        _server(),
        const SshCredentials(password: 'pw'),
      );
      await pumpEventQueue();
      expect(session.allowLegacyHostKeys, isTrue);

      final off = SessionManager(store: ServerStore(seed: [_server()]));
      addTearDown(off.dispose);
      final offSession = off.open(
        _server(),
        const SshCredentials(password: 'pw'),
      );
      await pumpEventQueue();
      expect(offSession.allowLegacyHostKeys, isFalse);
    });

    test('构造后再改字段，默认工厂的新会话立即带上新取值（快照 vs 字段）', () async {
      // 与上一条不同：这里构造时传 false、之后才改 true。若默认工厂
      // 的闭包捕获的是初始化形参（构造实参快照）而不是实例字段，
      // 这条用例必红——旧实现正是栽在这里。
      final store = ServerStore(seed: [_server()]);
      final sessions = SessionManager(store: store);
      addTearDown(sessions.dispose);
      expect(sessions.allowLegacyHostKeys, isFalse);

      sessions.allowLegacyHostKeys = true;
      final session = sessions.open(
        _server(),
        const SshCredentials(password: 'pw'),
      );
      await pumpEventQueue();
      expect(session.allowLegacyHostKeys, isTrue);
    });

    test('连接失败归类为错误状态，暴露错误种类', () async {
      final store = ServerStore(seed: [_server()]);
      final sessions = _manager(store, [
        FakeTransport(error: SSHAuthFailError('Permission denied')),
      ]);

      sessions.open(_server(), const SshCredentials(password: 'wrong'));
      await pumpEventQueue();

      final session = sessions.activeOf('srv-01')!;
      expect(session.phase, TerminalPhase.failed);
      expect(session.errorKind, TerminalErrorKind.auth);
      expect(session.isActive, isFalse);
      expect(store.byId('srv-01')?.status, ServerStatus.error);
    });

    test('远端主动断开 → 会话变为 closed，主机回到未连接', () async {
      final store = ServerStore(seed: [_server()]);
      final sessions = _manager(store, [
        FakeTransport(closeAfterConnect: true),
      ]);

      sessions.open(_server(), const SshCredentials(password: 'pw'));
      await pumpEventQueue();

      final session = sessions.activeOf('srv-01')!;
      expect(session.phase, TerminalPhase.closed);
      expect(store.byId('srv-01')?.status, ServerStatus.idle);
    });

    test('retry 用原凭据、以新传输重建会话并恢复连接', () async {
      final store = ServerStore(seed: [_server()]);
      final sessions = _manager(store, [
        FakeTransport(error: SSHAuthFailError('Permission denied')),
        FakeTransport(),
      ]);
      sessions.open(_server(), const SshCredentials(password: 'pw'));
      await pumpEventQueue();
      expect(sessions.activeOf('srv-01')!.phase, TerminalPhase.failed);

      sessions.retry(sessions.activeOf('srv-01')!);
      await pumpEventQueue();

      final session = sessions.activeOf('srv-01')!;
      expect(session.phase, TerminalPhase.connected);
      expect(session.credentials.password, 'pw');
      expect(store.byId('srv-01')?.status, ServerStatus.connected);
    });

    test('web 等不支持平台抛 UnsupportedError → unsupported 归类', () async {
      final store = ServerStore(seed: [_server()]);
      final sessions = _manager(store, [
        FakeTransport(error: UnsupportedError('no tcp')),
      ]);

      sessions.open(_server(), const SshCredentials(password: 'pw'));
      await pumpEventQueue();

      expect(
        sessions.activeOf('srv-01')!.errorKind,
        TerminalErrorKind.unsupported,
      );
    });
  });

  group('同一主机多开会话', () {
    test('openNew 每次都新建：编号按序、新会话成为当前、状态是聚合的', () async {
      final store = ServerStore(seed: [_server()]);
      final sessions = _manager(store, [FakeTransport(), FakeTransport()]);

      final first = sessions.open(
        _server(),
        const SshCredentials(password: 'a'),
      );
      await pumpEventQueue();
      final second = sessions.openNew(
        _server(),
        const SshCredentials(password: 'b'),
      );

      expect(identical(first, second), isFalse);
      expect(sessions.sessionCount, 2);
      expect(sessions.sessionCountOf('srv-01'), 2);
      expect(sessions.ordinalOf(first), 1);
      expect(sessions.ordinalOf(second), 2);
      // 当前会话 = 最新建的那条；byOrdinal 是稳定地址。
      expect(identical(sessions.activeOf('srv-01'), second), isTrue);
      expect(identical(sessions.byOrdinal('srv-01', 1), first), isTrue);
      expect(store.byId('srv-01')?.status, ServerStatus.connecting);

      await pumpEventQueue();
      expect(first.phase, TerminalPhase.connected);
      expect(second.phase, TerminalPhase.connected);
      expect(store.byId('srv-01')?.status, ServerStatus.connected);
    });

    test('open 仍复用活跃会话，不会因为多开而变成每次都新建', () async {
      final store = ServerStore(seed: [_server()]);
      final sessions = _manager(store, [FakeTransport(), FakeTransport()]);
      final first = sessions.open(
        _server(),
        const SshCredentials(password: 'a'),
      );
      await pumpEventQueue();

      final again = sessions.open(
        _server(),
        const SshCredentials(password: 'b'),
      );

      expect(identical(again, first), isTrue);
      expect(sessions.sessionCount, 1);
    });

    test('closeSession 只关一条，当前身份交给相邻的一条', () async {
      final store = ServerStore(seed: [_server()]);
      final firstTransport = FakeTransport();
      final secondTransport = FakeTransport();
      final sessions = _manager(store, [firstTransport, secondTransport]);
      final first = sessions.open(
        _server(),
        const SshCredentials(password: 'a'),
      );
      await pumpEventQueue();
      final second = sessions.openNew(
        _server(),
        const SshCredentials(password: 'b'),
      );
      await pumpEventQueue();

      // 关掉当前（第二条）：当前落回第一条，第一条的连接不动。
      sessions.closeSession(second);

      expect(sessions.sessionCountOf('srv-01'), 1);
      expect(identical(sessions.activeOf('srv-01'), first), isTrue);
      expect(secondTransport.disposed, isTrue);
      expect(firstTransport.disposed, isFalse);
      expect(store.byId('srv-01')?.status, ServerStatus.connected);

      // 再关掉最后一条：主机回到未连接，簿记清干净。
      sessions.closeSession(first);
      expect(sessions.sessionCount, 0);
      expect(sessions.activeOf('srv-01'), isNull);
      expect(sessions.sessionsOf('srv-01'), isEmpty);
      expect(store.byId('srv-01')?.status, ServerStatus.idle);
    });

    test('closeAll 关掉该主机的全部会话并把主机置回未连接', () async {
      final store = ServerStore(seed: [_server()]);
      final firstTransport = FakeTransport();
      final secondTransport = FakeTransport();
      final sessions = _manager(store, [firstTransport, secondTransport]);
      sessions.open(_server(), const SshCredentials(password: 'a'));
      sessions.openNew(_server(), const SshCredentials(password: 'b'));
      await pumpEventQueue();

      sessions.closeAll('srv-01');

      expect(sessions.sessionCount, 0);
      expect(firstTransport.disposed, isTrue);
      expect(secondTransport.disposed, isTrue);
      expect(store.byId('srv-01')?.status, ServerStatus.idle);
    });

    test('聚合状态：一条连上就算连上，全失败才算错误', () async {
      final store = ServerStore(seed: [_server()]);
      final sessions = _manager(store, [
        FakeTransport(),
        FakeTransport(error: SSHAuthFailError('Permission denied')),
      ]);
      // 第一条连上、第二条认证失败。
      sessions.open(_server(), const SshCredentials(password: 'a'));
      await pumpEventQueue();
      sessions.openNew(_server(), const SshCredentials(password: 'bad'));
      await pumpEventQueue();

      expect(sessions.hasAuthFailure('srv-01'), isTrue);
      expect(store.byId('srv-01')?.status, ServerStatus.connected);

      // 把连上的那条关掉：只剩失败的那条，状态变 error。
      sessions.closeSession(sessions.byOrdinal('srv-01', 1)!);
      expect(store.byId('srv-01')?.status, ServerStatus.error);
    });

    test('activate 切当前会话；编号永不复用', () async {
      final store = ServerStore(seed: [_server()]);
      final sessions = _manager(store, [
        FakeTransport(),
        FakeTransport(),
        FakeTransport(),
      ]);
      sessions.open(_server(), const SshCredentials(password: 'a'));
      await pumpEventQueue();
      final first = sessions.activeOf('srv-01')!;
      final second = sessions.openNew(
        _server(),
        const SshCredentials(password: 'b'),
      );
      await pumpEventQueue();

      sessions.activate(first);
      expect(identical(sessions.activeOf('srv-01'), first), isTrue);

      // 关掉第二条再开一条：新会话拿 3，不回收 2。
      sessions.closeSession(second);
      final third = sessions.openNew(
        _server(),
        const SshCredentials(password: 'c'),
      );
      expect(sessions.ordinalOf(third), 3);
      expect(identical(sessions.activeOf('srv-01'), third), isTrue);
    });

    test('会话标题跟着远端 OSC 走，供界面区分同主机的多条会话', () async {
      final store = ServerStore(seed: [_server()]);
      final transport = FakeTransport();
      final sessions = _manager(store, [transport]);
      final session = sessions.open(
        _server(),
        const SshCredentials(password: 'pw'),
      );
      await pumpEventQueue();

      expect(session.title.value, isEmpty);
      transport.attachedTerminal!.setTitle('root@web1: /var/log');
      expect(session.title.value, 'root@web1: /var/log');
    });
  });
}
