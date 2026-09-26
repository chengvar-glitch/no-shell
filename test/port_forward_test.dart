import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/ssh/forward.dart';
import 'package:no_shell/ssh/port_forward_runtime.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_session.dart';

import 'support/forward_fakes.dart';

/// 让排队的异步回调跑完（转发里的 listen / 管道都是异步接上的）。
Future<void> settle() => Future<void>.delayed(Duration.zero);

PortForwardRule _rule({
  String id = 'fwd-1',
  PortForwardMode mode = PortForwardMode.local,
  String localHost = '127.0.0.1',
  int localPort = 8080,
  String remoteHost = '10.0.0.5',
  int remotePort = 80,
  bool autoStart = false,
}) => PortForwardRule(
  id: id,
  mode: mode,
  localHost: localHost,
  localPort: localPort,
  remoteHost: remoteHost,
  remotePort: remotePort,
  autoStart: autoStart,
);

({
  PortForwardManager manager,
  FakeForwardTransport transport,
  FakeTunnelGateway gateway,
})
_build() {
  final transport = FakeForwardTransport();
  final gateway = FakeTunnelGateway();
  return (
    manager: PortForwardManager(transport, gateway: gateway),
    transport: transport,
    gateway: gateway,
  );
}

void main() {
  group('PortForwardRule', () {
    test('JSON 往返保留全部字段', () {
      const rule = PortForwardRule(
        id: 'fwd-9',
        mode: PortForwardMode.remote,
        localHost: '127.0.0.1',
        localPort: 2222,
        remoteHost: '0.0.0.0',
        remotePort: 8022,
        autoStart: true,
      );
      final restored = PortForwardRule.fromJson(rule.toJson());
      expect(restored, rule);
    });

    test('认不出的模式退回本地转发，空 id 不抛异常', () {
      final restored = PortForwardRule.fromJson({
        'id': 'x',
        'mode': 'socks-from-the-future',
        'localPort': 1,
        'remotePort': 2,
      });
      expect(restored.mode, PortForwardMode.local);
      expect(restored.localHost, '127.0.0.1');
      expect(restored.autoStart, isFalse);
    });

    test('端口越界 / 地址为空判定为不可启动', () {
      expect(_rule(localPort: 0).isRunnable, isFalse);
      expect(_rule(remotePort: 70000).isRunnable, isFalse);
      expect(_rule(remoteHost: '  ').isRunnable, isFalse);
      expect(_rule().isRunnable, isTrue);
    });

    test('远程转发允许目标端口 0（由服务端分配）', () {
      expect(
        _rule(mode: PortForwardMode.remote, remotePort: 0).isRunnable,
        isTrue,
      );
      // 本地转发的目标端口 0 是没填，不能放行。
      expect(_rule(remotePort: 0).isRunnable, isFalse);
    });
  });

  group('SshServer 转发与跳板机序列化', () {
    test('forwards 与 jumpServerId 一起往返', () {
      final server = SshServer(
        id: 'srv-1',
        group: 'g',
        name: 'target',
        host: '10.0.0.1',
        username: 'root',
        jumpServerId: 'srv-2',
        forwards: [
          _rule(id: 'a'),
          _rule(id: 'b', mode: PortForwardMode.dynamic, remotePort: 0),
        ],
      );
      final restored = SshServer.fromJson(server.toJson());
      expect(restored.jumpServerId, 'srv-2');
      expect(restored.forwards, server.forwards);
    });

    test('坏规则只跳过那一条，不带走整台主机', () {
      final restored = SshServer.fromJson({
        'id': 'srv-1',
        'host': '10.0.0.1',
        'username': 'root',
        'jumpServerId': '',
        'forwards': [
          'not-a-map',
          {'id': 'ok', 'mode': 'local', 'localPort': 1, 'remotePort': 2},
        ],
      });
      expect(restored.jumpServerId, isNull);
      expect(restored.forwards.map((rule) => rule.id), ['ok']);
    });

    test('copyWith 能清掉跳板机，也能整体替换转发规则', () {
      final server = SshServer(
        id: 'srv-1',
        group: 'g',
        name: 'target',
        host: '10.0.0.1',
        username: 'root',
        jumpServerId: 'srv-2',
        forwards: [_rule(id: 'a')],
      );
      expect(server.copyWith().jumpServerId, 'srv-2');
      expect(server.copyWith(clearJumpServer: true).jumpServerId, isNull);
      expect(server.copyWith(jumpServerId: 'srv-3').jumpServerId, 'srv-3');
      expect(server.copyWith(forwards: const []).forwards, isEmpty);
    });
  });

  group('PortForwardManager 本地转发', () {
    test('监听成功后按目标地址逐条开直连通道，双向字节都能过', () async {
      final env = _build();
      await env.manager.start(_rule());
      expect(env.manager.isRunning('fwd-1'), isTrue);
      expect(env.manager.statusOf('fwd-1').phase, PortForwardPhase.running);
      expect(env.manager.statusOf('fwd-1').boundPort, 8080);

      final listener = env.gateway.listenerFor('127.0.0.1', 8080)!;
      final inbound = listener.connect(label: 'localhost client');
      await settle();

      // 目标地址是「服务端视角」的地址，原样透传。
      expect(env.transport.directRequests, [(host: '10.0.0.5', port: 80)]);
      final outbound = env.transport.directChannels.single;

      // 客户端 → 目标
      inbound.feed([1, 2, 3]);
      await settle();
      expect(outbound.received, [1, 2, 3]);

      // 目标 → 客户端
      outbound.feed([9, 8]);
      await settle();
      expect(inbound.received, [9, 8]);
    });

    test('目标连不上时只断开这一条连接，转发仍在跑', () async {
      final env = _build();
      await env.manager.start(_rule());
      env.transport.directError = const ForwardException(
        ForwardErrorKind.refused,
        'connection refused',
      );

      final listener = env.gateway.listenerFor('127.0.0.1', 8080)!;
      final inbound = listener.connect();
      await settle();

      expect(inbound.destroyed, isTrue);
      expect(env.manager.statusOf('fwd-1').phase, PortForwardPhase.running);
    });

    test('任一方向结束就关掉两条通道', () async {
      final env = _build();
      await env.manager.start(_rule());
      final listener = env.gateway.listenerFor('127.0.0.1', 8080)!;
      final inbound = listener.connect();
      await settle();
      final outbound = env.transport.directChannels.single;

      inbound.finish();
      await settle();
      expect(outbound.closed || outbound.destroyed, isTrue);
    });

    test('本地转发的监听端口 0 视为未填，直接失败', () async {
      final env = _build();
      await env.manager.start(_rule(localPort: 0));
      expect(env.manager.statusOf('fwd-1').phase, PortForwardPhase.failed);
      expect(env.gateway.listeners, isEmpty);
    });

    test('本地端口占用 → 失败态带 refused 与原因', () async {
      final env = _build();
      env.gateway.listenError = const ForwardException(
        ForwardErrorKind.refused,
        'address already in use',
      );
      await env.manager.start(_rule());
      final status = env.manager.statusOf('fwd-1');
      expect(status.phase, PortForwardPhase.failed);
      expect(status.errorKind, ForwardErrorKind.refused);
      expect(status.error, contains('address already in use'));
      expect(env.manager.isRunning('fwd-1'), isFalse);
    });

    test('规则没填全时直接失败，不去碰网络', () async {
      final env = _build();
      await env.manager.start(_rule(localPort: 0, remotePort: 0));
      expect(env.manager.statusOf('fwd-1').phase, PortForwardPhase.failed);
      expect(env.gateway.listeners, isEmpty);
    });

    test('重复启动是空操作；停止后回到未启动并关掉监听', () async {
      final env = _build();
      await env.manager.start(_rule());
      await env.manager.start(_rule());
      final listener = env.gateway.listenerFor('127.0.0.1', 8080)!;
      expect(listener.accepted, isEmpty);

      await env.manager.stop('fwd-1');
      expect(env.manager.isRunning('fwd-1'), isFalse);
      expect(env.manager.statusOf('fwd-1').phase, PortForwardPhase.stopped);
      expect(listener.closed, isTrue);

      // 停掉之后再启动：这一次真的重新监听。
      await env.manager.start(_rule());
      expect(env.manager.isRunning('fwd-1'), isTrue);
    });
  });

  group('PortForwardManager 远程转发', () {
    test('把服务端监听请求原样发出，并按本地地址落地每条入站连接', () async {
      final env = _build();
      await env.manager.start(
        _rule(
          mode: PortForwardMode.remote,
          localHost: '127.0.0.1',
          localPort: 22,
          remoteHost: '0.0.0.0',
          remotePort: 8022,
        ),
      );
      expect(env.transport.remoteRequests, [(host: '0.0.0.0', port: 8022)]);

      final inbound = env.transport.remoteListener!.connect();
      await settle();
      expect(env.gateway.dialed, [(host: '127.0.0.1', port: 22)]);

      final local = env.gateway.dialedChannels.single;
      inbound.feed([7]);
      await settle();
      expect(local.received, [7]);
      local.feed([4]);
      await settle();
      expect(inbound.received, [4]);
    });

    test('服务端分配端口（请求 0）时状态里带实际端口', () async {
      final env = _build();
      await env.manager.start(
        _rule(mode: PortForwardMode.remote, remotePort: 0),
      );
      expect(env.manager.statusOf('fwd-1').boundPort, 42000);
    });

    test('服务端拒绝监听 → failed，原因归类为 refused', () async {
      final env = _build();
      env.transport.remoteError = const ForwardException(
        ForwardErrorKind.refused,
        'Server refused to listen on the requested port',
      );
      await env.manager.start(_rule(mode: PortForwardMode.remote));
      expect(env.manager.statusOf('fwd-1').phase, PortForwardPhase.failed);
      expect(env.manager.statusOf('fwd-1').errorKind, ForwardErrorKind.refused);
    });

    test('本地目标连不上时断开入站连接，不拖垮整条转发', () async {
      final env = _build();
      await env.manager.start(_rule(mode: PortForwardMode.remote));
      env.gateway.dialError = const ForwardException(
        ForwardErrorKind.refused,
        'connection refused',
      );
      final inbound = env.transport.remoteListener!.connect();
      await settle();
      expect(inbound.destroyed, isTrue);
      expect(env.manager.statusOf('fwd-1').phase, PortForwardPhase.running);
    });
  });

  group('PortForwardManager 动态转发', () {
    test('起一个本地 SOCKS5 代理，停止时关掉', () async {
      final env = _build();
      await env.manager.start(
        _rule(mode: PortForwardMode.dynamic, localPort: 1080, remotePort: 0),
      );
      expect(env.transport.dynamicRequests, [(host: '127.0.0.1', port: 1080)]);
      expect(env.manager.statusOf('fwd-1').phase, PortForwardPhase.running);

      await env.manager.stop('fwd-1');
      expect(env.transport.proxies.single.closed, isTrue);
    });

    test('web 上不支持时归类为 unsupported', () async {
      final env = _build();
      env.transport.dynamicError = UnsupportedError('no raw TCP');
      await env.manager.start(
        _rule(mode: PortForwardMode.dynamic, remotePort: 0),
      );
      final status = env.manager.statusOf('fwd-1');
      expect(status.phase, PortForwardPhase.failed);
      expect(status.errorKind, ForwardErrorKind.unsupported);
    });
  });

  group('PortForwardManager 生命周期', () {
    test('自动启动只挑 autoStart 的规则', () async {
      final env = _build();
      env.manager.startAutoRules([
        _rule(id: 'fwd-1', autoStart: true),
        _rule(id: 'fwd-2', localPort: 8081),
      ]);
      await settle();
      expect(env.manager.runningIds, {'fwd-1'});
    });

    test('stopAll 停掉全部并把状态清回未启动', () async {
      final env = _build();
      await env.manager.start(_rule(id: 'fwd-1'));
      await env.manager.start(
        _rule(id: 'fwd-2', mode: PortForwardMode.dynamic, localPort: 1080),
      );
      env.manager.stopAll();
      await settle();
      expect(env.manager.runningIds, isEmpty);
      expect(env.manager.statusOf('fwd-1').phase, PortForwardPhase.stopped);
      expect(env.transport.proxies.single.closed, isTrue);
      expect(env.gateway.listenerFor('127.0.0.1', 8080)!.closed, isTrue);
    });

    test('dispose 关掉监听与在跑的通道，并且不再通知', () async {
      final env = _build();
      await env.manager.start(_rule());
      final listener = env.gateway.listenerFor('127.0.0.1', 8080)!;
      final inbound = listener.connect();
      await settle();
      final outbound = env.transport.directChannels.single;

      var notifications = 0;
      env.manager.addListener(() => notifications++);
      env.manager.dispose();
      await settle();

      expect(listener.closed, isTrue);
      expect(inbound.destroyed || inbound.closed, isTrue);
      expect(outbound.destroyed || outbound.closed, isTrue);
      expect(notifications, 0);
    });

    test('启动过程中被 dispose：不留下没人持有的监听', () async {
      final env = _build();
      final starting = env.manager.start(_rule());
      env.manager.dispose();
      await starting;
      await settle();
      expect(env.manager.runningIds, isEmpty);
      expect(env.gateway.listenerFor('127.0.0.1', 8080)?.closed, isTrue);
    });

    test('状态没变就不通知：重复停一条已经停着的规则', () async {
      final env = _build();
      await env.manager.start(_rule());
      await settle();
      await env.manager.stop('fwd-1'); // 回到未启动（这一笔会通知）
      var notifications = 0;
      env.manager.addListener(() => notifications++);

      await env.manager.stop('fwd-1'); // 已经停着，再来一次
      env.manager.stopAll(); // 全部收一遍，但没有一条状态真的在变
      await settle();

      expect(notifications, 0);
    });

    test('stopAll 收掉多条规则时只通知一次', () async {
      final env = _build();
      await env.manager.start(_rule(id: 'fwd-1'));
      await env.manager.start(
        _rule(id: 'fwd-2', mode: PortForwardMode.dynamic, localPort: 1080),
      );
      await settle();
      var notifications = 0;
      env.manager.addListener(() => notifications++);

      env.manager.stopAll();
      await settle();

      expect(env.manager.runningIds, isEmpty);
      expect(notifications, 1);
    });

    test('启动中 stop：在飞的 start 不把规则复活成运行中', () async {
      final env = _build();
      final gate = Completer<void>();
      env.gateway.listenGate = gate;
      final starting = env.manager.start(_rule());
      await settle();
      expect(env.manager.statusOf('fwd-1').phase, PortForwardPhase.starting);

      final stopped = env.manager.stop('fwd-1');
      gate.complete(); // 放行在飞的 bind
      await starting;
      await stopped;
      await settle();

      expect(env.manager.runningIds, isEmpty);
      expect(env.manager.statusOf('fwd-1').phase, PortForwardPhase.stopped);
      expect(env.gateway.listenerFor('127.0.0.1', 8080)!.closed, isTrue);
    });

    test('启动中 stopAll（连接瞬断）：规则不被复活成挂在尸体会话上', () async {
      final env = _build();
      final gate = Completer<void>();
      env.gateway.listenGate = gate;
      final starting = env.manager.start(_rule());
      await settle();

      env.manager.stopAll();
      gate.complete();
      await starting;
      await settle();

      expect(env.manager.runningIds, isEmpty);
      expect(env.manager.statusOf('fwd-1').phase, PortForwardPhase.stopped);
      expect(env.gateway.listenerFor('127.0.0.1', 8080)!.closed, isTrue);
    });

    test('stop 之后再 start：新代次照常落地', () async {
      final env = _build();
      final gate = Completer<void>();
      env.gateway.listenGate = gate;
      final first = env.manager.start(_rule());
      await settle();
      final stopped = env.manager.stop('fwd-1');
      gate.complete();
      await first;
      await stopped;

      await env.manager.start(_rule());
      await settle();
      expect(env.manager.isRunning('fwd-1'), isTrue);
      expect(env.manager.statusOf('fwd-1').phase, PortForwardPhase.running);
    });
  });

  group('PortForwardStatus', () {
    test('值语义：内容相同即相等，任一字段不同就不等', () {
      const base = PortForwardStatus(
        ruleId: 'fwd-1',
        phase: PortForwardPhase.running,
        boundPort: 8080,
      );
      const same = PortForwardStatus(
        ruleId: 'fwd-1',
        phase: PortForwardPhase.running,
        boundPort: 8080,
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);
      // 状态写入靠它做无变化守卫，漏掉任何一个字段都会让守卫失效。
      expect(base == const PortForwardStatus(ruleId: 'fwd-1'), isFalse);
      expect(
        base ==
            const PortForwardStatus(
              ruleId: 'fwd-1',
              phase: PortForwardPhase.running,
              boundPort: 8081,
            ),
        isFalse,
      );
      expect(
        base ==
            const PortForwardStatus(
              ruleId: 'fwd-1',
              phase: PortForwardPhase.failed,
              errorKind: ForwardErrorKind.refused,
              error: 'busy',
              boundPort: 8080,
            ),
        isFalse,
      );
    });
  });

  group('TerminalSession 与转发接线', () {
    test('连上后自动启动 autoStart 规则，断开时全部停掉', () async {
      final transport = FakeForwardTransport();
      final gateway = FakeTunnelGateway();
      final session = TerminalSession(
        server: SshServer(
          id: 'srv-1',
          group: 'g',
          name: 'host',
          host: '10.0.0.1',
          username: 'root',
          forwards: [
            _rule(id: 'auto', autoStart: true),
            _rule(id: 'manual', localPort: 8081),
          ],
        ),
        credentials: const SshCredentials(),
        transport: transport,
        tunnelGateway: gateway,
      );

      await session.start();
      await settle();
      expect(session.phase, TerminalPhase.connected);
      expect(session.forwards.runningIds, {'auto'});

      session.terminate();
      await settle();
      expect(session.forwards.runningIds, isEmpty);
      expect(gateway.listenerFor('127.0.0.1', 8080)!.closed, isTrue);
      session.dispose();
    });

    test('连接失败时不启动任何转发', () async {
      final transport = FakeForwardTransport()..connectOnAttach = false;
      final session = TerminalSession(
        server: SshServer(
          id: 'srv-1',
          group: 'g',
          name: 'host',
          host: '10.0.0.1',
          username: 'root',
          forwards: [_rule(id: 'auto', autoStart: true)],
        ),
        credentials: const SshCredentials(),
        transport: transport,
        tunnelGateway: FakeTunnelGateway(),
      );
      await session.start();
      expect(session.forwards.runningIds, isEmpty);
      session.dispose();
    });
  });
}
