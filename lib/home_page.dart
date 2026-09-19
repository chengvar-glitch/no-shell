import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_locale.dart';
import 'host_transfer.dart';
import 'l10n/generated/app_localizations.dart';
import 'models.dart';
import 'ssh/connect_flow.dart';
import 'ssh/credential_store.dart';
import 'ssh/host_key_store.dart';
import 'ssh/session_manager.dart';
import 'shell_layout.dart';
import 'store.dart';
import 'widgets/host_form.dart';
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

  /// 双击主机行的直连入口：选中、详情面板落到终端 Tab、没连上就发起连接。
  /// 已连接（含连接中）时只跳转——双击是「给我终端」，不是连接开关，
  /// 复用 [_toggleConnect] 会把连着的主机断开，正好反着用户的意图。
  void _quickConnect(SshServer server) {
    setState(() {
      _layout.selectedId = server.id;
      _layout.detailTab = kTerminalTabIndex;
    });
    final active = widget.sessions
        .sessionsOf(server.id)
        .any((session) => session.isActive);
    if (!active) unawaited(_toggleConnect(server));
  }

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
    final l10n = AppLocalizations.of(context);
    final index = await confirmAndDeleteHost(
      context,
      store: widget.store,
      sessions: widget.sessions,
      credentials: widget.credentials,
      hostKeys: widget.hostKeys,
      server: server,
    );
    if (index == null || !mounted) return;
    if (_selectedId == server.id) setState(() => _layout.selectedId = null);
    // 撤销条只是兜底：删除本身不可恢复，但插回原位比让用户重填一遍强。
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
              onQuickConnect: _quickConnect,
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
              // Tab 下标归 _layout 持有：双击直连改写它，用户切 Tab 写回它。
              detailTab: _layout.detailTab,
              onDetailTabChanged: (index) => _layout.detailTab = index,
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
  late final _form = HostFormController(
    initial: widget.initial,
    initialGroup: widget.initialGroup,
    credentials: widget.credentials,
    onChanged: () {
      if (mounted) setState(() {});
    },
  );

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final saved = await _form.build(context: context);
    if (saved == null || !mounted) return;
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(_form.isEditing ? l10n.editConnection : l10n.newConnection),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form.formKey,
          child: SingleChildScrollView(
            child: HostFormFields(
              controller: _form,
              groups: widget.groupNames,
              servers: widget.servers,
              onChanged: () => setState(() {}),
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
