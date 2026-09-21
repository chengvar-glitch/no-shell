import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../ssh/credential_store.dart';
import '../ssh/session_manager.dart';
import '../ssh/session_page.dart';
import '../ssh/terminal_view.dart';
import '../theme.dart';
import '../widgets/status_badges.dart';

/// 终端 Tab：统一管理活跃 SSH 会话，点击进入全屏终端。
final class TerminalTab extends StatelessWidget {
  const TerminalTab({
    super.key,
    required this.sessions,
    required this.credentials,
  });

  final SessionManager sessions;

  /// 全屏终端页里「新建会话」要按连接流程取凭据，这里原样透传。
  final CredentialStore credentials;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sessions,
      builder: (context, _) {
        final all = sessions.sessions;
        return Scaffold(
          appBar: AppBar(title: Text(AppLocalizations.of(context).terminal)),
          body: all.isEmpty
              ? _emptyView(context)
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: all.length,
                  itemBuilder: (context, index) {
                    final session = all[index];
                    return ListTile(
                      leading: StatusDot(status: serverStatusOf(session.phase)),
                      title: Text(session.server.name),
                      subtitle: Text(session.server.account),
                      trailing: IconButton(
                        tooltip: AppLocalizations.of(context).disconnect,
                        icon: const Icon(Icons.link_off_rounded, size: 19),
                        onPressed: () => sessions.closeSession(session),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SessionPage(
                            sessions: sessions,
                            serverId: session.server.id,
                            credentials: credentials,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _emptyView(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.terminal_outlined,
            size: 56,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(l10n.noActiveSessions, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            l10n.sessionsEmptyHint,
            style: TextStyle(fontSize: 12.5, color: theme.secondaryText),
          ),
        ],
      ),
    );
  }
}
