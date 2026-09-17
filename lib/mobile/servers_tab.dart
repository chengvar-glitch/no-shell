import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../host_transfer.dart';
import '../models.dart';
import '../ssh/connect_flow.dart';
import '../ssh/credential_store.dart';
import '../ssh/session_manager.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/group_controls.dart';
import '../widgets/status_badges.dart';
import 'server_detail_page.dart';
import 'server_edit_page.dart';

/// 服务器 Tab：移动端主机列表，支持搜索、分组展示、长按操作与新建。
class ServersTab extends StatefulWidget {
  const ServersTab({
    super.key,
    required this.store,
    required this.sessions,
    required this.credentials,
  });

  final ServerStore store;
  final SessionManager sessions;
  final CredentialStore credentials;

  @override
  State<ServersTab> createState() => _ServersTabState();
}

class _ServersTabState extends State<ServersTab> {
  bool _searching = false;

  /// 搜索关键词走 ValueNotifier：每次输入只重建列表子树，
  /// 不把 setState 上抛到整个 Tab（含顶栏与 FAB）。
  final ValueNotifier<String> _query = ValueNotifier('');

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// [group] 非空表示「在这个分组里新建」（分组头菜单的入口），表单预填该分组。
  void _openEditor([SshServer? existing, String? group]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServerEditPage(
          store: widget.store,
          credentials: widget.credentials,
          initial: existing,
          initialGroup: group,
        ),
      ),
    );
  }

  void _openDetail(SshServer server) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServerDetailPage(
          store: widget.store,
          sessions: widget.sessions,
          credentials: widget.credentials,
          serverId: server.id,
        ),
      ),
    );
  }

  void _showActions(SshServer server) {
    final l10n = AppLocalizations.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    showModalBottomSheet<void>(
      context: context,
      // 同分组操作表：弹层限高 9/16 屏高，矮屏 / 横屏靠滚动兜住。
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  server.status == ServerStatus.connected
                      ? Icons.link_off_rounded
                      : Icons.play_arrow_rounded,
                ),
                title: Text(
                  server.status == ServerStatus.connected
                      ? l10n.disconnect
                      : l10n.connect,
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  toggleSession(
                    context,
                    sessions: widget.sessions,
                    server: server,
                    credentials: widget.credentials,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.edit),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openEditor(server);
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: Text(l10n.groupMoveTo),
                onTap: () {
                  Navigator.pop(sheetContext);
                  moveServerToGroupFlow(
                    context,
                    store: widget.store,
                    server: server,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                iconColor: errorColor,
                textColor: errorColor,
                title: Text(l10n.delete),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDelete(server);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(SshServer server) async {
    final l10n = AppLocalizations.of(context);
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
    if (!mounted) return;
    // 先结束该主机的会话，避免悬挂连接；已存凭据一并清理。
    widget.sessions.close(server.id);
    await widget.credentials.delete(server.id);
    if (!mounted) return;
    widget.store.remove(server.id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(l10n.deletedSnackbar(server.name))),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: _searching ? _searchField() : Text(l10n.navServers),
            actions: [
              IconButton(
                tooltip: _searching ? l10n.cancelSearch : l10n.search,
                icon: Icon(
                  _searching ? Icons.close_rounded : Icons.search_rounded,
                ),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  _query.value = '';
                }),
              ),
              PopupMenuButton<String>(
                onSelected: (action) {
                  switch (action) {
                    case 'import':
                      importHostsFlow(
                        context,
                        store: widget.store,
                        credentials: widget.credentials,
                      );
                    case 'export':
                      exportHostsFlow(
                        context,
                        store: widget.store,
                        credentials: widget.credentials,
                      );
                    case 'import-backup':
                      importHostsBackupFlow(
                        context,
                        store: widget.store,
                        credentials: widget.credentials,
                      );
                    case 'export-backup':
                      exportHostsBackupFlow(
                        context,
                        store: widget.store,
                        credentials: widget.credentials,
                      );
                  }
                },
                itemBuilder: (menuContext) {
                  final menuL10n = AppLocalizations.of(menuContext);
                  return [
                    PopupMenuItem(
                      value: 'import',
                      child: Row(
                        children: [
                          const Icon(Icons.download_rounded, size: 20),
                          const SizedBox(width: 12),
                          Text(menuL10n.importHosts),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'export',
                      child: Row(
                        children: [
                          const Icon(Icons.upload_outlined, size: 20),
                          const SizedBox(width: 12),
                          Text(menuL10n.exportHosts),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'import-backup',
                      child: Row(
                        children: [
                          const Icon(Icons.lock_open_rounded, size: 20),
                          const SizedBox(width: 12),
                          Text(menuL10n.importHostsBackup),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'export-backup',
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline_rounded, size: 20),
                          const SizedBox(width: 12),
                          Text(menuL10n.exportHostsBackup),
                        ],
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),
          body: ValueListenableBuilder<String>(
            valueListenable: _query,
            builder: (context, query, _) {
              final groups = widget.store.groups(query: query);
              final total = widget.store.serverCount;
              // 搜索时强制展开，保证命中结果可见；平时按 store 记的折叠态。
              final searching = query.isNotEmpty;
              // 扁平化为「分组头 / 主机行」序列，itemBuilder 按下标直取，
              // 避免每构建一行都从头回扫分组列表。
              final rows = <Object>[
                for (final group in groups) ...[
                  group,
                  if (searching || !group.collapsed) ...group.servers,
                ],
              ];
              return rows.isEmpty
                  ? _emptyView(context, total)
                  // 扁平化为「分组头 / 主机行」序列，懒构建可见行即可。
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        if (row is ServerGroup) {
                          return _groupHeader(
                            context,
                            row,
                            searching: searching,
                          );
                        }
                        final server = row as SshServer;
                        return _ServerTile(
                          server: server,
                          onTap: () => _openDetail(server),
                          onLongPress: () => _showActions(server),
                          onToggleConnect: () => toggleSession(
                            context,
                            sessions: widget.sessions,
                            server: server,
                            credentials: widget.credentials,
                          ),
                        );
                      },
                    );
            },
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.newConnection),
          ),
        );
      },
    );
  }

  /// 分组操作：与桌面端分组头菜单同一套动作，这里走底部弹层。
  Future<void> _showGroupActions(ServerGroup group) async {
    final l10n = AppLocalizations.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final index = widget.store.groupNames.indexOf(group.name);
    final last = widget.store.groupNames.length - 1;
    final action = await showModalBottomSheet<GroupAction>(
      context: context,
      // 弹层默认限高 9/16 屏高，矮屏 / 横屏装不下 6 项，交给滚动而不是溢出。
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add_rounded),
                title: Text(l10n.groupNewConnection),
                onTap: () =>
                    Navigator.pop(sheetContext, GroupAction.createConnection),
              ),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: Text(l10n.groupNew),
                onTap: () =>
                    Navigator.pop(sheetContext, GroupAction.createGroup),
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: Text(l10n.groupRename),
                onTap: () => Navigator.pop(sheetContext, GroupAction.rename),
              ),
              ListTile(
                leading: const Icon(Icons.arrow_upward_rounded),
                title: Text(l10n.groupMoveUp),
                enabled: index > 0,
                onTap: () => Navigator.pop(sheetContext, GroupAction.moveUp),
              ),
              ListTile(
                leading: const Icon(Icons.arrow_downward_rounded),
                title: Text(l10n.groupMoveDown),
                enabled: index >= 0 && index < last,
                onTap: () => Navigator.pop(sheetContext, GroupAction.moveDown),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                iconColor: errorColor,
                textColor: errorColor,
                title: Text(l10n.groupDelete),
                onTap: () => Navigator.pop(sheetContext, GroupAction.delete),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    await runGroupAction(
      context,
      store: widget.store,
      action: action,
      group: group.name,
      onCreateInGroup: () => _openEditor(null, group.name),
    );
  }

  Widget _searchField() {
    return TextField(
      autofocus: true,
      onChanged: (value) => _query.value = value,
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context).searchHint,
        border: InputBorder.none,
      ),
    );
  }

  Widget _emptyView(BuildContext context, int total) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lan_outlined, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            total == 0 ? l10n.noHostsYet : l10n.noMatchingHosts,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            total == 0 ? l10n.createFirstConnection : l10n.tryAnotherKeyword,
            style: TextStyle(fontSize: 12.5, color: theme.secondaryText),
          ),
        ],
      ),
    );
  }

  Widget _groupHeader(
    BuildContext context,
    ServerGroup group, {
    required bool searching,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return InkWell(
      // 搜索时结果强制展开，这时点折叠没有意义（与桌面端一致）。
      onTap: searching
          ? null
          : () => widget.store.setGroupCollapsed(group.name, !group.collapsed),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 2),
        child: Row(
          children: [
            AnimatedRotation(
              turns: group.collapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 17,
                color: theme.secondaryText,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: theme.secondaryText,
                ),
              ),
            ),
            Text(
              '${group.servers.length}',
              style: TextStyle(
                fontSize: 11,
                color: theme.secondaryText.withValues(alpha: 0.7),
              ),
            ),
            IconButton(
              tooltip: l10n.moreActions,
              // 触屏上这是分组管理的唯一入口，命中区按 44 给足
              // （compact 密度下默认只有 40）。
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              iconSize: 18,
              icon: Icon(
                Icons.more_horiz_rounded,
                size: 18,
                color: theme.secondaryText,
              ),
              onPressed: () => _showGroupActions(group),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleConnect,
  });

  final SshServer server;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final connected = server.status == ServerStatus.connected;
    final subtitle = server.port == 22
        ? server.account
        : '${server.account}:${server.port}';
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: StatusDot(status: server.status),
      title: Text(
        server.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: theme.secondaryText),
      ),
      trailing: IconButton(
        tooltip: connected ? l10n.disconnect : l10n.connect,
        icon: Icon(
          connected ? Icons.link_off_rounded : Icons.play_arrow_rounded,
          color: theme.secondaryText,
        ),
        onPressed: onToggleConnect,
      ),
    );
  }
}
