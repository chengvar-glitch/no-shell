/// 详情视图「当前会话 + 会话条数」的无变化守卫，桌面端详情面板与移动端详情页
/// 共用同一套：切会话（[SessionManager.activate]）只发会话层的通知，store 的
/// 状态没变，光靠 store 那一路重建不起来，终端 / SFTP 就会停在旧会话上；
/// 而会话层的通知很密（终端输出、重连倒计时都会发），所以按这两个值做守卫——
/// 都没变就不 setState。
library;

import 'package:flutter/widgets.dart';

import '../ssh/session_manager.dart';
import '../ssh/terminal_session.dart';

mixin SessionSelectionGuard<T extends StatefulWidget> on State<T> {
  /// 要跟的会话注册表。
  SessionManager get guardedSessions;

  /// 要跟的主机 id。
  String get guardedServerId;

  int _syncedCount = 0;
  TerminalSession? _syncedActive;

  /// 开始守卫：在 [State.initState] 里调。
  void startSessionGuard() {
    _syncSessionSelection();
    guardedSessions.addListener(_onSessionsChanged);
  }

  /// 停止守卫：在 [State.dispose] 里调。
  void stopSessionGuard() {
    guardedSessions.removeListener(_onSessionsChanged);
  }

  /// 换了会话注册表：把监听从 [previous] 挪到当前那条，并重设基准。
  /// 在 [State.didUpdateWidget] 里按需调。
  void rebindSessionGuard(SessionManager previous) {
    previous.removeListener(_onSessionsChanged);
    startSessionGuard();
  }

  /// 换了主机：守卫的基准跟着换，否则会拿上一台的会话数做比较。
  void resyncSessionGuard() => _syncSessionSelection();

  void _syncSessionSelection() {
    _syncedCount = guardedSessions.sessionCountOf(guardedServerId);
    _syncedActive = guardedSessions.activeOf(guardedServerId);
  }

  void _onSessionsChanged() {
    final count = guardedSessions.sessionCountOf(guardedServerId);
    final active = guardedSessions.activeOf(guardedServerId);
    if (count == _syncedCount && identical(active, _syncedActive)) return;
    _syncedCount = count;
    _syncedActive = active;
    setState(() {});
  }
}
