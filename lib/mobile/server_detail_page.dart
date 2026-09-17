import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../ssh/connect_flow.dart';
import '../ssh/credential_store.dart';
import '../ssh/session_manager.dart';
import '../store.dart';
import '../widgets/server_detail.dart' show OverviewTab, TerminalTab;
import '../widgets/sftp_browser.dart' show SftpTab;
import '../widgets/status_badges.dart';
import 'server_edit_page.dart';

/// 移动端主机详情页：概览 / 终端 / SFTP 三个 Tab + 底部连接操作，
/// 复用桌面端的概览、终端与 SFTP 视图。
class ServerDetailPage extends StatelessWidget {
  const ServerDetailPage({
    super.key,
    required this.store,
    required this.sessions,
    required this.credentials,
    required this.serverId,
  });

  final ServerStore store;
  final SessionManager sessions;
  final CredentialStore credentials;
  final String serverId;

  void _edit(BuildContext context, SshServer server) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServerEditPage(
          store: store,
          credentials: credentials,
          initial: server,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, SshServer server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final dialogL10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(dialogL10n.deleteConfirmTitle(server.name)),
          content: Text(dialogL10n.deleteConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(dialogL10n.cancel),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(dialogL10n.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    // 先结束该主机的会话，避免悬挂连接；已存凭据一并清理。
    sessions.close(server.id);
    await credentials.delete(server.id);
    if (!context.mounted) return;
    store.remove(server.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final server = store.byId(serverId);
        if (server == null) {
          // 主机已被删除（或撤销后仍在返回途中），直接展示空态。
          return Scaffold(
            body: Center(
              child: Text(AppLocalizations.of(context).hostNotFound),
            ),
          );
        }
        final session = sessions.byServerId(server.id);
        final hasActive = session?.isActive ?? false;
        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    server.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(status: server.status),
              ],
            ),
            actions: [
              IconButton(
                tooltip: l10n.edit,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _edit(context, server),
              ),
              IconButton(
                tooltip: l10n.delete,
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => _confirmDelete(context, server),
              ),
            ],
          ),
          body: DefaultTabController(
            length: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TabBar(
                  tabs: [
                    Tab(text: l10n.overview),
                    Tab(text: l10n.terminal),
                    Tab(text: l10n.sftp),
                  ],
                  onTap: (_) => FocusScope.of(context).unfocus(),
                ),
                Expanded(
                  child: TabBarView(
                    // 保活三个 Tab：切走不再 dispose，切回终端无需重建 xterm 视图。
                    children: [
                      _KeepAlive(child: OverviewTab(server: server)),
                      _KeepAlive(
                        child: TerminalTab(
                          server: server,
                          session: session,
                          idleHint: l10n.sessionMobileHint,
                          onRetry: session == null
                              ? null
                              : () => sessions.retry(server.id),
                        ),
                      ),
                      _KeepAlive(
                        child: SftpTab(
                          session: session,
                          idleHint: l10n.sftpSessionMobileHint,
                          onRetry: session == null
                              ? null
                              : () => sessions.retry(server.id),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: () => toggleSession(
                context,
                sessions: sessions,
                server: server,
                credentials: credentials,
              ),
              icon: Icon(
                hasActive ? Icons.link_off_rounded : Icons.bolt_rounded,
                size: 17,
              ),
              label: Text(hasActive ? l10n.disconnect : l10n.connectNow),
            ),
          ),
        );
      },
    );
  }
}

/// TabBarView 页面保活包装：共享的 Tab 组件无法逐一改成
/// AutomaticKeepAliveClientMixin，在这里统一声明 wantKeepAlive。
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
