import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../widgets/session_log_dialog.dart';
import '../widgets/status_badges.dart';
import 'session_manager.dart';
import 'terminal_view.dart';

/// 全屏终端页：从移动端会话列表进入，断开后自动退回。
/// 标题旁的状态胶囊是会话日志的入口，与详情页头部同一套交互。
final class SessionPage extends StatelessWidget {
  const SessionPage({
    super.key,
    required this.sessions,
    required this.serverId,
  });

  final SessionManager sessions;
  final String serverId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: sessions,
      builder: (context, _) {
        final session = sessions.activeOf(serverId);
        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    session?.server.name ??
                        sessions.store.byId(serverId)?.name ??
                        'SSH',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (session != null) ...[
                  const SizedBox(width: 8),
                  StatusPill(
                    status: serverStatusOf(session.phase),
                    onTap: () =>
                        showSessionLogDialog(context, session: session),
                  ),
                ],
              ],
            ),
            actions: [
              if (session != null)
                IconButton(
                  tooltip: l10n.disconnect,
                  icon: const Icon(Icons.link_off_rounded),
                  onPressed: () => sessions.closeAll(serverId),
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
