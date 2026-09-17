import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_locale.dart';
import 'host_portable.dart';
import 'host_transfer.dart';
import 'l10n/generated/app_localizations.dart';
import 'models.dart';
import 'ssh/connect_flow.dart';
import 'ssh/credential_store.dart';
import 'ssh/session_manager.dart';
import 'ssh/ssh_credentials.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets/group_controls.dart';
import 'widgets/server_detail.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/sidebar.dart';

/// 桌面端左右分栏骨架：左侧连接侧边栏（固定宽度，可整体收起），右侧详情面板。
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.store,
    required this.sessions,
    required this.credentials,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onLanguageChanged,
    this.onSettingsClosed,
  });

  final ServerStore store;
  final SessionManager sessions;
  final CredentialStore credentials;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;

  /// 设置弹窗关闭后的回调：把「点完成」当作一次明确提交，立即落盘。
  final VoidCallback? onSettingsClosed;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _sidebarCollapsed = false;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStoreChanged);
      widget.store.addListener(_onStoreChanged);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() => setState(() {});

  void _toggleSidebar() =>
      setState(() => _sidebarCollapsed = !_sidebarCollapsed);

  void _openSettings() {
    unawaited(_showSettings());
  }

  Future<void> _showSettings() async {
    await showSettingsDialog(
      context,
      themeMode: widget.themeMode,
      onThemeModeChanged: widget.onThemeModeChanged,
      language: widget.language,
      onLanguageChanged: widget.onLanguageChanged,
      archiveUnreadable: widget.store.archiveUnreadable,
    );
    if (!mounted) return;
    widget.onSettingsClosed?.call();
  }

  SshServer? get _selected => widget.store.byId(_selectedId);

  Future<void> _toggleConnect(SshServer server) => toggleSession(
    context,
    sessions: widget.sessions,
    server: server,
    credentials: widget.credentials,
  );

  Future<void> _importHosts() => importHostsFlow(
    context,
    store: widget.store,
    credentials: widget.credentials,
  );

  Future<void> _exportHosts() => exportHostsFlow(
    context,
    store: widget.store,
    credentials: widget.credentials,
  );

  Future<void> _deleteServer(SshServer server) async {
    // 删除不可恢复（撤销条只是兜底），桌面端与移动端一致先弹确认框。
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.deleteConfirmTitle(server.name)),
          content: Text(l10n.deleteConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppPalette.danger),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    // 先结束该主机的会话，避免悬挂连接；已存凭据一并清理。
    widget.sessions.close(server.id);
    await widget.credentials.delete(server.id);
    if (!mounted) return;
    final index = widget.store.remove(server.id);
    if (index == -1) return;
    if (_selectedId == server.id) setState(() => _selectedId = null);
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.deletedSnackbar(server.name)),
          action: SnackBarAction(
            label: l10n.undo,
            onPressed: () {
              widget.store.restore(server, index);
              setState(() => _selectedId = server.id);
            },
          ),
        ),
      );
  }

  /// [group] 非空表示「在这个分组里新建」（分组头菜单的入口），表单预填该分组。
  Future<void> _editOrCreate([SshServer? existing, String? group]) async {
    final result = await showDialog<SshServer>(
      context: context,
      builder: (_) => _ServerDialog(
        initial: existing,
        initialGroup: group,
        groupNames: widget.store.groupNames,
        credentials: widget.credentials,
      ),
    );
    if (result == null || !mounted) return;
    widget.store.upsert(result);
    setState(() => _selectedId = result.id);
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = _sidebarCollapsed;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true):
            _toggleSidebar,
        const SingleActivator(LogicalKeyboardKey.keyB, control: true):
            _toggleSidebar,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: _SplitPane(
            collapsed: collapsed,
            sidebar: Sidebar(
              store: widget.store,
              selectedId: _selectedId,
              onSelect: (server) => setState(() => _selectedId = server.id),
              onCreate: () => _editOrCreate(),
              onCreateInGroup: (group) => _editOrCreate(null, group),
              onEdit: (server) => _editOrCreate(server),
              onDelete: _deleteServer,
              onToggleConnect: _toggleConnect,
              onToggleSidebar: _toggleSidebar,
              onOpenSettings: _openSettings,
              onImportHosts: _importHosts,
              onExportHosts: _exportHosts,
            ),
            // 详情面板自带窗口标题条（Windows/Linux 上是它里面的第一行，
            // 且服务器头部就排在这一行里），侧边栏因此可以整块顶到窗口最上沿。
            detail: ServerDetailPanel(
              server: _selected,
              sessions: widget.sessions,
              onConnect: _toggleConnect,
              onCreate: () => _editOrCreate(),
              onDelete: _deleteServer,
              sidebarCollapsed: collapsed,
              onToggleSidebar: _toggleSidebar,
            ),
          ),
        ),
      ),
    );
  }
}

/// 左右分栏骨架：侧边栏固定宽度，只保留整块收起 / 展开（访达那种不可拖拽的侧栏）。
/// 两栏同色（都是页面底色），分界只靠留白与卡片底色，不再有分隔线或拖拽条。
class _SplitPane extends StatelessWidget {
  const _SplitPane({
    required this.sidebar,
    required this.detail,
    required this.collapsed,
  });

