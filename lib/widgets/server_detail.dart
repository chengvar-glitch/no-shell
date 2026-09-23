import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_locale.dart';
import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../settings.dart';
import '../ssh/connect_flow.dart';
import '../ssh/credential_store.dart';
import '../ssh/session_manager.dart';
import '../ssh/terminal_session.dart';
import '../ssh/terminal_view.dart';
import '../store.dart';
import '../theme.dart';
import 'port_forward_panel.dart';
import 'session_idle_view.dart';
import 'session_menu.dart';
import 'session_selection.dart';
import 'sftp_browser.dart';
import 'status_badges.dart';
import 'window_caption.dart';
import 'confirm_dialog.dart';

class ServerDetailPanel extends StatelessWidget {
  const ServerDetailPanel({
    super.key,
    required this.server,
    required this.store,
    required this.sessions,
    required this.credentials,
    required this.onConnect,
    required this.onCreate,
    this.sidebarCollapsed = false,
    this.onToggleSidebar,
    this.detailTab = kOverviewTabIndex,
    this.onDetailTabChanged,
  });

  final SshServer? server;
  final ServerStore store;
  final SessionManager sessions;

  /// 凭据存储：「新建会话」要按存档凭据 / 现有会话手头的凭据决定弹不弹框。
  final CredentialStore credentials;
  final ValueChanged<SshServer> onConnect;
  final VoidCallback onCreate;
  final bool sidebarCollapsed;
  final VoidCallback? onToggleSidebar;

  /// 外部想要的 Tab 下标（双击直连落终端）；用户自己切 Tab 经
  /// [onDetailTabChanged] 写回持有方，双向各走一条路。
  final int detailTab;
  final ValueChanged<int>? onDetailTabChanged;

  @override
  Widget build(BuildContext context) {
    final selected = server;
    if (selected == null) {
      return _EmptyState(
        onCreate: onCreate,
        sidebarCollapsed: sidebarCollapsed,
        onToggleSidebar: onToggleSidebar,
      );
    }
    return _ServerDetail(
      server: selected,
      store: store,
      sessions: sessions,
      credentials: credentials,
      onConnect: () => onConnect(selected),
      sidebarCollapsed: sidebarCollapsed,
      onToggleSidebar: onToggleSidebar,
      detailTab: detailTab,
      onDetailTabChanged: onDetailTabChanged,
    );
  }
}

/// 详情面板四个 Tab 的固定下标（概览 / 终端 / SFTP / 转发）。
/// 双击主机行直连等外部入口要把面板带到终端，跨文件按下标取。
const kOverviewTabIndex = 0;
const kTerminalTabIndex = 1;

/// 无主机选中（空态）时的展开入口：macOS 上红绿灯浮在内容左上角，按钮与
/// 它们同一行、位于其右侧；其余非自绘标题条平台排在面板左上角。
/// 有主机选中的详情头部走行内 [_ExpandSidebarButton]，不用这个浮动版本。
Widget? _sidebarExpandButton(
  BuildContext context,
  bool collapsed,
  VoidCallback? onToggle,
) {
  if (!collapsed || onToggle == null) return null;
  final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
  return Align(
    alignment: Alignment.topLeft,
    child: Padding(
      // macOS：红绿灯垂直中心 y≈27（trafficLightTopInset 20 + 半个灯高 7），
      // 按钮（高 26）在 54pt 头部行内垂直居中（top 14）落在同一条中心线上，
      // 缩进 96 与收起态详情头部同一列；其余平台照旧贴面板左上角。
      padding: EdgeInsets.only(
        left: isMacOS ? kMacOSTrafficLightsIndent : 6,
        top: isMacOS ? kMacOSTrafficLightsCenterY - 13 : windowTopInset(6.0),
      ),
      child: IconButton(
        tooltip: AppLocalizations.of(context)
            .expandSidebar(sidebarToggleShortcut),
        icon: const Icon(Icons.view_sidebar, size: 17),
        onPressed: onToggle,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 30, height: 26),
      ),
    ),
  );
}

