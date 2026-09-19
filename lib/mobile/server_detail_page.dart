import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../ssh/connect_flow.dart';
import '../ssh/credential_store.dart';
import '../ssh/host_key_store.dart';
import '../ssh/session_manager.dart';
import '../store.dart';
import '../widgets/port_forward_panel.dart' show PortForwardPanel;
import '../widgets/server_detail.dart'
    show OverviewTab, TerminalIdleStyle, TerminalTab;
import '../widgets/session_log_dialog.dart';
import '../widgets/session_selection.dart';
import '../widgets/sftp_browser.dart' show SftpTab;
import '../widgets/status_badges.dart';
import 'server_edit_page.dart';

/// 移动端主机详情页：概览 / 终端 / SFTP / 转发四个 Tab + 底部连接操作，
/// 复用桌面端的概览、终端、SFTP 与转发视图。
class ServerDetailPage extends StatefulWidget {
  const ServerDetailPage({
    super.key,
    required this.store,
    required this.sessions,
    required this.credentials,
    this.hostKeys,
    required this.serverId,
  });

  final ServerStore store;
  final SessionManager sessions;
  final CredentialStore credentials;

  /// 已记录的主机指纹；删除主机时一并清理，可选（测试可省）。
  final HostKeyStore? hostKeys;
  final String serverId;

  @override
  State<ServerDetailPage> createState() => _ServerDetailPageState();
}

class _ServerDetailPageState extends State<ServerDetailPage>
    with SessionSelectionGuard {
  @override
  SessionManager get guardedSessions => widget.sessions;

  @override
  String get guardedServerId => widget.serverId;

  @override
  void initState() {
    super.initState();
    startSessionGuard();
  }

  @override
  void didUpdateWidget(ServerDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessions != widget.sessions) {
      rebindSessionGuard(oldWidget.sessions);
    }
    if (oldWidget.serverId != widget.serverId) resyncSessionGuard();
  }

  @override
  void dispose() {
    stopSessionGuard();
    super.dispose();
  }

  void _edit(BuildContext context, SshServer server) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServerEditPage(
          store: widget.store,
          credentials: widget.credentials,
          initial: server,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, SshServer server) async {
    final index = await confirmAndDeleteHost(
      context,
      store: widget.store,
      sessions: widget.sessions,
      credentials: widget.credentials,
      hostKeys: widget.hostKeys,
      server: server,
    );
    if (index == null || !context.mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 注意：这里的 store 订阅必须保留——名称 / 状态 / 会话都来自它。
    // 四个 Tab 各自的保活子树已经尽力隔离（见下方 _KeepAlive），
    // 终端那边的重排版由 SshTerminalView 内部的 TerminalStyle 缓存兜住。
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final server = widget.store.byId(widget.serverId);
        if (server == null) {
          // 主机已被删除（或撤销后仍在返回途中），直接展示空态。
          return Scaffold(
            body: Center(
              child: Text(AppLocalizations.of(context).hostNotFound),
            ),
          );
        }
        final session = widget.sessions.activeOf(server.id);
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
                StatusPill(
                  status: server.status,
                  onTap: session == null
                      ? null
                      : () => showSessionLogDialog(context, session: session),
                ),
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
            length: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TabBar(
                  tabs: [
                    Tab(text: l10n.overview),
                    Tab(text: l10n.terminal),
                    Tab(text: l10n.sftp),
                    Tab(text: l10n.portForwarding),
                  ],
                  onTap: (_) => FocusScope.of(context).unfocus(),
                ),
                Expanded(
                  child: TabBarView(
                    // 保活四个 Tab：切走不再 dispose，切回终端无需重建 xterm 视图。
                    children: [
                      _KeepAlive(
                        child: OverviewTab(
                          server: server,
                          // 跳板机存的是 id，概览要给人看的名字；那台主机已被删时
                          // 名字为空，卡片退回显示 id，让用户看出引用已经失效。
                          jumpHostName: widget.store
                              .byId(server.jumpServerId)
                              ?.name,
                        ),
                      ),
                      _KeepAlive(
                        child: TerminalTab(
                          server: server,
                          session: session,
                          sessions: widget.sessions,
                          idleHint: l10n.sessionMobileHint,
                          // 未连接时不摆黑终端块，与 SFTP Tab 同一形态的空态。
                          idleStyle: TerminalIdleStyle.plain,
                          onRetry: session == null
                              ? null
                              : () => widget.sessions.retry(session),
                        ),
                      ),
                      _KeepAlive(
                        child: SftpTab(
                          session: session,
                          idleHint: l10n.sftpSessionMobileHint,
                          onRetry: session == null
                              ? null
                              : () => widget.sessions.retry(session),
                        ),
                      ),
                      _KeepAlive(
                        child: PortForwardPanel(
                          server: server,
                          store: widget.store,
                          sessions: widget.sessions,
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
                sessions: widget.sessions,
                server: server,
                credentials: widget.credentials,
                // 必须带上 store：跳板机链路是从它解析出来的。
                store: widget.store,
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
