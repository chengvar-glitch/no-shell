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

/// 活跃 SSH 会话注册表，并把会话阶段同步为 [ServerStore] 中对应主机的展示状态。
///
/// **一台主机可以挂多条会话**（同一台服务器多开终端）：每条会话是各自独立的
/// 连接与认证，各自带自己的终端缓冲区、SFTP 通道与转发运行时。界面绑定的是
/// 该主机的**当前会话**（[activeOf]），主机行上的状态是全部会话的聚合
/// （[ServerStatus.connected] 优先，其次 connecting / error / idle）。
///
/// 会话以**对象身份**定位（[TerminalSession] 没有 `==` 重载，天生按引用相等），
/// 展示编号由本类维护：一台主机内单调递增、**永不复用**，重连 / [retry] 也不
/// 改变编号，因此 [byOrdinal] 是一条会话的稳定地址（全屏终端页路由用它，
/// 重连换了对象也还能找回来）。
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
  }) : agentKeysProbe = agentKeysProbe ?? _defaultAgentKeysProbe,
       _injectedHopProbe = hopAgentProbe {
    // 工厂必须在构造体里赋值：初始化列表中的闭包引用不到实例字段
    // （Dart 在初始化列表里禁用 this），裸名解析成初始化形参、捕获的是
    // 构造实参快照——设置改动后新建会话就带不上新取值。构造体里
    // `allowLegacyHostKeys` / `hostKeys` 解析为字段本身，调用时才读。
    _sessionFactory =
        sessionFactory ??
        ((server, credentials, jumps) => TerminalSession(
          server: server,
          credentials: credentials,
          hostKeys: hostKeys,
          allowLegacyHostKeys: allowLegacyHostKeys,
          jumps: jumps,
        ));
  }

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
    } on HostKeyChangedException {
      // 指纹不符与「agent 没有钥匙」是两回事：吞掉它，连接流程就会先弹
      // 跳板机密码框、用户输完才看到「疑似中间人」。原样抛给调用方处置。
      rethrow;
    } on HostKeyUnavailableException {
      // 指纹存档读不出来必须 fail closed：同样不能伪装成「没钥匙」。
      rethrow;
    } on Object {
      return null;
    } finally {
      transport.dispose();
    }
  }

  /// 延迟到构造体里赋值（见构造函数）：工厂闭包必须读实例字段，而
  /// 初始化列表里引用不到 this。`late final` 允许在构造体里完成这一次赋值。
  late final TerminalSessionFactory _sessionFactory;

  /// 主机 id → 会话列表（创建顺序，也就是界面上会话菜单的顺序）。
  /// 主机没有会话时整个条目被移除，[sessions] 的顺序因此是「主机首次出现的
  /// 顺序 + 主机内创建顺序」。
  final Map<String, List<TerminalSession>> _byServer = {};

  /// 主机 id → 当前会话（界面绑定的那一条）。列表非空时它必然有值。
  final Map<String, TerminalSession> _active = {};

  /// 会话 → 展示编号（从 1 起）。以对象身份为键。
  final Map<TerminalSession, int> _ordinals = {};

  /// 主机 id → 下一个要分配的编号；只增不减，编号因此永不复用。
  final Map<String, int> _nextOrdinal = {};

  /// 阶段监听器登记表：关闭会话时先摘掉监听再 terminate，
  /// 免得「用户点关闭」这条路径上被 terminate 的阶段回调多通知一次。
  final Map<TerminalSession, VoidCallback> _phaseListeners = {};

  /// 待执行的自动重连计划（会话 → 尝试号与计时器）。
  /// 有条目即代表「这条会话是断线自动重连流程的一部分」。
  final Map<TerminalSession, _PendingReconnect> _reconnects = {};

  /// 全部会话：按主机首次出现顺序、主机内按创建顺序。
  List<TerminalSession> get sessions =>
      List.unmodifiable([for (final list in _byServer.values) ...list]);

  int get sessionCount => _ordinals.length;

  /// 某台主机的会话（创建顺序）。
  List<TerminalSession> sessionsOf(String? serverId) {
    final list = serverId == null ? null : _byServer[serverId];
    return list == null ? const [] : List.unmodifiable(list);
  }

  int sessionCountOf(String? serverId) =>
      serverId == null ? 0 : (_byServer[serverId]?.length ?? 0);

  /// 某台主机的**当前会话**：终端 / SFTP / 转发 / 会话日志都绑定它。
  /// 可能是失败的或已结束的会话——是否活跃看 [TerminalSession.isActive]。
  TerminalSession? activeOf(String? serverId) =>
      serverId == null ? null : _active[serverId];

  /// 按编号取会话。编号在一台主机内唯一且不复用，重连 / [retry] 也不变，
  /// 因此它是一条会话的稳定地址。
  TerminalSession? byOrdinal(String serverId, int ordinal) {
    for (final session in _byServer[serverId] ?? const <TerminalSession>[]) {
      if (_ordinals[session] == ordinal) return session;
    }
    return null;
  }

  /// 会话的展示编号（从 1 起）；不是本管理器登记的会话返回 0。
  int ordinalOf(TerminalSession session) => _ordinals[session] ?? 0;

  /// 该主机是否存在认证失败现场。连接流程据此不再静默复用存档凭据，
  /// 而是直接把预填的凭据框交给用户。
  bool hasAuthFailure(String serverId) =>
      (_byServer[serverId] ?? const <TerminalSession>[]).any(
        (session) =>
            session.phase == TerminalPhase.failed &&
            session.errorKind == TerminalErrorKind.auth,
      );

  /// 把某台主机的当前会话切到 [session]；不是它登记的会话时不作声。
  void activate(TerminalSession session) {
    final serverId = session.server.id;
    if (!(_byServer[serverId]?.contains(session) ?? false)) return;
    if (identical(_active[serverId], session)) return;
    _active[serverId] = session;
    notifyListeners();
  }

  /// 该主机挂着的自动重连计划；没有则为 null。
  /// 界面据此展示「将在 N 秒后重连（第 X 次）」。
  ReconnectPlan? reconnectPlanOf(TerminalSession? session) {
    final pending = session == null ? null : _reconnects[session];
    if (pending == null) return null;
    return ReconnectPlan(attempt: pending.attempt, delay: pending.delay);
  }

  /// 停止该会话的自动重连：已断开的会话与错误现场原样保留，交给用户处置。
  void cancelAutoReconnect(TerminalSession session) {
    if (_reconnects.remove(session) == null) return;
    notifyListeners();
  }

  /// 建立会话并开始连接；该主机已有活跃会话时直接复用（连接按钮的语义）。
  /// 当前会话已是终态（失败 / 已结束）时就地重开它，编号与位置都不变。
  /// [jumps] 为跳板机链路（由外到内），随会话一起记住，重连时原样复用。
  TerminalSession open(
    SshServer server,
    SshCredentials credentials, {
    List<SshHop> jumps = const [],
  }) {
    final current = _active[server.id];
    if (current == null) return _spawn(server, credentials, jumps);
    // 用户亲自发起的连接：这条会话挂着的自动重连就此作废，控制权移交。
    // 只作废它自己的计划——同主机其它会话的重连是它们自己的事。
    _cancelReconnectOf(current);
    if (current.isActive) return current;
    return _respawn(current, server, credentials, jumps);
  }

  /// 在同一台主机上**再开一条会话**（多开终端）：总是新建，成为当前会话，
  /// 并分配一个新编号。不碰同主机其它会话的自动重连计划。
  TerminalSession openNew(
    SshServer server,
    SshCredentials credentials, {
    List<SshHop> jumps = const [],
  }) => _spawn(server, credentials, jumps);

  /// 断开并移除某一条会话；它是当前会话时，当前身份交给相邻的一条
  /// （同下标优先，否则前一条）。主机没有会话了便回到未连接状态。
  void closeSession(TerminalSession session) {
    final serverId = session.server.id;
    final list = _byServer[serverId];
    final index = list?.indexOf(session) ?? -1;
    if (list == null || index == -1) return;
    list.removeAt(index);
    _discard(session);
    _ordinals.remove(session);
    _cancelReconnectOf(session);
    if (identical(_active[serverId], session)) {
      // 关掉的是当前会话：交给相邻的一条（同下标优先，否则前一条）；
      // 一条都不剩就把当前身份一并抹掉。
      if (list.isEmpty) {
        _active.remove(serverId);
      } else {
        _active[serverId] = list[index < list.length ? index : list.length - 1];
      }
    }
    _prune(serverId);
    _syncStore(serverId);
    notifyListeners();
  }

  /// 断开并移除该主机的全部会话（「断开连接 / 断开全部」与删除主机）。
  void closeAll(String serverId) {
    final list = _byServer.remove(serverId);
    _active.remove(serverId);
    _nextOrdinal.remove(serverId);
    if (list == null || list.isEmpty) return;
    for (final session in list) {
      _discard(session);
      _ordinals.remove(session);
      _cancelReconnectOf(session);
    }
    store.markIdle(serverId);
    notifyListeners();
  }

  /// 复用原凭据与跳板链路重连某条会话；编号、列表位置与当前身份都保持。
  /// 不是本管理器登记的会话、或它还是活跃的，都返回 null。
  TerminalSession? retry(TerminalSession session) {
    final serverId = session.server.id;
    if (!(_byServer[serverId]?.contains(session) ?? false)) return null;
    _cancelReconnectOf(session);
    if (session.isActive) return null;
    final server = store.byId(serverId) ?? session.server;
    return _respawn(session, server, session.credentials, session.jumps);
  }

  /// 该主机的聚合状态：连上一条就算连上，正在连的优先于失败的。
  ServerStatus _aggregateOf(String serverId) {
    final list = _byServer[serverId] ?? const <TerminalSession>[];
    if (list.any((session) => session.phase == TerminalPhase.connected)) {
      return ServerStatus.connected;
    }
    if (list.any((session) => session.phase == TerminalPhase.connecting)) {
      return ServerStatus.connecting;
    }
    if (list.any((session) => session.phase == TerminalPhase.failed)) {
      return ServerStatus.error;
    }
    return ServerStatus.idle;
  }

  /// 新建一条会话并登记：分配编号、成为当前会话、开始连接。
  TerminalSession _spawn(
    SshServer server,
    SshCredentials credentials,
    List<SshHop> jumps,
  ) {
    final session = _create(server, credentials, jumps);
    final list = _byServer.putIfAbsent(server.id, () => []);
    list.add(session);
    final ordinal = (_nextOrdinal[server.id] ?? 0) + 1;
    _nextOrdinal[server.id] = ordinal;
    _ordinals[session] = ordinal;
    _active[server.id] = session;
    store.markConnecting(server.id);
    notifyListeners();
    unawaited(session.start());
    return session;
  }

  /// 用新传输就地重开一条会话：编号、在列表中的位置、当前身份全部沿用，
  /// 因此界面上不会「换了个会话」。[reconnect] 非空时在 start 之前就把退避
  /// 计划挂到新会话上——新会话同步进入终态时，阶段回调能接着这个条目计数。
  TerminalSession _respawn(
    TerminalSession previous,
    SshServer server,
    SshCredentials credentials,
    List<SshHop> jumps, {
    _PendingReconnect? reconnect,
  }) {
    final serverId = server.id;
    final list = _byServer[serverId];
    final index = list?.indexOf(previous) ?? -1;
    // 已经不在注册表里（会话被关掉 / 主机被删）：按新建处理，别复活它。
    if (list == null || index == -1) return _spawn(server, credentials, jumps);
    final ordinal = _ordinals[previous] ?? 0;
    final wasActive = identical(_active[serverId], previous);
    _discard(previous);
    _ordinals.remove(previous);
    final session = _create(server, credentials, jumps);
    list[index] = session;
    if (ordinal != 0) _ordinals[session] = ordinal;
    if (wasActive) _active[serverId] = session;
    if (reconnect != null) _reconnects[session] = reconnect;
    store.markConnecting(serverId);
    notifyListeners();
    unawaited(session.start());
    return session;
  }

  /// 建会话对象并挂上阶段监听。阶段未变化的重复通知直接丢弃，
  /// 减少下游列表 / 详情页无谓重建。
  TerminalSession _create(
    SshServer server,
    SshCredentials credentials,
    List<SshHop> jumps,
  ) {
    final session = _sessionFactory(server, credentials, jumps);
    var syncedPhase = session.phase;
    void listener() {
      if (session.phase == syncedPhase) return;
      syncedPhase = session.phase;
      _syncStore(session.server.id);
      notifyListeners();
      _onPhase(session);
    }

    _phaseListeners[session] = listener;
    session.addListener(listener);
    return session;
  }

  /// 摘掉阶段监听并结束一条会话。先摘监听：调用方（关闭 / 就地重开）随后
  /// 自己发通知，不能让 terminate 的阶段回调再插一次。
  void _discard(TerminalSession session) {
    final listener = _phaseListeners.remove(session);
    if (listener != null) session.removeListener(listener);
    session
      ..terminate()
      ..dispose();
  }

  /// 主机没有会话了就清掉它的簿记（编号计数一并抹掉：重新连上就是新的一轮）。
  void _prune(String serverId) {
    if (_byServer[serverId]?.isNotEmpty ?? false) return;
    _byServer.remove(serverId);
    _active.remove(serverId);
    _nextOrdinal.remove(serverId);
  }

  /// 会话进入新阶段后维护自动重连的状态机。
  void _onPhase(TerminalSession session) {
    switch (session.phase) {
      case TerminalPhase.connected:
        // 重连成功：计数与计划一并清掉。
        if (_reconnects.remove(session) != null) notifyListeners();
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
    // 还在注册表里的会话才是意外断开；用户主动关闭时已先移除。
    if (!(_byServer[session.server.id]?.contains(session) ?? false)) return;
    _schedule(session, (_reconnects[session]?.attempt ?? 0) + 1);
  }

  /// 自动重连的一次尝试失败：暂时性错误接着退避，其余（认证 / 指纹 /
  /// 链路配置）重试也不会好，停下来把错误现场交还用户。
  void _afterFailedAttempt(TerminalSession session) {
    final pending = _reconnects[session];
    if (pending == null) return;
    if (_isTransient(session.errorKind)) {
      _schedule(session, pending.attempt + 1);
    } else {
      _reconnects.remove(session);
      notifyListeners();
    }
  }

  /// 断网、服务器暂时不在：值得再敲一次门。连接被拒这类原始套接字错误
  /// 没有更细的归类，落在 [TerminalErrorKind.other] 里，也算暂时性。
  static bool _isTransient(TerminalErrorKind kind) =>
      kind == TerminalErrorKind.network || kind == TerminalErrorKind.other;

  void _schedule(TerminalSession session, int attempt) {
    final delay = backoff.delayFor(attempt);
    _reconnects.remove(session)?.cancel();
    final timer = Timer(delay, () => _fireReconnect(session, attempt));
    _reconnects[session] = _PendingReconnect(
      attempt: attempt,
      delay: delay,
      timer: timer,
    );
    // 不再主动 notify：调用点都在会话阶段回调里，_syncStore 刚通知过，
    // 下游重建时读到的就是新计划。
  }

  /// 退避到期，发起第 [attempt] 次重连：换新传输、复用原凭据与跳板链路。
  void _fireReconnect(TerminalSession session, int attempt) {
    final pending = _reconnects[session];
    if (pending == null || pending.attempt != attempt) return;
    if (session.isActive ||
        !(_byServer[session.server.id]?.contains(session) ?? false)) {
      _reconnects.remove(session);
      return;
    }
    final server = store.byId(session.server.id) ?? session.server;
    // 计划先摘下来再交给新会话：_respawn 会在 start 之前把它挂回去，
    // 新会话若同步进入终态，阶段回调能接着这个计数走，不会漏掉尝试号。
    _reconnects.remove(session);
    _respawn(
      session,
      server,
      session.credentials,
      session.jumps,
      reconnect: _PendingReconnect(
        attempt: attempt,
        delay: backoff.delayFor(attempt),
      ),
    );
  }

  void _cancelReconnectOf(TerminalSession session) {
    _reconnects.remove(session)?.cancel();
  }

  void _syncStore(String serverId) {
    switch (_aggregateOf(serverId)) {
      case ServerStatus.connecting:
        store.markConnecting(serverId);
      case ServerStatus.connected:
        store.markConnected(serverId);
      case ServerStatus.error:
        store.markError(serverId);
      case ServerStatus.idle:
        store.markIdle(serverId);
    }
  }

  @override
  void dispose() {
    for (final pending in _reconnects.values) {
      pending.cancel();
    }
    _reconnects.clear();
    for (final list in _byServer.values) {
      for (final session in list) {
        _discard(session);
      }
    }
    _byServer.clear();
    _active.clear();
    _ordinals.clear();
    _nextOrdinal.clear();
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
