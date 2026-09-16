import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models.dart';
import '../store.dart';
import 'host_key_store.dart';
import 'ssh_credentials.dart';
import 'terminal_session.dart';

typedef TerminalSessionFactory = TerminalSession Function(
  SshServer server,
  SshCredentials credentials,
);

/// 活跃 SSH 会话注册表（服务器 id → 会话），
/// 并把会话阶段同步为 [ServerStore] 中对应主机的展示状态。
final class SessionManager extends ChangeNotifier {
  SessionManager({
    required this.store,
    this.hostKeys,
    TerminalSessionFactory? sessionFactory,
  }) : _sessionFactory =
           sessionFactory ??
           ((server, credentials) => TerminalSession(
             server: server,
             credentials: credentials,
             hostKeys: hostKeys,
           ));

  final ServerStore store;

  /// TOFU 主机密钥指纹存储，随默认会话工厂下发到每个会话。
  final HostKeyStore? hostKeys;
  final TerminalSessionFactory _sessionFactory;
  final Map<String, TerminalSession> _sessions = {};

  List<TerminalSession> get sessions => List.unmodifiable(_sessions.values);

  int get sessionCount => _sessions.length;

  TerminalSession? byServerId(String? id) => id == null ? null : _sessions[id];

  /// 建立会话并开始连接；同主机已有活跃会话时直接复用。
  TerminalSession open(SshServer server, SshCredentials credentials) {
    final existing = _sessions[server.id];
    if (existing != null && existing.isActive) return existing;
    existing?.dispose();
    final session = _sessionFactory(server, credentials);
    // 阶段未变化的重复通知直接丢弃，减少下游列表 / 详情页无谓重建。
    var syncedPhase = session.phase;
    session.addListener(() {
      if (session.phase == syncedPhase) return;
      syncedPhase = session.phase;
      _syncStore(session);
    });
    _sessions[server.id] = session;
    store.markConnecting(server.id);
    notifyListeners();
    unawaited(session.start());
    return session;
  }

  /// 断开并移除会话，主机回到未连接状态。
  void close(String serverId) {
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

  /// 复用原凭据重连（失败或已结束的会话）。
  void retry(String serverId) {
    final previous = _sessions[serverId];
    if (previous == null || previous.isActive) return;
    final server = store.byId(serverId) ?? previous.server;
    _sessions.remove(serverId);
    previous.dispose();
    open(server, previous.credentials);
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
    for (final session in _sessions.values) {
      session
        ..terminate()
        ..dispose();
    }
    _sessions.clear();
    super.dispose();
  }
}
