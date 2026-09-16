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

/// 可编程假传输：成功时向终端写入欢迎语，可配置抛错 / 主动关闭。
final class _FakeTransport implements SshTransport {
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

SshServer _server() => SshServer(
  // 必须是 mock 数据里已存在的 id，mark* 才能回写状态。
  id: 'srv-01',
  group: '生产环境',
  name: 'test-host',
  host: '10.0.0.1',
  username: 'root',
);

/// 每次建会话按顺序取一个假传输，便于测试「失败后重连换新传输」。
SessionManager _manager(ServerStore store, List<_FakeTransport> transports) =>
    SessionManager(
      store: store,
      sessionFactory: (server, credentials) => TerminalSession(
        server: server,
        credentials: credentials,
        transport: transports.removeAt(0),
      ),
    );

void main() {
  group('SessionManager', () {
    test('open 后主机状态经历 connecting → connected，会话持有终端缓冲区', () async {
      final store = ServerStore();
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
      final store = ServerStore();
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
      final store = ServerStore();
      final transport = _FakeTransport();
      final sessions = _manager(store, [transport]);
      sessions.open(_server(), const SshCredentials(password: 'pw'));
      await pumpEventQueue();

      sessions.close('srv-01');

      expect(sessions.byServerId('srv-01'), isNull);
      expect(transport.disposed, isTrue);
      expect(store.byId('srv-01')?.status, ServerStatus.idle);
    });

    test('连接失败归类为错误状态，暴露错误种类', () async {
      final store = ServerStore();
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
      final store = ServerStore();
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
      final store = ServerStore();
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
      final store = ServerStore();
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
