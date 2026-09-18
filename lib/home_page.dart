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
import 'ssh/host_key_store.dart';
import 'ssh/session_manager.dart';
import 'ssh/ssh_agent.dart';
import 'ssh/ssh_credentials.dart';
import 'shell_layout.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets/group_controls.dart';
import 'widgets/jump_host_field.dart';
import 'widgets/server_detail.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/sidebar.dart';
import 'widgets/confirm_dialog.dart';

/// 桌面端左右分栏骨架：左侧连接侧边栏（固定宽度，可整体收起），右侧详情面板。
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.store,
    required this.sessions,
    required this.credentials,
    this.hostKeys,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.language,
    required this.onLanguageChanged,
    this.onSettingsClosed,
    this.allowLegacyHostKeys = false,
    this.onAllowLegacyHostKeysChanged,
    this.layout,
  });

  final ServerStore store;
  final SessionManager sessions;
  final CredentialStore credentials;

  /// 已记录的主机指纹；删除主机时一并清理，可选（测试可省）。
  final HostKeyStore? hostKeys;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;

  /// 设置弹窗关闭后的回调：把「点完成」当作一次明确提交，立即落盘。
  final VoidCallback? onSettingsClosed;

  /// 连接老设备时是否允许 ssh-rsa（SHA-1）主机密钥。
  final bool allowLegacyHostKeys;
  final ValueChanged<bool>? onAllowLegacyHostKeysChanged;

  /// 跨断点保留的界面状态；由应用入口持有，两套骨架共用一份。
  /// 为空时（组件测试、单独挂载）本页自建一份，行为与从前一致。
  final ShellLayoutState? layout;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// ⌘1…⌘9 用到的数字键（终端字号缩放用的是无修饰键的 0，不冲突）。
  static const List<LogicalKeyboardKey> _sessionDigitKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  /// 跨断点保留的那几个值（选中项 / 侧边栏折叠）放在这里，而不是本 State：
  /// 窗口宽度跨过 640px 时整套骨架会被换掉，State 连同它一起销毁重建。
  late final ShellLayoutState _layout = widget.layout ?? ShellLayoutState();

  String? get _selectedId => _layout.selectedId;

  bool get _sidebarCollapsed => _layout.sidebarCollapsed;

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

  /// 上一次整页重建时选中的那台（含它跳板机的名字）。
  ///
  /// 详情面板渲染的 store 数据只有这两样：选中的主机本身，以及概览卡片上
  /// 「经哪台跳板机」的名字。其余变更（别的主机增删改、状态翻转、分组折叠）
  /// 由侧边栏自己订阅 store 处理，不该把整页连同终端 / SFTP 保活子树重画——
  /// 那些子树的重建代价远大于侧边栏的一行。
  ///
  /// 主机对象是不可变的，任何编辑或状态变更都会换一个新实例，因此身份比较
  /// 就足以判断「这台主机的内容变了」。
  Object? _renderedSelection;

  Object? _selectionSignature() {
    final selected = _selected;
    if (selected == null) return null;
    return (selected, widget.store.byId(selected.jumpServerId)?.name);
  }

  void _onStoreChanged() {
    final signature = _selectionSignature();
    if (signature == _renderedSelection) return;
    setState(() => _renderedSelection = signature);
  }

  void _toggleSidebar() =>
      setState(() => _layout.sidebarCollapsed = !_layout.sidebarCollapsed);

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
      allowLegacyHostKeys: widget.allowLegacyHostKeys,
      onAllowLegacyHostKeysChanged: widget.onAllowLegacyHostKeysChanged,
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
    // 必须带上 store：连接流程靠它解析跳板链路，漏传等于静默忽略跳板机。
    store: widget.store,
  );

  /// 在同一台主机上再开一条会话（⊕ / ⌘T / 侧边栏右键菜单同一入口）。
  Future<void> _newSession(SshServer server) => newSessionFlow(
    context,
    sessions: widget.sessions,
    server: server,
    credentials: widget.credentials,
    store: widget.store,
  );

  /// ⌘T / Ctrl+T：给当前选中的主机再开一条会话。
  void _newSessionShortcut() {
    final server = _selected;
    if (server == null) return;
    unawaited(_newSession(server));
  }

  /// ⌘1…⌘9：把当前会话切到该主机的第 N 条；没有那一条就什么也不做。
  void _activateSession(int ordinal) {
    final server = _selected;
    if (server == null) return;
    final session = widget.sessions.byOrdinal(server.id, ordinal);
    if (session != null) widget.sessions.activate(session);
  }

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
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.deleteConfirmTitle(server.name),
      body: l10n.deleteConfirmBody,
      confirmLabel: l10n.delete,
    );
    if (!confirmed || !mounted) return;
    // 先结束该主机的会话（可能是多开的几条），避免悬挂连接。
    widget.sessions.closeAll(server.id);
    // 凭据与指纹的清理不 await：钥匙串 / 存储层卡住时不能把删除本身
    // 拖住（用户点了删除就必须删掉）。它只影响下次连接的判定。
    unawaited(
      dropHostSecrets(
        credentials: widget.credentials,
        hostKeys: widget.hostKeys,
        server: server,
      ),
    );
    final index = widget.store.remove(server.id);
    if (index == -1) return;
    if (_selectedId == server.id) setState(() => _layout.selectedId = null);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.deletedSnackbar(server.name)),
          action: SnackBarAction(
            label: l10n.undo,
            onPressed: () {
              widget.store.restore(server, index);
              setState(() => _layout.selectedId = server.id);
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
        // 跳板机下拉的候选就是已保存的主机；新建时这台主机还没进列表，
        // 所以列表在弹窗打开时取一次即可（编辑期间列表不会变）。
        servers: widget.store.servers,
        credentials: widget.credentials,
      ),
    );
    if (result == null || !mounted) return;
    widget.store.upsert(result);
    setState(() => _layout.selectedId = result.id);
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
        // 多开会话的两个键位：⌘T 再来一条，⌘1…⌘9 直达第 N 条。
        // 终端自己的快捷键（字号缩放）用的是无修饰键，不会撞上。
        const SingleActivator(LogicalKeyboardKey.keyT, meta: true):
            _newSessionShortcut,
        const SingleActivator(LogicalKeyboardKey.keyT, control: true):
            _newSessionShortcut,
        for (var i = 0; i < _sessionDigitKeys.length; i++) ...{
          SingleActivator(_sessionDigitKeys[i], meta: true): () =>
              _activateSession(i + 1),
          SingleActivator(_sessionDigitKeys[i], control: true): () =>
              _activateSession(i + 1),
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: _SplitPane(
            collapsed: collapsed,
            sidebar: Sidebar(
              store: widget.store,
              sessions: widget.sessions,
              selectedId: _selectedId,
              onSelect: (server) =>
                  setState(() => _layout.selectedId = server.id),
              onCreate: () => _editOrCreate(),
              onCreateInGroup: (group) => _editOrCreate(null, group),
              onEdit: (server) => _editOrCreate(server),
              onDelete: _deleteServer,
              onToggleConnect: _toggleConnect,
              onCreateSession: _newSession,
              onToggleSidebar: _toggleSidebar,
              onOpenSettings: _openSettings,
              onImportHosts: _importHosts,
              onExportHosts: _exportHosts,
            ),
            // 详情面板自带窗口标题条（Windows/Linux 上是它里面的第一行，
            // 且服务器头部就排在这一行里），侧边栏因此可以整块顶到窗口最上沿。
            detail: ServerDetailPanel(
              server: _selected,
              store: widget.store,
              sessions: widget.sessions,
              credentials: widget.credentials,
              onConnect: _toggleConnect,
              onCreate: () => _editOrCreate(),
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
    required this.servers,
    this.initial,
    this.initialGroup,
  });

  final SshServer? initial;

  /// 新建时预填的分组（「在此分组新建连接」传进来）。
  final String? initialGroup;
  final List<String> groupNames;

  /// 全部已保存的主机，供跳板机下拉选；正在编辑的那台 [initial] 也在其中，
  /// 「不能选自己」由 [JumpHostField] 过滤。
  final List<SshServer> servers;
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

  /// 选中的分组名；null 表示默认分组（没动过下拉就是它）。
  late String? _group = widget.initial?.group ?? widget.initialGroup;
  late final _notes = TextEditingController(text: widget.initial?.notes);
  late AuthMethod _auth = widget.initial?.authMethod ?? AuthMethod.privateKey;

  /// 选中的跳板机 id；null 表示直连。
  late String? _jumpServerId = widget.initial?.jumpServerId;

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
      final saved = await widget.credentials.write(
        id,
        SshCredentials(password: password),
      );
      if (!saved && mounted) {
        showToast(context, l10n.credentialsSaveFailedMsg);
      }
    } else if (_auth != AuthMethod.password &&
        widget.initial?.authMethod == AuthMethod.password) {
      // 从密码认证改成密钥认证：旧密码留在钥匙串里没人再用，但每次导出
      // 都会被打包进备份。改方式就把它清掉。
      await dropStoredCredential(widget.credentials, id);
    }
    if (!mounted) return;
    // 分组下拉里只有已建好的分组，没动过就是默认分组。
    final group = _group ?? l10n.defaultGroupName;
    // 这里重建整台主机（而不是在 initial 上改），所以没显式带上的字段都会丢：
    // forwards 归转发面板维护，必须原样带回去，否则每编辑一次就静默删光规则。
    final saved = SshServer(
      id: id,
      group: group,
      name: _name.text.trim(),
      host: _host.text.trim(),
      username: _username.text.trim(),
      port: int.parse(_port.text.trim()),
      authMethod: _auth,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      tags: widget.initial?.tags ?? const [],
      lastConnectedAt: widget.initial?.lastConnectedAt,
      forwards: widget.initial?.forwards ?? const [],
    );
    Navigator.of(context).pop(
      // 跳板机可以被取消，而 copyWith 的 `??` 表达不出「清掉」，
      // 只有用户选了「不使用」且原本挂着跳板机时才置 clearJumpServer。
      saved.copyWith(
        jumpServerId: _jumpServerId,
        clearJumpServer:
            _jumpServerId == null && widget.initial?.jumpServerId != null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
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
                  value: _group ?? l10n.defaultGroupName,
                  groups: widget.groupNames,
                  onChanged: (name) => setState(() => _group = name),
                ),
                const SizedBox(height: 12),
                // 排在分组之后：分组是「这台主机属于哪」，跳板机是「怎么连过去」，
                // 紧挨着认证方式（同为连接参数）。helper 文案占两行，弹窗高度够。
                JumpHostField(
                  servers: widget.servers,
                  self: widget.initial,
                  value: _jumpServerId,
                  onChanged: (id) => setState(() => _jumpServerId = id),
                ),
                const SizedBox(height: 12),
                // 分组 / 跳板机都有自带标签，认证方式补一个同级小标题，
                // 三选一的语义一眼可读。
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    l10n.authMethod,
                    style: TextStyle(fontSize: 12, color: theme.secondaryText),
                  ),
                ),
                const SizedBox(height: 6),
                // 与上下输入框同宽：不撑满时按钮组按内容居中，夹在整列
                // 全宽字段中间显得散乱。
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<AuthMethod>(
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
                      // 本平台没有 agent 时不给这个入口；主机预设就是 Agent
                      // 时仍要展示，否则保存的取值在界面上无从呈现。
                      if (sshAgentSupported || _auth == AuthMethod.agent)
                        ButtonSegment(
                          value: AuthMethod.agent,
                          label: Text(l10n.authAgent),
                          icon: const Icon(Icons.extension_outlined, size: 16),
                        ),
                    ],
                    selected: {_auth},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        setState(() => _auth = selection.first),
                  ),
                ),
                if (_auth == AuthMethod.agent) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.agentAuthHint,
                    style: TextStyle(fontSize: 12, color: theme.secondaryText),
                  ),
                ],
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
