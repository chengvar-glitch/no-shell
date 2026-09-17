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

/// 可编程假传输：成功时向终端写入欢迎语，可配置抛错 / 主动关闭。
final class _FakeTransport with NoForwardingTransport {
  _FakeTransport({this.error, this.closeAfterConnect = false});

  /// 非 null 时 [attach] 抛出该错误，模拟连接 / 认证失败。
  final Object? error;

  /// 连接成功后立即触发远端关闭。
  final bool closeAfterConnect;

  bool disposed = false;
  Terminal? attachedTerminal;

  @override
  Future<void> attach(
    Terminal terminal, {
    required void Function() onConnected,
    required void Function() onClosed,
  }) async {
    // 模拟真实网络的异步握手，让 connecting 状态可被观察。
    await Future<void>.delayed(Duration.zero);
    if (error != null) throw error!;
    attachedTerminal = terminal;
    terminal.write('welcome');
    onConnected();
    if (closeAfterConnect) onClosed();
  }

  @override
  Future<SftpFileSystem> openSftp() async =>
      throw const SftpException(SftpErrorKind.unsupported, 'fake transport');

  @override
  void dispose() => disposed = true;
}

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
      final transport = _FakeTransport();
      final sessions = _manager(store, [transport]);

      sessions.open(_server(), const SshCredentials(password: 'pw'));
      expect(store.byId('srv-01')?.status, ServerStatus.connecting);
      expect(sessions.sessionCount, 1);

      await pumpEventQueue();

      final session = sessions.byServerId('srv-01')!;
      expect(session.phase, TerminalPhase.connected);
      expect(session.isActive, isTrue);
      expect(store.byId('srv-01')?.status, ServerStatus.connected);
      // 远端输出已写入会话的终端缓冲区，且缓冲区正是传输层附着的那一个。
      expect(identical(session.terminal, transport.attachedTerminal), isTrue);
    });

    test('重复 open 同一主机时复用活跃会话，不重复建连', () async {
      final store = ServerStore(seed: [_server()]);
      final sessions = _manager(store, [_FakeTransport()]);

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
      final transport = _FakeTransport();
      final sessions = _manager(store, [transport]);
      sessions.open(_server(), const SshCredentials(password: 'pw'));
      await pumpEventQueue();

      sessions.close('srv-01');

      expect(sessions.byServerId('srv-01'), isNull);
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
      sessions.close('srv-01');
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
          transport: _FakeTransport(),
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

    test('连接失败归类为错误状态，暴露错误种类', () async {
      final store = ServerStore(seed: [_server()]);
      final sessions = _manager(store, [
        _FakeTransport(error: SSHAuthFailError('Permission denied')),
      ]);

      sessions.open(_server(), const SshCredentials(password: 'wrong'));
      await pumpEventQueue();

      final session = sessions.byServerId('srv-01')!;
      expect(session.phase, TerminalPhase.failed);
      expect(session.errorKind, TerminalErrorKind.auth);
      expect(session.isActive, isFalse);
      expect(store.byId('srv-01')?.status, ServerStatus.error);
    });

    test('远端主动断开 → 会话变为 closed，主机回到未连接', () async {
      final store = ServerStore(seed: [_server()]);
      final sessions = _manager(store, [
        _FakeTransport(closeAfterConnect: true),
      ]);

      sessions.open(_server(), const SshCredentials(password: 'pw'));
      await pumpEventQueue();

      final session = sessions.byServerId('srv-01')!;
      expect(session.phase, TerminalPhase.closed);
      expect(store.byId('srv-01')?.status, ServerStatus.idle);
    });

    test('retry 用原凭据、以新传输重建会话并恢复连接', () async {
      final store = ServerStore(seed: [_server()]);
      final sessions = _manager(store, [
        _FakeTransport(error: SSHAuthFailError('Permission denied')),
        _FakeTransport(),
      ]);
      sessions.open(_server(), const SshCredentials(password: 'pw'));
      await pumpEventQueue();
      expect(sessions.byServerId('srv-01')!.phase, TerminalPhase.failed);

      sessions.retry('srv-01');
      await pumpEventQueue();

      final session = sessions.byServerId('srv-01')!;
      expect(session.phase, TerminalPhase.connected);
      expect(session.credentials.password, 'pw');
      expect(store.byId('srv-01')?.status, ServerStatus.connected);
    });

    test('web 等不支持平台抛 UnsupportedError → unsupported 归类', () async {
      final store = ServerStore(seed: [_server()]);
      final sessions = _manager(store, [
        _FakeTransport(error: UnsupportedError('no tcp')),
      ]);

      sessions.open(_server(), const SshCredentials(password: 'pw'));
      await pumpEventQueue();

      expect(
        sessions.byServerId('srv-01')!.errorKind,
        TerminalErrorKind.unsupported,
      );
    });
  });
}
