import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/ssh/session_keep_alive.dart';
import 'package:no_shell/ssh/session_manager.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/ssh_transport.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/store.dart';

import 'support/transport_fakes.dart';

/// 记录平台侧调用的假宿主：[accepts] 为 false 时模拟「拉不起来」
/// （Android 12+ 拒绝从后台启动前台服务）。
final class _FakeHost implements KeepAliveHost {
  _FakeHost({this.accepts = true});

  bool accepts;

  /// 成功拉起的次数与当时下发的文案（失败的那次不记录）。
  final List<({String title, String body})> starts = [];

  int stopCount = 0;

  @override
  Future<bool> start({required String title, required String body}) async {
    if (!accepts) return false;
    starts.add((title: title, body: body));
    return true;
  }

  @override
  Future<void> stop() async => stopCount++;
}

SshServer _server() => SshServer(
  id: 'srv-01',
  group: '生产环境',
  name: 'keep-alive-test',
  host: '10.0.0.1',
  username: 'root',
);

const _credentials = SshCredentials(password: 'pw');

({String title, String body}) _texts() =>
    (title: 'SSH 会话保持中', body: '后台保持连接，避免被系统回收');

SessionManager _manager(
  ServerStore store,
  List<SshTransport> transports, {
  bool autoReconnect = false,
}) => SessionManager(
  store: store,
  autoReconnect: autoReconnect,
  sessionFactory: (server, credentials, _) => TerminalSession(
    server: server,
    credentials: credentials,
    transport: transports.removeAt(0),
  ),
);

