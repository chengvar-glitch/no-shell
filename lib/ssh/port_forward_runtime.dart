import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models.dart';
import 'ssh_transport.dart';
import 'tunnel_gateway.dart';

/// 一条转发规则的运行阶段。
enum PortForwardPhase {
  /// 未启动（用户没开，或会话还没建立）。
  stopped,
  starting,
  running,

  /// 启动失败；[PortForwardStatus.error] 带原因。
  failed,
}

/// 一条转发规则的运行状态。规则本身（地址 / 端口 / 自动启动）在
/// [PortForwardRule] 里，这里只放运行时才知道的东西。
final class PortForwardStatus {
  const PortForwardStatus({
    required this.ruleId,
    this.phase = PortForwardPhase.stopped,
    this.errorKind,
    this.error,
    this.boundPort,
  });

  final String ruleId;
  final PortForwardPhase phase;

  /// 失败原因归类；界面据此挑本地化文案。
  final ForwardErrorKind? errorKind;
  final String? error;

  /// 实际生效的端口：规则里写 0（由系统 / 服务端分配）时以这里为准。
  final int? boundPort;

  bool get isRunning => phase == PortForwardPhase.running;

  /// 值语义：运行时按它做无变化守卫，重复写同一个状态不该再通知一遍。
  @override
  bool operator ==(Object other) =>
      other is PortForwardStatus &&
      other.ruleId == ruleId &&
      other.phase == phase &&
      other.errorKind == errorKind &&
      other.error == error &&
      other.boundPort == boundPort;

  @override
  int get hashCode => Object.hash(ruleId, phase, errorKind, error, boundPort);
}

/// 一台主机上的端口转发运行时：把规则绑到该主机会话的传输层上。
///
/// 生命周期跟着会话走（与 SFTP 同样的取舍）：转发通道是已认证连接上的
/// channel，会话一断它们必然失效，因此没有「脱离会话独立运行的转发」。
///
/// [rules] 由调用方每次传入（而不是构造时快照）：规则可以在会话进行中编辑，
/// 启停的应当是用户当下看到的那一份。
final class PortForwardManager extends ChangeNotifier {
  PortForwardManager(this._transport, {TunnelGateway? gateway})
    : _gateway = gateway ?? createTunnelGateway();

  /// 转发要挂到哪条连接上；由 TerminalSession 传进来，与它同生共死。
  final SshTransport _transport;
  final TunnelGateway _gateway;

  final Map<String, _RunningForward> _running = {};
  final Map<String, PortForwardStatus> _statuses = {};

  /// 每条规则的启动代次：stop / stopAll 时 +1。start 在 await 归来后校验
  /// 代次——「starting」窗口可能横跨一次网络往返，这期间发生的 stop、
  /// stopAll、断开（stopAll）都靠它识别；否则在飞的 start 会把刚被停掉的
  /// 规则复活成 running（挂死在尸体会话上的「运行中」），或与并发 stop
  /// 交错出「监听真在跑、状态却是 failed、开关永远打不开」的死局。
  final Map<String, int> _generations = {};

  /// 所有已建立的连接，dispose 时一并销毁；管道自己结束时自行摘除。
  final Set<DuplexChannel> _liveChannels = {};

  bool _disposed = false;

  /// 已经启动的规则 id。
  Set<String> get runningIds => Set.unmodifiable(_running.keys);

  PortForwardStatus statusOf(String ruleId) =>
      _statuses[ruleId] ?? PortForwardStatus(ruleId: ruleId);

  bool isRunning(String ruleId) => _running.containsKey(ruleId);

  void _bumpGeneration(String ruleId) {
    _generations[ruleId] = (_generations[ruleId] ?? 0) + 1;
  }

