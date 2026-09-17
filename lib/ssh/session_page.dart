import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import 'session_manager.dart';
import 'terminal_view.dart';

/// 全屏终端页：从移动端会话列表进入，断开后自动退回。
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
        final session = sessions.byServerId(serverId);
        return Scaffold(
          appBar: AppBar(
            title: Text(
              session?.server.name ??
                  sessions.store.byId(serverId)?.name ??
                  'SSH',
            ),
            actions: [
              if (session != null)
                IconButton(
                  tooltip: l10n.disconnect,
                  icon: const Icon(Icons.link_off_rounded),
                  onPressed: () => sessions.close(serverId),
                ),
            ],
          ),
          body: SafeArea(
            child: session == null
                ? Center(child: Text(l10n.sessionClosedMsg))
                : SshTerminalView(
                    session: session,
                    onRetry: () => sessions.retry(serverId),
                    reconnectPlan: sessions.reconnectPlanOf(serverId),
                    onStopAutoReconnect: () =>
                        sessions.cancelAutoReconnect(serverId),
                  ),
          ),
        );
      },
    );
  }
}
