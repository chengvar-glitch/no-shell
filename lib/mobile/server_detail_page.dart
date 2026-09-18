import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../ssh/connect_flow.dart';
import '../ssh/credential_store.dart';
import '../ssh/host_key_store.dart';
import '../ssh/session_manager.dart';
import '../ssh/terminal_session.dart';
import '../store.dart';
import '../widgets/port_forward_panel.dart' show PortForwardPanel;
import '../widgets/server_detail.dart' show OverviewTab, TerminalTab;
import '../widgets/session_log_dialog.dart';
import '../widgets/sftp_browser.dart' show SftpTab;
import '../widgets/status_badges.dart';
import 'server_edit_page.dart';
import '../widgets/confirm_dialog.dart';

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

class _ServerDetailPageState extends State<ServerDetailPage> {
  /// 上一次看到的「当前会话 + 会话条数」，与桌面端详情面板同一套守卫。
  ///
  /// 会话层的通知频率很高（终端输出、重连倒计时都会发），而这里要跟的只是
  /// 「当前会话换了没有、条数变了没有」：同主机多开时 [SessionManager.activate]
  /// 只发会话层通知，store 的状态没变，光靠 store 那一路重建不起来，
  /// 终端 / SFTP / 底部连接按钮就会停在旧状态上。
  int _syncedCount = 0;
  TerminalSession? _syncedActive;

  @override
  void initState() {
    super.initState();
    _syncSessionSelection();
    widget.sessions.addListener(_onSessionsChanged);
  }

  @override
  void dispose() {
    widget.sessions.removeListener(_onSessionsChanged);
    super.dispose();
  }

  void _syncSessionSelection() {
    _syncedCount = widget.sessions.sessionCountOf(widget.serverId);
    _syncedActive = widget.sessions.activeOf(widget.serverId);
  }

  void _onSessionsChanged() {
    final count = widget.sessions.sessionCountOf(widget.serverId);
    final active = widget.sessions.activeOf(widget.serverId);
    if (count == _syncedCount && identical(active, _syncedActive)) return;
    _syncedCount = count;
    _syncedActive = active;
    setState(() {});
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
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.deleteConfirmTitle(server.name),
      body: l10n.deleteConfirmBody,
      confirmLabel: l10n.delete,
    );
    if (!confirmed) return;
    if (!context.mounted) return;
    // 先结束该主机的会话（可能是多开的几条），避免悬挂连接。
    widget.sessions.closeAll(server.id);
    // 凭据与指纹的清理不 await：钥匙串 / 存储层卡住时不能把删除本身拖住
    // （与桌面端、移动端列表页同款，见 dropHostSecrets）。
    unawaited(
      dropHostSecrets(
        credentials: widget.credentials,
        hostKeys: widget.hostKeys,
        server: server,
      ),
    );
    widget.store.remove(server.id);
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