void main() {
  group('SessionKeepAlive', () {
    test('第一条会话连上就拉起保活，同主机再开一条不重复拉起', () async {
      final store = ServerStore(seed: [_server()]);
      final sessions = _manager(store, [FakeTransport(), FakeTransport()]);
      final host = _FakeHost();
      final keepAlive = SessionKeepAlive(
        sessions: sessions,
        texts: _texts,
        host: host,
      );
      addTearDown(keepAlive.dispose);
      addTearDown(sessions.dispose);

      sessions.open(_server(), _credentials);
      await pumpEventQueue();
      expect(keepAlive.isRunning, isTrue);
      expect(host.starts, hasLength(1), reason: '第一条会话就该拉起前台服务');

      sessions.openNew(_server(), _credentials);
      await pumpEventQueue();
      expect(host.starts, hasLength(1), reason: '已拉起时再开会话不该重发一遍');
      expect(host.stopCount, 0);
    });

    test('最后一条会话关闭后收掉保活', () async {
      final store = ServerStore(seed: [_server()]);
      final sessions = _manager(store, [FakeTransport(), FakeTransport()]);
      final host = _FakeHost();
      final keepAlive = SessionKeepAlive(
        sessions: sessions,
        texts: _texts,
        host: host,
      );
      addTearDown(keepAlive.dispose);
      addTearDown(sessions.dispose);

      sessions.open(_server(), _credentials);
      sessions.openNew(_server(), _credentials);
      await pumpEventQueue();
      expect(keepAlive.isRunning, isTrue);

      // 先关一条：还有一条在，保活不动。
      sessions.closeSession(sessions.sessionsOf('srv-01').first);
      await pumpEventQueue();
      expect(keepAlive.isRunning, isTrue);
      expect(host.stopCount, 0);

      sessions.closeSession(sessions.sessionsOf('srv-01').single);
      await pumpEventQueue();
      expect(keepAlive.isRunning, isFalse);
      expect(host.stopCount, 1);
    });

    test('拉不起来（后台被拒）时留着状态，下一次会话通知再试一次', () async {
      final store = ServerStore(seed: [_server()]);
      final sessions = _manager(store, [FakeTransport(), FakeTransport()]);
      final host = _FakeHost(accepts: false);
      final keepAlive = SessionKeepAlive(
        sessions: sessions,
        texts: _texts,
        host: host,
      );
      addTearDown(keepAlive.dispose);
      addTearDown(sessions.dispose);

      sessions.open(_server(), _credentials);
      await pumpEventQueue();
      expect(host.starts, isEmpty, reason: '平台拒绝了这一次');
      expect(keepAlive.isRunning, isFalse, reason: '没拉起来就不能记成「已在保活」，否则永远不会再试');

      // 平台恢复可用了（用户回到前台）：下一次会话通知重新尝试。
      host.accepts = true;
      sessions.openNew(_server(), _credentials);
      await pumpEventQueue();
      expect(host.starts, hasLength(1));
      expect(keepAlive.isRunning, isTrue);
    });

    test('连接失败、会话停在错误现场时收掉保活', () async {
      final store = ServerStore(seed: [_server()]);
      final sessions = _manager(store, [
        FakeTransport(error: Exception('boom')),
      ]);
      final host = _FakeHost();
      final keepAlive = SessionKeepAlive(
        sessions: sessions,
        texts: _texts,
        host: host,
      );
      addTearDown(keepAlive.dispose);
      addTearDown(sessions.dispose);

      sessions.open(_server(), _credentials);
      expect(keepAlive.isRunning, isTrue, reason: '连接中也算「会话还活着」');

      await pumpEventQueue();
      expect(sessions.holdsLiveSessions, isFalse);
      expect(keepAlive.isRunning, isFalse);
      expect(host.stopCount, 1);
    });

    test('断线退避等待期间不收保活，手动停止重连才收', () {
      fakeAsync((async) {
        final store = ServerStore(seed: [_server()]);
        final transport = FakeTransport(
          handshakeDelay: const Duration(milliseconds: 1),
        );
        final sessions = _manager(store, [transport], autoReconnect: true);
        final host = _FakeHost();
        final keepAlive = SessionKeepAlive(
          sessions: sessions,
          texts: _texts,
          host: host,
        );
        addTearDown(keepAlive.dispose);
        addTearDown(sessions.dispose);

        sessions.open(_server(), _credentials);
        async.elapse(const Duration(milliseconds: 5));
        expect(host.starts, hasLength(1));

        // 远端掉线：阶段变 closed，但退避重连已经排上（默认 2s 后发起）。
        transport.closeFromRemote();
        async.elapse(const Duration(milliseconds: 10));
        expect(
          sessions.holdsLiveSessions,
          isTrue,
          reason: '排着重连的会话不算结束——重连正好会落在后台',
        );
        expect(keepAlive.isRunning, isTrue);
        expect(host.stopCount, 0);

        // 用户点了「停止自动重连」：此刻才真的没有会话要保。
        sessions.cancelAutoReconnect(sessions.activeOf('srv-01')!);
        expect(keepAlive.isRunning, isFalse);
        expect(host.stopCount, 1);
      });
    });

    test('下发给平台的是取词回调当前给出的文案', () async {
      final store = ServerStore(seed: [_server()]);
      final sessions = _manager(store, [FakeTransport(), FakeTransport()]);
      final host = _FakeHost();
      var language = 'zh';
      final keepAlive = SessionKeepAlive(
        sessions: sessions,
        texts: () => language == 'zh'
            ? (title: 'SSH 会话保持中', body: '后台保持连接，避免被系统回收')
            : (
                title: 'SSH session kept alive',
                body: 'Holding the connection open',
              ),
        host: host,
      );
      addTearDown(keepAlive.dispose);
      addTearDown(sessions.dispose);

      sessions.open(_server(), _credentials);
      await pumpEventQueue();
      expect(host.starts.single.title, 'SSH 会话保持中');

      language = 'en';
      sessions.closeAll('srv-01');
      sessions.open(_server(), _credentials);
      await pumpEventQueue();
      expect(host.starts.last.title, 'SSH session kept alive');
      expect(host.starts.last.body, isNot(contains('后台')));
    });
  });
}