/// 行内版展开侧边栏按钮：与侧边栏头部、详情头部的动作按钮同一套尺寸。
/// 收起侧边栏后它排在标题条这一行里（跟着行内走），而不是浮到内容左上角。
class _ExpandSidebarButton extends StatelessWidget {
  const _ExpandSidebarButton({required this.onToggle});

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: AppLocalizations.of(context)
          .expandSidebar(sidebarToggleShortcut),
      icon: const Icon(Icons.view_sidebar, size: 18),
      onPressed: onToggle,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onCreate,
    required this.sidebarCollapsed,
    required this.onToggleSidebar,
  });

  final VoidCallback onCreate;
  final bool sidebarCollapsed;
  final VoidCallback? onToggleSidebar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final expandable = sidebarCollapsed && onToggleSidebar != null;
    final content = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: theme.panelBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.hairline),
            ),
            child: Icon(
              Icons.lan_outlined,
              size: 32,
              color: theme.secondaryText,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            l10n.selectHostToStart,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.emptyDetailHint,
            style: TextStyle(fontSize: 12.5, color: theme.secondaryText),
          ),
          const SizedBox(height: 22),
          FilledButton.tonalIcon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded, size: 17),
            label: Text(l10n.newConnection),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.comfortable,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    // Windows/Linux：自绘标题条本来就是面板里的第一行，展开按钮排进这一行，
    // 与窗口按钮同行——不会再浮在内容左上角、看起来像掉到了下一行。
    if (usesCustomWindowCaption) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WindowCaptionBar(
            leading: expandable
                ? _ExpandSidebarButton(onToggle: onToggleSidebar!)
                : null,
          ),
          Expanded(child: content),
        ],
      );
    }
    return Stack(
      children: [
        ?_sidebarExpandButton(context, sidebarCollapsed, onToggleSidebar),
        content,
      ],
    );
  }
}

class _ServerDetail extends StatefulWidget {
  const _ServerDetail({
    required this.server,
    required this.store,
    required this.sessions,
    required this.credentials,
    required this.onConnect,
    required this.sidebarCollapsed,
    required this.onToggleSidebar,
    required this.detailTab,
    this.onDetailTabChanged,
  });

  final SshServer server;
  final ServerStore store;
  final SessionManager sessions;
  final CredentialStore credentials;
  final VoidCallback onConnect;
  final bool sidebarCollapsed;
  final VoidCallback? onToggleSidebar;
  final int detailTab;
  final ValueChanged<int>? onDetailTabChanged;

  @override
  State<_ServerDetail> createState() => _ServerDetailState();
}

class _ServerDetailState extends State<_ServerDetail>
    with SessionSelectionGuard {
  /// 状态胶囊的 key：多会话时会话菜单要锚在它下方弹出。
  final GlobalKey _sessionPillKey = GlobalKey();

  @override
  SessionManager get guardedSessions => widget.sessions;

  @override
  String get guardedServerId => widget.server.id;

  @override
  void initState() {
    super.initState();
    startSessionGuard();
  }

  @override
  void didUpdateWidget(_ServerDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessions != widget.sessions) {
      rebindSessionGuard(oldWidget.sessions);
    }
    // 换了一台主机：守卫的基准跟着换，否则会拿上一台的会话数做比较。
    if (oldWidget.server.id != widget.server.id) resyncSessionGuard();
  }

  @override
  void dispose() {
    stopSessionGuard();
    super.dispose();
  }

  /// 在同一台主机上再开一条会话。凭据优先级与失败回退见 [newSessionFlow]。
  Future<void> _createSession() => newSessionFlow(
    context,
    sessions: widget.sessions,
    server: widget.server,
    credentials: widget.credentials,
    store: widget.store,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final server = widget.server;
    final session = widget.sessions.activeOf(server.id);
    final sessionCount = widget.sessions.sessionCountOf(server.id);
    final header = _DetailHeader(
      server: server,
      session: session,
      sessionCount: sessionCount,
      pillKey: _sessionPillKey,
      connected: session?.isActive ?? false,
      sessions: widget.sessions,
      sidebarCollapsed: widget.sidebarCollapsed,
      onToggleSidebar: widget.onToggleSidebar,
      onConnect: widget.onConnect,
      onCreateSession: _createSession,
    );
    final tabs = _DetailTabs(
      labels: [l10n.overview, l10n.terminal, l10n.sftp, l10n.portForwarding],
      tabIndex: widget.detailTab,
      onTabChanged: widget.onDetailTabChanged,
      children: [
        OverviewTab(
          server: server,
          // 跳板机存的是 id，概览要给人看的名字；那台主机已被删时名字为空，
          // 卡片退回显示 id，让用户看得出这条配置指着的东西不在了。
          jumpHostName: widget.store.byId(server.jumpServerId)?.name,
        ),
        TerminalTab(
          server: server,
          session: session,
          sessions: widget.sessions,
          idleHint: l10n.sessionDesktopHint,
          onRetry: session == null
              ? null
              : () => widget.sessions.retry(session),
          cursorBlink: true,
        ),
        SftpTab(
          session: session,
          idleHint: l10n.sftpSessionHint,
          onRetry: session == null
              ? null
              : () => widget.sessions.retry(session),
        ),
        PortForwardPanel(
          server: server,
          store: widget.store,
          sessions: widget.sessions,
        ),
      ],
    );

    // Windows/Linux：头部直接排进自绘标题条那一行，内容整体上移，顶部不再多出
    // 一条空白；macOS 的品牌行让给了红绿灯，头部也排进这一行（行高 54 = 红绿灯
    // 中心 y≈27pt 的两倍，在其中垂直居中），与侧边栏动作按钮同一条中心线。
    if (usesCustomWindowCaption) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WindowCaptionBar(leading: header),
          _HeaderTags(
            server: server,
            sidebarCollapsed: widget.sidebarCollapsed,
          ),
          Expanded(child: tabs),
        ],
      );
    }
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isMacOS)
              // 收起侧边栏后详情面板顶到窗口左缘，头部必须让开左上角的红绿灯
              // 区（红绿灯右缘约 82pt），起点平移到 kMacOSTrafficLightsIndent；
              // 标签行（[_HeaderTags]）以同一时长与曲线跟随，左缘保持成列。
              // 动画时长与侧边栏收起一致，名字不会从灯底下突兀地钻出来。
              AnimatedPadding(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.fromLTRB(
                  widget.sidebarCollapsed ? kMacOSTrafficLightsIndent : 16,
                  0,
                  12,
                  0,
                ),
                child: SizedBox(
                  height: 54,
                  child: Align(alignment: Alignment.centerLeft, child: header),
                ),
              )
            else
              Padding(
                padding: EdgeInsets.fromLTRB(16, windowTopInset(10.0), 12, 8),
                child: header,
              ),
            _HeaderTags(
              server: server,
              sidebarCollapsed: widget.sidebarCollapsed,
            ),
            Expanded(child: tabs),
          ],
        ),
      ],
    );
  }
}