  /// 启动一条转发；已在运行时是空操作（幂等，自动启动与用户点按都走它）。
  Future<void> start(PortForwardRule rule) async {
    if (_disposed) return;
    if (_running.containsKey(rule.id)) {
      // 已在跑还来 start：把状态校正成 running 再返回。不能静默早退——
      // 历史上可能残留一份过期的 failed 状态（与并发 stop 交错的结果），
      // 而入口守卫会挡住所有后续 start，开关就永远锁死在 failed 上。
      _setStatus(
        PortForwardStatus(
          ruleId: rule.id,
          phase: PortForwardPhase.running,
          boundPort: _running[rule.id]!.boundPort,
        ),
      );
      return;
    }
    if (!rule.isRunnable) {
      _fail(rule.id, ForwardErrorKind.other, 'Port forward rule is incomplete');
      return;
    }
    final generation = _generations[rule.id] ?? 0;
    _setStatus(
      PortForwardStatus(ruleId: rule.id, phase: PortForwardPhase.starting),
    );
    try {
      final running = switch (rule.mode) {
        PortForwardMode.local => await _startLocal(rule),
        PortForwardMode.remote => await _startRemote(rule),
        PortForwardMode.dynamic => await _startDynamic(rule),
      };
      // 启动是异步的：这期间用户可能已经断开（dispose 只看到 _running 里没有它），
      // 也可能已经把它停掉（代次变了）或另一个 start 已先落地。
      if (_disposed) {
        await running.shutdown();
        return;
      }
      if ((_generations[rule.id] ?? 0) != generation ||
          _running.containsKey(rule.id)) {
        await running.shutdown();
        return;
      }
      _running[rule.id] = running;
      _setStatus(
        PortForwardStatus(
          ruleId: rule.id,
          phase: PortForwardPhase.running,
          boundPort: running.boundPort,
        ),
      );
    } on Object catch (error) {
      // 代次已变（期间被停掉）：失败属于一个用户已经放弃的启动，别把
      // 停止后的干净状态又改写成 failed。
      if (_disposed || (_generations[rule.id] ?? 0) != generation) return;
      _fail(rule.id, forwardErrorFrom(error).kind, error.toString());
    }
  }

  /// 会话建立后按规则里的 autoStart 批量启动。
  void startAutoRules(Iterable<PortForwardRule> rules) {
    for (final rule in rules) {
      if (!rule.autoStart) continue;
      unawaited(start(rule));
    }
  }

  /// 停掉一条转发；没在跑时是空操作。状态回到「未启动」，
  /// 失败原因一并清掉——否则下次启动前会一直挂着上一次的报错。
  Future<void> stop(String ruleId) async {
    _bumpGeneration(ruleId);
    final running = _running.remove(ruleId);
    _setStatus(PortForwardStatus(ruleId: ruleId));
    await running?.shutdown();
  }

  /// 停掉全部转发（会话结束 / 断开时调用）。
  ///
  /// 自行汇总成一次通知，而不是逐条走 [_setStatus]：会话断开时要重置的规则
  /// 可能有好几条，逐条通知等于让转发面板连着重建好几遍。
  void stopAll() {
    // dispose 已经把在跑的与状态都收干净了：迟到的 stopAll（会话在回收之后
    // 才收到远端关闭）不该再往空表里写一遍。
    if (_disposed) return;
    final pending = _running.values.toList();
    // 在飞的 start 也要一并作废：连接刚建立就断开时，autoStart 的 bind
    // 还在路上，不 bump 代次它会把规则复活成挂死在尸体会话上的「运行中」。
    for (final ruleId in {..._running.keys, ..._statuses.keys}) {
      _bumpGeneration(ruleId);
    }
    _running.clear();
    var changed = false;
    for (final ruleId in _statuses.keys.toList()) {
      final reset = PortForwardStatus(ruleId: ruleId);
      if (_statuses[ruleId] == reset) continue;
      _statuses[ruleId] = reset;
      changed = true;
    }
    if (changed) notifyListeners();
    for (final running in pending) {
      unawaited(running.shutdown());
    }
    _destroyChannels();
  }

  /// 本地转发：本机监听，每个入站连接经 SSH 打开一条到目标的直连通道。
  Future<_RunningForward> _startLocal(PortForwardRule rule) async {
    final listener = await _gateway.listen(rule.localHost, rule.localPort);
    return _RunningForward(
      boundPort: listener.port,
      close: listener.close,
      subscription: listener.connections.listen(
        (inbound) => unawaited(
          _bridge(
            inbound,
            () =>
                _transport.openDirectChannel(rule.remoteHost, rule.remotePort),
          ),
        ),
        // 监听本身出错（套接字故障）只影响后续连接，已建立的连接照跑；
        // 这里不把整条规则判失败，用户看到的是端口仍然在监听。
        onError: (Object _) {},
      ),
    );
  }

