import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../widgets/session_menu.dart';
import '../widgets/status_badges.dart';
import 'connect_flow.dart';
import 'credential_store.dart';
import 'session_manager.dart';
import 'terminal_view.dart';

/// 全屏终端页：从移动端会话列表进入，断开后自动退回。
/// 标题旁的状态胶囊点开是会话日志（多开了才换成会话菜单：切会话 / 新建会话 /
/// 日志），与桌面详情头部、移动端主机详情页同一套规则（见 [openSessionPill]）。
final class SessionPage extends StatefulWidget {
  const SessionPage({
    super.key,
    required this.sessions,
    required this.serverId,
    required this.credentials,
  });

  final SessionManager sessions;
  final String serverId;

  /// 「新建会话」要按连接流程再取一次凭据（存档 / 现存会话 / agent / 弹窗）。
  final CredentialStore credentials;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  /// 胶囊自己的 key：会话菜单锚在它下方（与桌面头部同一套锚法）。
  final GlobalKey _pillKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sessions = widget.sessions;
    final store = sessions.store;
    return ListenableBuilder(
      listenable: sessions,
      builder: (context, _) {
        final session = sessions.activeOf(widget.serverId);
        final server = store.byId(widget.serverId);
        final count = sessions.sessionsOf(widget.serverId).length;
        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    session?.server.name ?? server?.name ?? 'SSH',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (session != null) ...[
                  const SizedBox(width: 8),
                  StatusPill(
                    key: _pillKey,
                    status: serverStatusOf(session.phase),
                    // 多开了才显示计数：一条会话时胶囊的外观与多会话功能
                    // 之前完全一样。
                    sessionCount: count,
                    tooltip: count > 1 ? l10n.sessionMenu : null,
                    onTap: server == null
                        ? null
                        : () => openSessionPill(
                            context,
                            sessions: sessions,
                            server: server,
                            anchor: _pillKey,
                            onNewSession: () => newSessionFlow(
                              context,
                              sessions: sessions,
                              server: server,
                              credentials: widget.credentials,
                              store: store,
                            ),
                          ),
                  ),
                ],
              ],
            ),
            actions: [
              if (session != null)
                IconButton(
                  tooltip: l10n.disconnect,
                  icon: const Icon(Icons.link_off_rounded),
                  onPressed: () => sessions.closeAll(widget.serverId),
                ),
            ],
          ),
          body: SafeArea(
            child: session == null
                ? Center(child: Text(l10n.sessionClosedMsg))
                : SshTerminalView(
                    session: session,
                    onRetry: () => sessions.retry(session),
                    reconnectPlan: sessions.reconnectPlanOf(session),
                    onStopAutoReconnect: () =>
                        sessions.cancelAutoReconnect(session),
                  ),
          ),
        );
      },
    );
  }
}