/// 详情面板头部：服务器名 + 状态 + 操作按钮。
///
/// 操作按钮（⋯ 菜单 / 连接 / 断开连接）紧跟在名字后面而不是贴在面板右端：
/// 头部已经上移到标题条这一行，右端是窗口按钮（关闭）的位置，摆在那里会打架。
class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.server,
    required this.session,
    required this.sessionCount,
    required this.pillKey,
    required this.connected,
    required this.sessions,
    required this.sidebarCollapsed,
    required this.onToggleSidebar,
    required this.onConnect,
    required this.onCreateSession,
  });

  final SshServer server;

  /// 该主机挂着的会话；会话日志的入口在状态胶囊上，有会话才可点。
  /// 断开但未关闭的会话仍算有——日志要能事后查看。
  final TerminalSession? session;

  /// 该主机的会话条数：大于 1 时胶囊带计数、点开是会话菜单。
  final int sessionCount;

  /// 状态胶囊的 key：会话菜单锚在它下方。
  final GlobalKey pillKey;

  final bool connected;
  final SessionManager sessions;
  final bool sidebarCollapsed;
  final VoidCallback? onToggleSidebar;
  final VoidCallback onConnect;

  /// 在同一台主机上再开一条会话。
  final VoidCallback onCreateSession;

  /// 点状态胶囊：一条会话时进日志（与多会话功能之前完全一样），
  /// 多开了才换成会话菜单——菜单里照样有「会话日志」。
  /// 规则本体在 [openSessionPill]，移动端两处共用同一份。
  void _openSessions(BuildContext context) {
    if (session == null) return;
    openSessionPill(
      context,
      sessions: sessions,
      server: server,
      anchor: pillKey,
      onNewSession: onCreateSession,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // 局部变量让空检查提升进闭包：可空的字段本身不行。
    final session = this.session;
    final multi = sessionCount > 1;
    // macOS 收起态同样排进行内：头部已平移到红绿灯右侧（96pt），
    // 按钮不会与灯重叠，用户不必靠 ⌘B 也能找回侧边栏。
    final showExpand = sidebarCollapsed && onToggleSidebar != null;
    return Row(
      // 收缩包裹：头部排在标题条左侧，窄窗口下由名字省略号承担收缩。
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showExpand) ...[
          _ExpandSidebarButton(onToggle: onToggleSidebar!),
          const SizedBox(width: 2),
        ],
        Flexible(
          child: Text(
            server.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 10),
        StatusPill(
          key: pillKey,
          status: server.status,
          sessionCount: sessionCount,
          tooltip: multi ? l10n.sessionMenu : null,
          onTap: session == null ? null : () => _openSessions(context),
        ),
        // 「新建会话」只在有会话时出现：没连上时该做的是连接（右边那颗）。
        // 一枚图标，不新增一行、不新增分区。
        if (sessionCount > 0) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: l10n.newSession,
            icon: const Icon(Icons.add_rounded, size: 18),
            onPressed: onCreateSession,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          ),
        ],
        const SizedBox(width: 4),
        connected
            ? OutlinedButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.link_off_rounded, size: 15),
                label: Text(multi ? l10n.disconnectAll : l10n.disconnect),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : FilledButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.bolt_rounded, size: 15),
                label: Text(l10n.connect),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
      ],
    );
  }
}