  /// 侧边栏宽度：容得下「主机名 + 账号@地址」两行，再宽也只是空白。
  static const sidebarWidth = 264.0;

  final Widget sidebar;
  final Widget detail;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 收起时宽度动画到 0，内部保持固定宽度向左滑出并被裁剪。
        ClipRect(
          child: AnimatedContainer(
            key: const ValueKey('sidebar-slot'),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: collapsed ? 0 : sidebarWidth,
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 0,
              maxWidth: sidebarWidth,
              child: SizedBox(width: sidebarWidth, child: sidebar),
            ),
          ),
        ),
        Expanded(child: detail),
      ],
    );
  }
}

class _ServerDialog extends StatefulWidget {
  const _ServerDialog({
    required this.groupNames,
    required this.credentials,
    this.initial,
    this.initialGroup,
  });

  final SshServer? initial;

  /// 新建时预填的分组（「在此分组新建连接」传进来）。
  final String? initialGroup;
  final List<String> groupNames;
  final CredentialStore credentials;

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _metadata = TextEditingController();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _host = TextEditingController(text: widget.initial?.host);
  late final _port = TextEditingController(
    text: (widget.initial?.port ?? 22).toString(),
  );
  late final _username = TextEditingController(text: widget.initial?.username);
  late final _group = TextEditingController(
    text: widget.initial?.group ?? widget.initialGroup ?? '',
  );
  late final _notes = TextEditingController(text: widget.initial?.notes);
  late AuthMethod _auth = widget.initial?.authMethod ?? AuthMethod.privateKey;

  /// 粘贴的元数据里带的密码，保存时写进安全存储。
  String? _password;

  @override
  void dispose() {
    for (final controller in [
      _metadata,
      _name,
      _host,
      _port,
      _username,
      _group,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 把粘贴的元数据填进下方表单：只覆盖识别到的字段，用户仍可继续手动改。
  void _applyMetadata(String text) {
    final drafts = parseHostsText(
      text,
      defaultGroup: AppLocalizations.of(context).defaultGroupName,
    );
    if (drafts.isEmpty) return;
    final draft = drafts.first;
    setState(() {
      _name.text = draft.name;
      _host.text = draft.host;
      _port.text = draft.port.toString();
      _username.text = draft.username;
      _password = draft.password;
      // 元数据只承载密码认证；没写密码时保留手动选择的认证方式。
      if (draft.password != null) _auth = AuthMethod.password;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    final id =
        widget.initial?.id ?? 'srv-${DateTime.now().microsecondsSinceEpoch}';
    final password = _password;
    if (password != null &&
        _auth == AuthMethod.password &&
        widget.credentials.supported) {
      await widget.credentials.write(id, SshCredentials(password: password));
    }
    if (!mounted) return;
    // 分组留空即落到默认分组；填了新名字就当场建一个（GroupField 支持直接输入）。
    final group = _group.text.trim();
    Navigator.of(context).pop(
      SshServer(
        id: id,
        group: group.isEmpty ? l10n.defaultGroupName : group,
        name: _name.text.trim(),
        host: _host.text.trim(),
        username: _username.text.trim(),
        port: int.parse(_port.text.trim()),
        authMethod: _auth,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        tags: widget.initial?.tags ?? const [],
        lastConnectedAt: widget.initial?.lastConnectedAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(
        widget.initial == null ? l10n.newConnection : l10n.editConnection,
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _metadata,
                  maxLines: 5,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: InputDecoration(
                    labelText: l10n.pasteMetadata,
                    hintText: l10n.pasteMetadataHint,
                    alignLabelWithHint: true,
                  ),
                  onChanged: _applyMetadata,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  autofocus: widget.initial == null,
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    labelText: l10n.fieldName,
                    hintText: l10n.nameHint,
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? l10n.nameRequired : null,
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _host,
                        style: const TextStyle(fontSize: 13.5),
                        decoration: InputDecoration(
                          labelText: l10n.fieldHost,
                          hintText: l10n.hostHint,
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? l10n.hostRequired
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _port,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 13.5),
                        decoration: InputDecoration(labelText: l10n.port),
                        validator: (v) {
                          final port = int.tryParse(v ?? '');
                          if (port == null || port < 1 || port > 65535) {
                            return l10n.portInvalid;
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _username,
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    labelText: l10n.username,
                    hintText: l10n.usernameHint,
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? l10n.usernameRequired
                      : null,
                ),
                const SizedBox(height: 12),
                GroupField(
                  controller: _group,
                  groups: widget.groupNames,
                  textStyle: const TextStyle(fontSize: 13.5),
                ),
                const SizedBox(height: 12),
                SegmentedButton<AuthMethod>(
                  segments: [
                    ButtonSegment(
                      value: AuthMethod.password,
                      label: Text(l10n.authPassword),
                      icon: const Icon(Icons.password_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: AuthMethod.privateKey,
                      label: Text(l10n.authKey),
                      icon: const Icon(Icons.vpn_key_outlined, size: 16),
                    ),
                  ],
                  selected: {_auth},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      setState(() => _auth = selection.first),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    labelText: l10n.notesOptional,
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.save)),
      ],
    );
  }
}
