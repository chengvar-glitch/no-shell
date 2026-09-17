import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:xterm/core.dart';

import '../models.dart';
import '../store.dart';
import 'auto_reconnect.dart';
import 'host_key_store.dart';
import 'jump_host.dart';
import 'ssh_agent.dart';
import 'ssh_credentials.dart';
import 'ssh_transport.dart';
import 'terminal_session.dart';

typedef TerminalSessionFactory = TerminalSession Function(
  SshServer server,
  SshCredentials credentials,
  List<SshHop> jumps,
);

/// 逐跳 agent 探针：这一跳没存过凭据时，静默试本机 agent 的钥匙——
/// 能过认证就返回要用的凭据，不能（或本机没有 agent）返回 null。
/// 生产实现见 [_defaultHopAgentProbe]；测试注入假探针即可驱动跳板链路。
typedef HopAgentProbe = Future<SshCredentials?> Function(
  SshServer server,
  List<SshHop> upstream,
);

/// 「本机 agent 是否可用且有钥匙」的探针：连接流程在弹凭据框前先问它，
/// 有钥匙才值得发起一次静默的 agent 认证。纯本地检查，不联网。
/// 默认连真实的 SSH_AUTH_SOCK；测试注入假探针保持确定性。
typedef AgentKeysProbe = Future<bool> Function();

Future<bool> _defaultAgentKeysProbe() async {
  if (!sshAgentSupported) return false;
  final SshAgentClient agent;
  try {
    agent = await connectSshAgent();
  } on Object {
    return false;
  }
  try {
    return (await agent.listIdentities()).isNotEmpty;
  } on Object {
    return false;
  } finally {
    await agent.close();
  }
}

/// 活跃 SSH 会话注册表（服务器 id → 会话），
/// 并把会话阶段同步为 [ServerStore] 中对应主机的展示状态。
final class SessionManager extends ChangeNotifier {
  SessionManager({
    required this.store,
    this.hostKeys,
    this.allowLegacyHostKeys = false,
    TerminalSessionFactory? sessionFactory,
    AgentKeysProbe? agentKeysProbe,
    HopAgentProbe? hopAgentProbe,
    this.autoReconnect = false,
    this.backoff = const ReconnectBackoff(),
  }) : _sessionFactory =
           sessionFactory ??
           // 闭包读取的是**实例字段**（初始化形参不留同名局部变量，
           // 没有遮蔽）：用户改完设置后新建的会话才带得上新取值。
           ((server, credentials, jumps) => TerminalSession(
             server: server,
             credentials: credentials,
             hostKeys: hostKeys,
             allowLegacyHostKeys: allowLegacyHostKeys,
             jumps: jumps,
           )),
       agentKeysProbe = agentKeysProbe ?? _defaultAgentKeysProbe,
       _injectedHopProbe = hopAgentProbe;

  /// 连接老设备时是否允许 `ssh-rsa`（SHA-1）主机密钥；设置面板可改。
  ///
  /// 刻意是可变字段：默认会话工厂的闭包引用它，改完设置后新建的会话
  /// 才会带上新取值（已建立的连接不受影响）。
  bool allowLegacyHostKeys;

  /// 会话意外断开后是否按 [backoff] 指数退避自动重连（空闲重连）。
  /// 默认关闭：测试注入的假传输不能凭空长出新会话；应用入口显式打开。
  final bool autoReconnect;

  /// 自动重连的退避节奏；测试可注入更快的节奏保持确定性。
  final ReconnectBackoff backoff;

  final ServerStore store;

  /// TOFU 主机密钥指纹存储，随默认会话工厂下发到每个会话。
  final HostKeyStore? hostKeys;

  /// 「本机 agent 是否可用且有钥匙」的探针；连接流程弹凭据框前先问它，
  /// 有钥匙才发起静默的 agent 认证（无感连接）。测试注入假探针。
  final AgentKeysProbe agentKeysProbe;

  /// 逐跳 agent 探针；生产实现先过 [agentKeysProbe] 再发起裸传输认证
  /// （不建会话、不动界面），测试注入假探针。
  late final HopAgentProbe hopAgentProbe =
      _injectedHopProbe ?? _defaultHopAgentProbe;
  final HopAgentProbe? _injectedHopProbe;