  /// 远程转发：服务端监听，每个入站连接落到本机的目标地址。
  Future<_RunningForward> _startRemote(PortForwardRule rule) async {
    final listener = await _transport.openRemoteForward(
      host: rule.remoteHost,
      port: rule.remotePort,
    );
    return _RunningForward(
      boundPort: listener.port,
      close: listener.close,
      subscription: listener.connections.listen(
        (inbound) => unawaited(
          _bridge(inbound, () => _gateway.dial(rule.localHost, rule.localPort)),
        ),
        onError: (Object _) {},
      ),
    );
  }

  /// 动态转发：SOCKS5 由 dartssh2 在本地起，规则只给监听地址与端口。
  Future<_RunningForward> _startDynamic(PortForwardRule rule) async {
    final proxy = await _transport.openDynamicProxy(
      host: rule.localHost,
      port: rule.localPort,
    );
    return _RunningForward(boundPort: proxy.port, close: proxy.close);
  }

  /// 把一条入站连接接到它该去的另一端；另一端开不起来就断开入站连接
  /// （用户侧表现为「连上又立刻断」），而不是把这条转发整条判失败。
  Future<void> _bridge(
    DuplexChannel inbound,
    Future<DuplexChannel> Function() openOther,
  ) async {
    if (_disposed) {
      inbound.destroy();
      return;
    }
    final DuplexChannel other;
    try {
      other = await openOther();
    } on Object {
      inbound.destroy();
      return;
    }
    if (_disposed) {
      inbound.destroy();
      other.destroy();
      return;
    }
    _pipe(inbound, other);
  }

  /// 把两条通道对接起来：任一方向结束 / 出错就把两条都关掉。
  void _pipe(DuplexChannel local, DuplexChannel remote) {
    _liveChannels
      ..add(local)
      ..add(remote);
    var closed = false;
    late final StreamSubscription<List<int>> up;
    late final StreamSubscription<List<int>> down;

    Future<void> shutdown() async {
      if (closed) return;
      closed = true;
      _liveChannels
        ..remove(local)
        ..remove(remote);
      await up.cancel();
      await down.cancel();
      await local.close();
      await remote.close();
    }

    up = local.stream.listen(
      remote.write,
      onDone: () => unawaited(shutdown()),
      onError: (Object _) => unawaited(shutdown()),
      cancelOnError: true,
    );
    down = remote.stream.listen(
      local.write,
      onDone: () => unawaited(shutdown()),
      onError: (Object _) => unawaited(shutdown()),
      cancelOnError: true,
    );
  }

  void _destroyChannels() {
    for (final channel in _liveChannels.toList()) {
      channel.destroy();
    }
    _liveChannels.clear();
  }

  void _fail(String ruleId, ForwardErrorKind kind, String detail) {
    if (_disposed) return;
    _setStatus(
      PortForwardStatus(
        ruleId: ruleId,
        phase: PortForwardPhase.failed,
        errorKind: kind,
        error: detail,
      ),
    );
  }

  void _setStatus(PortForwardStatus status) {
    if (_disposed) return;
    // 无变化守卫：启动流程会在几个阶段间反复写状态，重复写同一个值不该
    // 让订阅方重建一遍（与 AppSettings / TerminalStylePrefs 同一套约定）。
    if (_statuses[status.ruleId] == status) return;
    _statuses[status.ruleId] = status;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final pending = _running.values.toList();
    _running.clear();
    _statuses.clear();
    for (final running in pending) {
      unawaited(running.shutdown());
    }
    _destroyChannels();
    super.dispose();
  }
}

/// 一条已启动的转发：关闭句柄 + 入站连接订阅。
final class _RunningForward {
  _RunningForward({
    required this.boundPort,
    required this.close,
    this.subscription,
  });

  /// 实际生效的端口；规则里写 0 时才有别于规则值。
  final int? boundPort;

  /// 关掉监听 / 代理本身。
  final Future<void> Function() close;

  /// 入站连接的订阅；动态转发没有（SOCKS 握手由 dartssh2 自己处理）。
  final StreamSubscription<DuplexChannel>? subscription;

  /// 先停止接收新连接，再关掉监听本身；已建立的连接由 [_pipe] 自行收尾。
  ///
  /// 不 await `cancel()`：它要等底层流把取消处理完，而「不再收新连接」在
  /// 调用返回时就已经生效。等它会把这个动作拖在事件循环上——用户点了停止，
  /// 界面上的开关先变了、监听却还开着（测试里那一下就看得很清楚）。
  Future<void> shutdown() async {
    final pending = subscription?.cancel();
    if (pending != null) unawaited(pending.catchError((Object _) {}));
    await close();
  }
}