/// 标签行：排在标题条 / 头部之下，没有标签时不占高度。
/// 始终保留在树上，避免标签增减时把 Tab 容器搬到另一个子树位置。
class _HeaderTags extends StatelessWidget {
  const _HeaderTags({required this.server, required this.sidebarCollapsed});

  final SshServer server;
  final bool sidebarCollapsed;

  @override
  Widget build(BuildContext context) {
    if (server.tags.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    // 左缘始终与头部同一列：自绘标题条行内头部左内边距 12（与侧边栏头部
    // 对齐）；macOS 头部在面板里、展开态左内边距 16，收起后头部平移到
    // 红绿灯右侧（96），标签以同一时长与曲线跟随，不再孤零零挂在
    // 红绿灯那一列。
    final isMacOS =
        !usesCustomWindowCaption &&
        defaultTargetPlatform == TargetPlatform.macOS;
    final double left = usesCustomWindowCaption
        ? 12
        : isMacOS && sidebarCollapsed
        ? kMacOSTrafficLightsIndent
        : 16;
    return AnimatedPadding(
      key: const ValueKey('detail-header-tags'),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(left, 6, 12, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final tag in server.tags) _TagChip(theme: theme, label: tag),
        ],
      ),
    );
  }
}

/// 四个 Tab 的标签栏与内容体。当前 Tab 下标由外部持有（ShellLayoutState.detailTab，
/// 双击直连要能把面板带到终端），这里双向跟随：外部改写时控制器跳过去，
/// 用户自己点 Tab 经 [onTabChanged] 写回去——写回不回流 setState，不构成环。
class _DetailTabs extends StatefulWidget {
  const _DetailTabs({
    required this.labels,
    required this.children,
    required this.tabIndex,
    this.onTabChanged,
  });

  final List<String> labels;
  final List<Widget> children;

  /// 外部想要的 Tab 下标；越界按概览处理（防御，正常只有 0…3）。
  final int tabIndex;
  final ValueChanged<int>? onTabChanged;

  @override
  State<_DetailTabs> createState() => _DetailTabsState();
}

class _DetailTabsState extends State<_DetailTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(
    length: widget.children.length,
    initialIndex: _wantedIndex,
    vsync: this,
  )..addListener(_onTabChanged);

  /// 上一次画出来的下标：动画期间控制器会连发多次通知，用它收敛成一次重建。
  int _rendered = -1;

  int get _wantedIndex =>
      widget.tabIndex.clamp(0, widget.children.length - 1).toInt();

  @override
  void didUpdateWidget(_DetailTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部入口（双击直连）改写下标时跳过去；值相同（含用户点完写回后的
    // 常规重建）不动，避免把用户刚点开的 Tab 又拽回去。
    if (widget.tabIndex != oldWidget.tabIndex &&
        widget.tabIndex != _controller.index) {
      _controller.animateTo(_wantedIndex);
    }
  }

  // 切换动画期间会多次通知，只在下标真正变化时重建。
  void _onTabChanged() {
    if (_controller.index == _rendered) return;
    _rendered = _controller.index;
    setState(() {});
    widget.onTabChanged?.call(_controller.index);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTabChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _controller,
          tabs: [for (final label in widget.labels) Tab(text: label)],
          onTap: (_) => FocusScope.of(context).unfocus(),
        ),
        Expanded(
          child: _DetailTabView(
            index: _controller.index,
            children: widget.children,
          ),
        ),
      ],
    );
  }
}