  Future<SshCredentials?> _defaultHopAgentProbe(
    SshServer server,
    List<SshHop> upstream,
  ) async {
    if (!await agentKeysProbe()) return null;
    final transport = createSshTransport(
      server,
      const SshCredentials(useAgent: true),
      hostKeys,
      allowLegacyHostKeys: allowLegacyHostKeys,
      jumps: upstream,
    );
    final terminal = Terminal(maxLines: 64);
    try {
      await transport.attach(terminal, onConnected: () {}, onClosed: () {});
      return const SshCredentials(useAgent: true);
    } on Object {
      return null;
    } finally {
      transport.dispose();
    }
  }

  final TerminalSessionFactory _sessionFactory;
  final Map<String, TerminalSession> _sessions = {};

  /// 待执行的自动重连计划（主机 id → 尝试号与计时器）。
  /// 有条目即代表「这条会话是断线自动重连流程的一部分」。
  final Map<String, _PendingReconnect> _reconnects = {};

  List<TerminalSession> get sessions => List.unmodifiable(_sessions.values);

  int get sessionCount => _sessions.length;

  TerminalSession? byServerId(String? id) => id == null ? null : _sessions[id];

  /// 该主机挂着的自动重连计划；没有则为 null。
  /// 界面据此展示「将在 N 秒后重连（第 X 次）」。
  ReconnectPlan? reconnectPlanOf(String? id) {
    final pending = id == null ? null : _reconnects[id];
    if (pending == null) return null;
    return ReconnectPlan(attempt: pending.attempt, delay: pending.delay);
  }

  /// 停止该主机的自动重连：已断开的会话与错误现场原样保留，交给用户处置。
  void cancelAutoReconnect(String serverId) {
    if (_reconnects.remove(serverId) == null) return;
    notifyListeners();
  }

  /// 建立会话并开始连接；同主机已有活跃会话时直接复用。
  /// [jumps] 为跳板机链路（由外到内），随会话一起记住，重连时原样复用。
  TerminalSession open(
    SshServer server,
    SshCredentials credentials, {
    List<SshHop> jumps = const [],
  }) {
    // 用户亲自发起的连接：挂着的自动重连就此作废，控制权移交。
    _reconnects.remove(server.id)?.cancel();
    final existing = _sessions[server.id];
    if (existing != null && existing.isActive) return existing;
    existing?.dispose();
    return _spawn(server, credentials, jumps);
  }

  /// 断开并移除会话，主机回到未连接状态。
  void close(String serverId) {
    _reconnects.remove(serverId)?.cancel();
    final session = _sessions.remove(serverId);
    if (session == null) return;
    final wasActive = session.isActive;
    session.terminate();
    session.dispose();
    store.markIdle(serverId);
    // 活跃会话在 terminate 时已经过监听同步并通知过一次，无需重复通知。
    if (wasActive) return;
    notifyListeners();
  }

  /// 复用原凭据重连（失败或已结束的会话）；跳板机链路也照旧。
  void retry(String serverId) {
    // 手动重连同样是用户接管，退避计划作废（含计时器）。
    _reconnects.remove(serverId)?.cancel();
    final previous = _sessions[serverId];
    if (previous == null || previous.isActive) return;
    final server = store.byId(serverId) ?? previous.server;
    _sessions.remove(serverId);
    previous.dispose();
    _spawn(server, previous.credentials, previous.jumps);
  }

  /// 实际创建并登记会话；[open] / [retry] / 自动重连共用，
  /// 只有前两者该先清退避计划。
  TerminalSession _spawn(
    SshServer server,
    SshCredentials credentials,
    List<SshHop> jumps,
  ) {
    final session = _sessionFactory(server, credentials, jumps);
    // 阶段未变化的重复通知直接丢弃，减少下游列表 / 详情页无谓重建。
    var syncedPhase = session.phase;
    session.addListener(() {
      if (session.phase == syncedPhase) return;
      syncedPhase = session.phase;
      _syncStore(session);
      _onPhase(session);
    });
    _sessions[server.id] = session;
    store.markConnecting(server.id);
    notifyListeners();
    unawaited(session.start());
    return session;
  }