/// 常驻保活的 Tab 内容体：四个 Tab 始终参与布局（xterm 视图、SFTP 列表切走再
/// 切回不需要重建），但只画当前这一个。
///
/// 这里不用 IndexedStack：它的 index 变化会 markNeedsLayout，整棵子树（终端
/// 字符度量 + SFTP 列表）每次切换都要重新布局，实测一帧要几十毫秒，表现就是
/// 切 Tab 卡顿、有顿挫感。Visibility(maintainSize: true) 只 markNeedsPaint，
/// 隐藏的 Tab 保留布局尺寸，同时跳过绘制 / 命中 / 语义（等价于 IndexedStack
/// 的可见性语义），切换因此退化成一次重绘。
class _DetailTabView extends StatelessWidget {
  const _DetailTabView({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          Visibility(
            visible: i == index,
            maintainSize: true,
            maintainState: true,
            maintainAnimation: true,
            child: children[i],
          ),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.theme, required this.label});

  final ThemeData theme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: theme.hoverOverlay,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.hairline),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: theme.secondaryText),
      ),
    );
  }
}

class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key, required this.server, this.jumpHostName});

  final SshServer server;

  /// 跳板机的主机名，由调用方从 store 查好传进来；为空时退回显示 id。
  final String? jumpHostName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // 跳板机已被删除时名字查不到，卡片退回显示 id：让用户看得出这条配置
    // 指着的东西不在了，而不是一片空白。
    final jumpId = server.jumpServerId;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoCard(
                theme: theme,
                label: l10n.hostAddress,
                value: server.host,
                trailing: IconButton(
                  tooltip: l10n.copyAddress,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 26,
                    height: 26,
                  ),
                  iconSize: 14,
                  icon: Icon(
                    Icons.copy_rounded,
                    size: 14,
                    color: theme.secondaryText,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: server.host));
                    showToast(context, l10n.copied(server.host));
                  },
                ),
              ),
              _InfoCard(
                theme: theme,
                label: l10n.port,
                value: '${server.port}',
              ),
              _InfoCard(
                theme: theme,
                label: l10n.username,
                value: server.username,
              ),
              _InfoCard(
                theme: theme,
                label: l10n.authMethod,
                value: authMethodLabel(l10n, server.authMethod),
              ),
              _InfoCard(
                theme: theme,
                label: l10n.lastConnected,
                value: formatRelativeTime(l10n, server.lastConnectedAt),
              ),
              _InfoCard(theme: theme, label: l10n.group, value: server.group),
              // 直连的主机不摆一张写着「不使用」的卡片：那是噪音，
              // 只有真配了跳板机时才多出这张。
              if (jumpId != null)
                _InfoCard(
                  theme: theme,
                  label: l10n.jumpHost,
                  value: jumpHostName ?? jumpId,
                ),
            ],
          ),
          if (server.notes != null) ...[
            const SizedBox(height: 18),
            Text(
              l10n.notes,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: theme.secondaryText,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.panelBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.hairline),
              ),
              child: Text(
                server.notes!,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.theme,
    required this.label,
    required this.value,
    this.trailing,
  });

  final ThemeData theme;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 218,
      padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
      decoration: BoxDecoration(
        color: theme.panelBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
              color: theme.secondaryText,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ],
      ),
    );
  }
}

/// 终端 Tab 未连接时空态的形态：两端刻意不同。
/// 桌面端保持终端样式预览（占位与连上后是同一个盒子、同一套字号配色，
/// 频繁的「点连接 → 连上」过渡不跳变）；移动端换成与 SFTP Tab 一致的
/// 图标 + 提示空态——手机屏上其余 Tab 都是主题化空态，黑终端块在浅色
/// 主题下过于突兀，`$ ssh` 假命令行也容易被误读成正在连接。
enum TerminalIdleStyle {
  /// 终端样式预览画面（桌面端）。
  preview,

  /// 图标 + 标题 + 提示的普通空态（移动端）。
  plain,
}

/// 终端视图：有会话时渲染真实 SSH 终端，否则按 [idleStyle] 展示空态。
/// 桌面端详情面板与移动端详情页共用；传入 [sessions] 时终端浮层里
/// 会带上自动重连的倒计时与「停止」入口。
final class TerminalTab extends StatelessWidget {
  const TerminalTab({
    super.key,
    required this.server,
    this.session,
    this.sessions,
    this.onRetry,
    this.idleHint,
    this.idleStyle = TerminalIdleStyle.preview,
    this.cursorBlink = false,
  });

  final SshServer server;

  /// 当前主机的 SSH 会话；为空表示尚未建立，展示空态。
  final TerminalSession? session;

  /// 会话管理器；为空（部分测试）时终端不展示自动重连状态。
  final SessionManager? sessions;

  /// 失败 / 已结束时的重连动作。
  final VoidCallback? onRetry;

  /// 未连接时的提示文案，桌面端与移动端入口措辞不同。
  final String? idleHint;

  /// 未连接时空态的形态，见 [TerminalIdleStyle]。
  final TerminalIdleStyle idleStyle;

  /// 聚焦时是否让终端光标闪烁；组件测试的宿主可以不开。
  final bool cursorBlink;

  @override
  Widget build(BuildContext context) {
    final session = this.session;
    final l10n = AppLocalizations.of(context);
    if (session == null && idleStyle == TerminalIdleStyle.plain) {
      return SessionIdleView(
        icon: Icons.terminal_rounded,
        title: l10n.terminal,
        hint: idleHint ?? l10n.sessionMobileHint,
      );
    }
    // 只监听终端样式偏好：配色 / 字体变化时仅终端面板重建。
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: ValueListenableBuilder<TerminalStylePrefs>(
        valueListenable: TerminalStyleScope.of(context).notifier,
        builder: (context, prefs, _) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: prefs.theme.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).hairline),
            ),
            // RepaintBoundary 只包住终端本体：它把终端的高频重绘（输出流）
            // 隔离在内部，同时让外层边框/背景换色（如主题切换动画）只重绘
            // 容器本身，不再连带把整幅终端缓冲区按帧重画一遍。
            child: RepaintBoundary(
              child: session == null
                  ? _buildIdleOutput(context, prefs)
                  : _terminalWithReconnect(context, session),
            ),
          );
        },
      ),
    );
  }

  /// 终端视图套一层会话订阅：只有自动重连的计划变化时才重建这一小块，
  /// 会话层的其它通知不经过这里。
  Widget _terminalWithReconnect(BuildContext context, TerminalSession session) {
    Widget view(BuildContext context) => SshTerminalView(
      // 按会话换 key：xterm 的 TerminalView 不处理 `terminal` 被换掉
      // （didUpdateWidget 里没有这一条），复用同一个 State 切会话会继续画
      // 旧缓冲区。换 key 让它整棵重建，切过去的才是当前会话的画面。
      // 代价是每次切换重测一次字符宽度——比画错缓冲区划算得多。
      key: ObjectKey(session),
      session: session,
      onRetry: onRetry,
      reconnectPlan: sessions?.reconnectPlanOf(session),
      onStopAutoReconnect: sessions == null
          ? null
          : () => sessions!.cancelAutoReconnect(session),
      cursorBlink: cursorBlink,
    );
    final manager = sessions;
    return manager == null
        ? view(context)
        : ListenableBuilder(
            listenable: manager,
            builder: (context, _) => view(context),
          );
  }

  Widget _buildIdleOutput(BuildContext context, TerminalStylePrefs prefs) {
    final colors = prefs.theme;
    // 未连接时的占位输出跟着终端字号走：连上前后字号一致，不会「一跳变样」。
    final mono = TextStyle(
      fontSize: prefs.fontSize.toDouble(),
      height: 1.55,
      fontFamily: prefs.resolvedFontFamily,
      fontFamilyFallback: prefs.fontFallback,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SelectionArea(
            child: SingleChildScrollView(
              child: Text.rich(
                TextSpan(
                  style: mono,
                  children: [
                    TextSpan(
                      text: r'$ ',
                      style: TextStyle(color: colors.brightBlack),
                    ),
                    TextSpan(
                      text: 'ssh ${server.account}\n',
                      style: TextStyle(color: colors.foreground),
                    ),
                    TextSpan(
                      text:
                          idleHint ??
                          AppLocalizations.of(context).sessionDesktopHint,
                      style: TextStyle(color: colors.brightBlack),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'ssh · ${server.account}',
          style: TextStyle(
            fontSize: (prefs.fontSize - 2).clamp(9, 20).toDouble(),
            color: colors.foreground.withValues(alpha: 0.35),
          ),
        ),
      ],
    );
  }
}