  /// 会话进入新阶段后维护自动重连的状态机。
  void _onPhase(TerminalSession session) {
    switch (session.phase) {
      case TerminalPhase.connected:
        // 重连成功：计数与计划一并清掉。
        if (_reconnects.remove(session.server.id) != null) notifyListeners();
      case TerminalPhase.closed:
        _scheduleAfterDrop(session);
      case TerminalPhase.failed:
        _afterFailedAttempt(session);
      case TerminalPhase.connecting:
        break;
    }
  }

  /// 会话意外断开（connected → closed）：排下一次退避重连。
  void _scheduleAfterDrop(TerminalSession session) {
    if (!autoReconnect) return;
    // 还在注册表里的会话才是意外断开；用户主动 close() 时已先移除。
    if (!identical(_sessions[session.server.id], session)) return;
    _schedule(
      session.server.id,
      (_reconnects[session.server.id]?.attempt ?? 0) + 1,
    );
  }

  /// 自动重连的一次尝试失败：暂时性错误接着退避，其余（认证 / 指纹 /
  /// 链路配置）重试也不会好，停下来把错误现场交还用户。
  void _afterFailedAttempt(TerminalSession session) {
    final pending = _reconnects[session.server.id];
    if (pending == null) return;
    if (_isTransient(session.errorKind)) {
      _schedule(session.server.id, pending.attempt + 1);
    } else {
      _reconnects.remove(session.server.id);
      notifyListeners();
    }
  }

  /// 断网、服务器暂时不在：值得再敲一次门。连接被拒这类原始套接字错误
  /// 没有更细的归类，落在 [TerminalErrorKind.other] 里，也算暂时性。
  static bool _isTransient(TerminalErrorKind kind) =>
      kind == TerminalErrorKind.network || kind == TerminalErrorKind.other;

  void _schedule(String serverId, int attempt) {
    final delay = backoff.delayFor(attempt);
    _reconnects.remove(serverId)?.cancel();
    final timer = Timer(delay, () => _fireReconnect(serverId, attempt));
    _reconnects[serverId] = _PendingReconnect(
      attempt: attempt,
      delay: delay,
      timer: timer,
    );
    // 不再主动 notify：调用点都在会话阶段回调里，_syncStore 刚通知过，
    // 下游重建时读到的就是新计划。
  }

  /// 退避到期，发起第 [attempt] 次重连：换新传输、复用原凭据与跳板链路。
  void _fireReconnect(String serverId, int attempt) {
    final pending = _reconnects[serverId];
    if (pending == null || pending.attempt != attempt) return;
    final session = _sessions[serverId];
    if (session == null || session.isActive) {
      _reconnects.remove(serverId);
      return;
    }
    final server = store.byId(serverId) ?? session.server;
    _sessions.remove(serverId);
    session.dispose();
    // 先把这次尝试的号带过去再 spawn：新会话若同步就进入终态，
    // 阶段回调能接着这个条目清计划或续退避，不会漏掉计数。
    _reconnects[serverId] = _PendingReconnect(
      attempt: attempt,
      delay: backoff.delayFor(attempt),
    );
    _spawn(server, session.credentials, session.jumps);
  }

  void _syncStore(TerminalSession session) {
    switch (session.phase) {
      case TerminalPhase.connecting:
        store.markConnecting(session.server.id);
      case TerminalPhase.connected:
        store.markConnected(session.server.id);
      case TerminalPhase.failed:
        store.markError(session.server.id);
      case TerminalPhase.closed:
        store.markIdle(session.server.id);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final pending in _reconnects.values) {
      pending.cancel();
    }
    _reconnects.clear();
    for (final session in _sessions.values) {
      session
        ..terminate()
        ..dispose();
    }
    _sessions.clear();
    super.dispose();
  }
}

/// 一条待执行的自动重连：第 [attempt] 次（从 1 计），[timer] 到点发起。
/// [delay] 是当时算出的等待时长，与尝试号一起构成界面上展示的计划。
/// 计时器只在等待期间存在；尝试发起后条目仅剩计数职责。
final class _PendingReconnect {
  _PendingReconnect({required this.attempt, required this.delay, this.timer});

  final int attempt;
  final Duration delay;
  final Timer? timer;

  void cancel() {
    timer?.cancel();
  }
}
