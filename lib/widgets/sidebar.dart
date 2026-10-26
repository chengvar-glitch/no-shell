import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app_locale.dart';
import '../host_transfer.dart';
import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../ssh/session_manager.dart';
import '../store.dart';
import '../theme.dart';
import '../update_check.dart';
import 'group_controls.dart';
import 'settings_controls.dart';
import 'shortcut_help_dialog.dart';
import 'status_badges.dart';
import 'app_icon_mark.dart';
import 'window_caption.dart';

// 侧边栏的几何全部从这里取，别再往各控件里散落数字：此前头部、搜索框、
// 分组头、主机行、底部设置入口各自写了一套内外边距，图标列对不上，
// 整条侧边栏看起来是「一堆靠自己居中凑齐的行」。

/// 整块内容距离侧边栏左右边缘的留白。
const double _kSidebarGutter = 12;

/// 分组头 / 主机行这类整行可点条目再往里让出的量：悬停底色、选中底色
/// 都落在这一圈内缩后的圆角矩形里，与侧边栏边缘保持同一道视觉留白。
const double _kRowInset = 8;

/// 行左侧图标列的宽度：分组头、主机行、底部设置入口的行首图标 / 状态点
/// 都在这条竖线上居中，往下扫一眼就是一列。
const double _kRowLeadingWidth = 24;

/// 主机行与分组头的行高：两者的悬停块一样高，扫下来才是同一张表。
const double _kRowHeight = 46;

/// 行内元素之间的固定间距。
const double _kRowGap = 10;

/// 行内右侧动作按钮的命中区（主机行的连接 / 分组头的「⋯」）。
/// 行高按它算：上下各留 9，刚好落在 [_kRowHeight] 里。
const double _kRowActionSize = 28;

/// 行内左右内边距：图标列从行内缩之后的这条线排起；文字起点还要再加
/// 图标列宽 [_kRowLeadingWidth] 与间距 [_kRowGap]。
const double _kRowPadding = 10;

/// 整行悬停 / 选中底色的圆角。
const double _kRowRadius = 8;

/// 侧边栏头部与底部动作按钮的命中区。比行内动作大一档：它们是常驻入口，
/// 命中的容错更重要。
const double _kHeaderActionSize = 32;

/// 头部动作按钮的字形尺寸。
const double _kHeaderActionIconSize = 18;

/// 搜索框高度：比设置面板里的下拉框（40）矮一档，和列表行贴得更近。
/// 只作最小高度用：大字号下输入框能自己撑开，不被裁。
const double _kSearchFieldHeight = 36;

/// 标题 / 正文 / 次要文字三档字号。侧边栏与设置面板共用同一套层级：
/// 13 是正文（主机名、行标签），11.5 是次要信息（地址、数量、键位）。
const double _kSidebarTitleFontSize = 13;
const double _kSidebarSecondaryFontSize = 11.5;

/// 桌面端连接侧边栏。
/// 头部是「收起 / 导入导出 / 新建」三个同级动作，底部只留设置入口：
/// 主题、语言都收进设置，避免同一件事在两个地方各摆一个按钮。
class Sidebar extends StatefulWidget {
  const Sidebar({
    super.key,
    required this.store,
    required this.sessions,
    required this.selectedId,
    required this.onSelect,
    required this.onQuickConnect,
    required this.onCreate,
    required this.onCreateInGroup,
    required this.onEdit,
    required this.onDelete,
    required this.onCopyHostInfo,
    required this.onToggleConnect,
    required this.onCreateSession,
    required this.onToggleSidebar,
    required this.onOpenSettings,
    required this.onImportHosts,
    required this.onExportHosts,
    this.searchFocusNode,
    this.updateCheck,
  });

  final ServerStore store;

  /// 会话注册表：只用来判断某台主机还有没有会话（「新建会话」菜单项的
  /// 显示条件）。主机行本身不展示会话数——那点像素留给详情面板的胶囊。
  final SessionManager sessions;
  final String? selectedId;
  final ValueChanged<SshServer> onSelect;

  /// 双击主机行的直连入口：选中、落终端 Tab、没连上就发起连接。
  /// 已连接时只跳转不断开——双击是「给我终端」，不是连接开关。
  final ValueChanged<SshServer> onQuickConnect;
  final VoidCallback onCreate;
  final ValueChanged<String> onCreateInGroup;
  final ValueChanged<SshServer> onEdit;
  final ValueChanged<SshServer> onDelete;

  /// 复制这台主机的连接信息文本（含已记住的密码），由宿主页面读凭据。
  final ValueChanged<SshServer> onCopyHostInfo;
  final ValueChanged<SshServer> onToggleConnect;
  final ValueChanged<SshServer> onCreateSession;
  final VoidCallback onToggleSidebar;
  final VoidCallback onOpenSettings;
  final VoidCallback onImportHosts;
  final VoidCallback onExportHosts;

  /// 搜索框的焦点节点；由宿主页面持有（⌘F 直达搜索）。为 null 时输入框
  /// 自理焦点，行为与从前一致。
  final FocusNode? searchFocusNode;

  /// 版本检测；为 null 时底部设置入口不挂「有新版本」红点。
  final UpdateCheckService? updateCheck;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  /// 搜索关键词内聚在侧边栏：输入时只重建本子树，不惊动详情面板与终端。
  /// 搜索关键词走 ValueNotifier：每次输入只重建「输入框后缀 + 列表」这两
  /// 棵子树，不把 setState 上抛到整个侧边栏（头部 / 三个动作按钮 / 底部
  /// 都会跟着重建）。移动端主机页用的是同一套做法。
  final ValueNotifier<String> _query = ValueNotifier('');

  /// store 一变就重建本子树。
  ///
  /// 侧边栏是主机列表与状态点的唯一渲染方，自己订阅之后，HomePage 就不必
  /// 为「别的某台主机连上了 / 改了名」把整页（含终端与 SFTP 保活子树）
  /// 重画一遍——详情面板只关心它当前选中的那一台。
  void _onStoreChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void didUpdateWidget(Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStoreChanged);
      widget.store.addListener(_onStoreChanged);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _query.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _showContextMenu(SshServer server, Offset position) async {
    final l10n = AppLocalizations.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    // 这台主机还挂着会话时，右键菜单里多一项「新建会话」（多开终端）：
    // 右键菜单不占常驻像素，是详情面板那枚 ⊕ 之外的第二个入口。
    final hasSession = widget.sessions.sessionCountOf(server.id) > 0;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'connect',
          height: kMenuItemHeight,
          child: Row(
            children: [
              // connecting 也算活跃：此刻按下走的是断开，按钮不许再画
              // 「连接」——connecting 只有几秒，但那几秒所示与所做是反的。
              Icon(
                server.status == ServerStatus.connected ||
                        server.status == ServerStatus.connecting
                    ? Icons.link_off_rounded
                    : Icons.play_arrow_rounded,
                size: kMenuItemIconSize,
              ),
              const SizedBox(width: kMenuItemIconGap),
              Text(
                server.status == ServerStatus.connected ||
                        server.status == ServerStatus.connecting
                    ? l10n.disconnect
                    : l10n.connect,
                style: const TextStyle(fontSize: kMenuItemFontSize),
              ),
            ],
          ),
        ),
        if (hasSession)
          PopupMenuItem(
            value: 'new-session',
            height: kMenuItemHeight,
            child: Row(
              children: [
                const Icon(Icons.add_rounded, size: kMenuItemIconSize),
                const SizedBox(width: kMenuItemIconGap),
                Text(
                  l10n.newSession,
                  style: const TextStyle(fontSize: kMenuItemFontSize),
                ),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'copy',
          height: kMenuItemHeight,
          child: Row(
            children: [
              const Icon(Icons.copy_rounded, size: kMenuItemIconSize),
              const SizedBox(width: kMenuItemIconGap),
              Text(
                l10n.copyHostInfo,
                style: const TextStyle(fontSize: kMenuItemFontSize),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          height: kMenuItemHeight,
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, size: kMenuItemIconSize),
              const SizedBox(width: kMenuItemIconGap),
              Text(
                l10n.edit,
                style: const TextStyle(fontSize: kMenuItemFontSize),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'move',
          height: kMenuItemHeight,
          child: Row(
            children: [
              const Icon(
                Icons.drive_file_move_outline,
                size: kMenuItemIconSize,
              ),
              const SizedBox(width: kMenuItemIconGap),
              Text(
                l10n.groupMoveTo,
                style: const TextStyle(fontSize: kMenuItemFontSize),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          height: kMenuItemHeight,
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: kMenuItemIconSize,
                color: AppPalette.danger,
              ),
              const SizedBox(width: kMenuItemIconGap),
              Text(
                l10n.delete,
                style: TextStyle(
                  fontSize: kMenuItemFontSize,
                  color: AppPalette.danger,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'connect':
        widget.onToggleConnect(server);
      case 'new-session':
        widget.onCreateSession(server);
      case 'copy':
        widget.onCopyHostInfo(server);
      case 'edit':
        widget.onEdit(server);
      case 'move':
        await moveServerToGroupFlow(
          context,
          store: widget.store,
          server: server,
        );
      case 'delete':
        widget.onDelete(server);
    }
  }

  /// 分组头的操作菜单：重命名 / 在此分组新建 / 上下移 / 删除。
  /// 与主机行一样，右键任意位置或点右侧「⋯」都能唤出。
  Future<void> _showGroupMenu(ServerGroup group, Offset position) async {
    final l10n = AppLocalizations.of(context);
    final index = widget.store.groupNames.indexOf(group.name);
    final last = widget.store.groupNames.length - 1;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<GroupAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final item in groupMenuItems(l10n, index: index, last: last)) ...[
          if (item.action == GroupAction.delete) const PopupMenuDivider(),
          PopupMenuItem(
            value: item.action,
            height: kMenuItemHeight,
            enabled: item.enabled,
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: kMenuItemIconSize,
                  color: item.action == GroupAction.delete
                      ? AppPalette.danger
                      : null,
                ),
                const SizedBox(width: kMenuItemIconGap),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: kMenuItemFontSize,
                    color: item.action == GroupAction.delete
                        ? AppPalette.danger
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
    if (!mounted || action == null) return;
    await runGroupAction(
      context,
      store: widget.store,
      action: action,
      group: group.name,
      onCreateInGroup: () => widget.onCreateInGroup(group.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 不铺自己的底色：侧边栏与内容区同色（页面底色），分界靠留白与行悬停底色，
    // 与访达的侧栏一样没有分隔线。整块透明还有个好处：InkWell 的水波直接画在
    // Scaffold 的 Material 上，悬停反馈天然可见，不必再补一层透明 Material。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(theme),
        _buildSearchField(theme),
        const SizedBox(height: 6),
        Expanded(child: _buildList()),
        _buildFooter(theme),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    // 品牌区：图标 + 应用名 + 主机数。
    final brand = Expanded(
      child: Row(
        children: [
          // 品牌标 28px：在 48px 标题区里上下各留 10px，不再贴边。
          const AppIconMark(size: 28),
          const SizedBox(width: _kRowGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.appName,
                  // 头部高度固定为标题条一行，文本必须单行省略：
                  // 侧边栏可收窄到 220px，换行会把这一行撑破。
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    letterSpacing: 0.1,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.hostCount(widget.store.serverCount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: _kSidebarSecondaryFontSize,
                    height: 1.2,
                    color: theme.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    // Windows/Linux：自绘标题条是详情面板里的真实一行，侧边栏头部与它同高对齐，
    // 整块头部顶到窗口最上沿——顶部不再留白，也就没有独立标题栏的观感。
    // 头部空白处也能拖动窗口；按钮照旧可点（点击与拖拽在竞技场里各归各的）。
    if (usesCustomWindowCaption) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(_kSidebarGutter, 0, 6, 8),
        child: WindowDragRegion(
          key: const ValueKey('sidebar-header-drag'),
          child: SizedBox(
            height: kWindowCaptionHeight,
            child: Row(children: [brand, ..._headerActions()]),
          ),
        ),
      );
    }
    // macOS：品牌区不摆（应用身份交给系统菜单栏），头部只留三个动作按钮、
    // 靠右排；行高 54 让按钮垂直中心落在红绿灯中心线上（y≈27pt，即原生
    // trafficLightTopInset 20pt + 半个灯高），整行平行于红绿灯。
    if (usesFloatingTrafficLights) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: SizedBox(
          height: 54,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: _headerActions(),
          ),
        ),
      );
    }
    // 其余平台（web 桌面宽屏）：顶部没有窗口按钮，头部照旧带动作整体排布。
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kSidebarGutter, 10, 6, 8),
      child: Row(children: [brand, ..._headerActions()]),
    );
  }

  /// 头部动作三件套：收起侧边栏 / 导入导出 / 新建。
  /// Windows/Linux 排在品牌区右侧；macOS 独占头部行（与红绿灯齐平，
  /// 详情面板头部同高对齐，见 server_detail 的头部行高 54）。
  List<Widget> _headerActions() => [
    _collapseAction(),
    // 注意 PopupMenuButton.constraints 约束的是菜单本身，不是图标按钮，
    // 命中区尺寸只能靠外层 SizedBox 保证。
    SizedBox(
      width: _kHeaderActionSize,
      height: _kHeaderActionSize,
      child: PopupMenuButton<HostTransferAction>(
        tooltip: AppLocalizations.of(context).importExportHosts,
        icon: const Icon(
          Icons.import_export_rounded,
          size: _kHeaderActionIconSize,
        ),
        padding: EdgeInsets.zero,
        iconSize: _kHeaderActionIconSize,
        onSelected: (action) {
          switch (action) {
            case HostTransferAction.import:
              widget.onImportHosts();
            case HostTransferAction.export:
              widget.onExportHosts();
          }
        },
        itemBuilder: (menuContext) {
          final menuL10n = AppLocalizations.of(menuContext);
          return [
            for (final item in hostTransferMenuItems(menuL10n))
              PopupMenuItem(
                value: item.action,
                height: kMenuItemHeight,
                child: Row(
                  children: [
                    Icon(item.icon, size: kMenuItemIconSize),
                    const SizedBox(width: kMenuItemIconGap),
                    Text(
                      item.label,
                      style: const TextStyle(fontSize: kMenuItemFontSize),
                    ),
                  ],
                ),
              ),
          ];
        },
      ),
    ),
    _headerAction(
      icon: Icons.add_rounded,
      tooltip: AppLocalizations.of(context)
          .newConnectionWithShortcut(newConnectionShortcut),
      onPressed: widget.onCreate,
      size: 19,
    ),
  ];

  Widget _collapseAction() {
    return _headerAction(
      icon: Icons.menu_open,
      tooltip: AppLocalizations.of(context)
          .collapseSidebar(sidebarToggleShortcut),
      onPressed: widget.onToggleSidebar,
    );
  }

  /// 头部动作按钮：统一 [_kHeaderActionSize] 命中区、无内边距，在 48px
  /// 标题区里垂直居中，视觉密度与窗口按钮一致。
  Widget _headerAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    double size = _kHeaderActionIconSize,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: size),
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(
        width: _kHeaderActionSize,
        height: _kHeaderActionSize,
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      // 与头部、底部入口同一列留白：搜索框左右边缘对齐行内缩后的块。
      padding: const EdgeInsets.symmetric(horizontal: _kSidebarGutter),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _kSearchFieldHeight),
        child: TextField(
          controller: _searchController,
          focusNode: widget.searchFocusNode,
          onChanged: (value) => _query.value = value,
          style: const TextStyle(fontSize: _kSidebarTitleFontSize),
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            // 搜索主机是 ⌘F / Ctrl+F 的去向，占位符里直接标出键位。
            hintText: l10n.withShortcut(
              l10n.shortcutSearchHosts,
              searchHostsShortcut,
            ),
            hintStyle: TextStyle(
              fontSize: _kSidebarTitleFontSize,
              color: theme.secondaryText,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 16,
              color: theme.secondaryText,
            ),
            // 放大镜与行首图标列**中心**落在同一竖线上（槽宽 36、图标列 24，
            // 两者中心都在 x=30；宽度不必相等）：搜索开合时整列不跳。
            prefixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            // 清除按钮只在有输入时出现：这里单独订阅关键词，
            // 免得每次输入都把整个输入框（乃至侧边栏）重建一遍。
            suffixIcon: ValueListenableBuilder<String>(
              valueListenable: _query,
              builder: (context, query, _) => query.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: theme.secondaryText,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        _query.value = '';
                      },
                    ),
            ),
            fillColor: theme.hoverOverlay,
          ),
        ),
      ),
    );
  }

  /// 列表订阅搜索关键词：输入只重建这一棵子树。
  Widget _buildList() => ValueListenableBuilder<String>(
    valueListenable: _query,
    builder: (context, query, _) => _buildRows(query),
  );

  Widget _buildRows(String query) {
    // 搜索时强制展开所有分组，保证结果可见；平时折叠态由 store 记着（落盘）。
    final searching = query.isNotEmpty;
    // 扁平化为「分组头 / 主机行」序列，交给 ListView.builder 懒构建，
    // 仅可见行会真正创建 Widget，主机数量多时不再整表一次性构建。
    final groups = widget.store.groups(query: query);
    final rows = <Object>[];
    for (final group in groups) {
      rows.add(group);
      if (searching || !group.collapsed) {
        for (final server in group.servers) {
          rows.add(server);
        }
      }
    }
    if (rows.isEmpty) {
      // 与移动端同一套区分：库里本来就没有主机 ≠ 搜索没有命中。
      return _SidebarEmptyState(hasHosts: widget.store.serverCount > 0);
    }
    return Scrollbar(
      controller: _scrollController,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 12),
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          if (row is ServerGroup) {
            return _GroupHeader(
              group: row,
              // 搜索时已强制展开，这里点一下就是「退出搜索再折叠」，
              // 不如直接忽略点击，避免状态对不上。
              onToggle: searching
                  ? null
                  : () => widget.store.setGroupCollapsed(
                      row.name,
                      !row.collapsed,
                    ),
              onMenu: (offset) => _showGroupMenu(row, offset),
            );
          }
          final server = row as SshServer;
          return _ServerTile(
            server: server,
            selected: server.id == widget.selectedId,
            onTap: () => widget.onSelect(server),
            onDoubleTap: () => widget.onQuickConnect(server),
            onToggleConnect: () => widget.onToggleConnect(server),
            onContextMenu: (offset) => _showContextMenu(server, offset),
          );
        },
      ),
    );
  }

  /// 底部只剩设置入口：主题 / 语言 / 导入导出都收进了设置与头部，
  /// 这里保留一个带文字的整行入口，比一枚孤零零的图标更好找。
  /// 行尾是设置与快捷键帮助的键位标注（⌘, / ⌘/），帮助弹窗从行尾的
  /// 键盘按钮进——快捷键没有菜单项可挂，这是它的常驻入口。
  Widget _buildFooter(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 不再画横线：列表底部留白 + 这一行的悬停底色已经把它和主机列表分开。
        Padding(
          padding: const EdgeInsets.fromLTRB(_kRowInset, 4, _kRowInset, 6),
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: l10n.shortcutOpenSettingsWithShortcut(
                    openSettingsShortcut,
                  ),
                  child: InkWell(
                    onTap: widget.onOpenSettings,
                    borderRadius: BorderRadius.circular(_kRowRadius),
                    hoverColor: theme.rowHover,
                    child: ConstrainedBox(
                      // 最小高度而不是写死：常态仍是 [_kRowHeight]，大字号下
                      // 行能自己撑开（与主机行同一个约定）。
                      constraints: const BoxConstraints(minHeight: _kRowHeight),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: _kRowPadding,
                        ),
                        child: Row(
                          children: [
                            // 图标槽与主机行同为一行图标列，设置入口的齿轮
                            // 落在状态点那条竖线上。
                            SizedBox(
                              width: _kRowLeadingWidth,
                              child: Center(
                                child: _SettingsEntryIcon(
                                  updateCheck: widget.updateCheck,
                                ),
                              ),
                            ),
                            const SizedBox(width: _kRowGap),
                            Expanded(
                              child: Text(
                                l10n.navSettings,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: _kSidebarTitleFontSize,
                                  fontWeight: FontWeight.w500,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.88,
                                  ),
                                ),
                              ),
                            ),
                            // 键位标注：悬停提示之外的常驻提示，窄行放不下
                            // 完整句子，只放键位本身。
                            Text(
                              openSettingsShortcut,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.secondaryText.withValues(
                                  alpha: 0.75,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 快捷键帮助（⌘/）：图标按钮不抢焦点体系之外的任何东西，
              // 弹窗是只读的，看完即走。命中区与设置行同高，二者底边对齐。
              SizedBox(
                width: _kHeaderActionSize,
                height: _kHeaderActionSize,
                child: IconButton(
                  tooltip: l10n.shortcutShortcutsHelpWithShortcut(
                    shortcutsHelpShortcut,
                  ),
                  icon: Icon(
                    Icons.keyboard_outlined,
                    size: _kHeaderActionIconSize,
                    color: theme.secondaryText,
                  ),
                  onPressed: () => showShortcutHelpDialog(context),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 设置入口的图标：有新版本时右上角挂一个红点。
/// 只订阅检测状态——侧边栏主机列表不该因为一次版本查询重建。
class _SettingsEntryIcon extends StatelessWidget {
  const _SettingsEntryIcon({this.updateCheck});

  final UpdateCheckService? updateCheck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = Icon(
      Icons.settings_outlined,
      size: 18,
      color: theme.secondaryText,
    );
    final service = updateCheck;
    if (service == null) return icon;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          icon,
          if (service.updateAvailable)
            const Positioned(
              right: -3,
              top: -3,
              child: UpdateAvailableDot(size: 8),
            ),
        ],
      ),
    );
  }
}

/// 侧边栏空态：图标 + 一句主文案 + 一句引导，比单行灰字更像个正经产品。
/// 文案与移动端 [ServersTab] 同一套 key，只有引导语按桌面端改（+ 在头部）。
class _SidebarEmptyState extends StatelessWidget {
  const _SidebarEmptyState({required this.hasHosts});

  /// 库里是否已有主机：区分「还没有主机」与「搜索没有命中」。
  final bool hasHosts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasHosts ? Icons.search_off_rounded : Icons.lan_outlined,
              size: 28,
              color: theme.secondaryText.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 10),
            Text(
              hasHosts ? l10n.noMatchingHosts : l10n.noHostsYet,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hasHosts ? l10n.tryAnotherKeyword : l10n.noHostsHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: theme.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分组头：整行可点折叠，「⋯」与右键唤出分组操作菜单。
/// 折叠态由 store 持有，这里只读。
class _GroupHeader extends StatefulWidget {
  const _GroupHeader({
    required this.group,
    required this.onToggle,
    required this.onMenu,
  });

  final ServerGroup group;

  /// 搜索态下为 null（结果强制展开，折叠没有意义）。
  final VoidCallback? onToggle;
  final ValueChanged<Offset> onMenu;

  @override
  State<_GroupHeader> createState() => _GroupHeaderState();
}

class _GroupHeaderState extends State<_GroupHeader> {
  final _menuKey = GlobalKey();
  bool _hovered = false;

  /// 「⋯」按钮的右下角作为菜单锚点，和右键走同一个回调。
  void _openMenu() {
    final box = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    widget.onMenu(box.localToGlobal(box.size.bottomRight(Offset.zero)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final collapsed = widget.group.collapsed;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onSecondaryTapUp: (details) => widget.onMenu(details.globalPosition),
        // 与主机行同一套悬停几何：同一圈内缩、同一个圆角、同一个底色 token，
        // 行高也一致——分组头与主机行是一张表里的两种行，高度不许不一样。
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _kRowInset,
            vertical: 1,
          ),
          child: InkWell(
            onTap: widget.onToggle,
            borderRadius: BorderRadius.circular(_kRowRadius),
            hoverColor: theme.rowHover,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _kRowHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _kRowPadding),
                child: Row(
                  children: [
                    // 行首图标列：折叠箭头在图标列里居中，文字起点与主机名
                    // 对齐；箭头比图标小，所以单独居中而不是贴左。
                    SizedBox(
                      width: _kRowLeadingWidth,
                      child: Center(
                        child: AnimatedRotation(
                          turns: collapsed ? -0.25 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: theme.secondaryText,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: _kRowGap),
                    Expanded(
                      child: Text(
                        widget.group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // 不加 letterSpacing：它会给每个字形右侧留白，
                        // 分组名的首字因此比主机名右移半个间距，一列文字
                        // 看着是歪的（小字号上尤其明显）。分组名与主机名
                        // 靠字号 + 颜色区分层级就够了。
                        style: TextStyle(
                          fontSize: _kSidebarSecondaryFontSize,
                          fontWeight: FontWeight.w600,
                          color: theme.secondaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 数量跟「⋯」同占一个尾部位置：数量一直在、只是变得
                    // 更淡，所以「⋯」出现 / 消失时它不会左右跳。
                    Text(
                      '${widget.group.servers.length}',
                      style: TextStyle(
                        fontSize: 11,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: theme.secondaryText.withValues(
                          alpha: _hovered ? 0.35 : 0.7,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 120),
                      opacity: _hovered ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !_hovered,
                        child: IconButton(
                          key: _menuKey,
                          tooltip: l10n.moreActions,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: _kRowActionSize,
                            height: _kRowActionSize,
                          ),
                          iconSize: 16,
                          icon: Icon(
                            Icons.more_horiz_rounded,
                            color: theme.secondaryText,
                          ),
                          onPressed: _openMenu,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerTile extends StatefulWidget {
  const _ServerTile({
    required this.server,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onToggleConnect,
    required this.onContextMenu,
  });

  final SshServer server;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onToggleConnect;
  final ValueChanged<Offset> onContextMenu;

  @override
  State<_ServerTile> createState() => _ServerTileState();
}

class _ServerTileState extends State<_ServerTile> {
  bool _hovered = false;

  /// 双击检测自己做，不挂 InkWell.onDoubleTap：同一块 InkWell 同时注册
  /// onTap 与 onDoubleTap 时，单击会被双击手势在竞技场里扣住 300ms
  /// （kDoubleTapTimeout）才放行，单击选中跟着变得迟钝。这里让 onTap
  /// 即点即发，两次点击的间隔自己量——落在双击窗口内就升级成「直连」。
  ///
  /// 量的是**指针事件自带的 timeStamp**（引擎的单调时钟），不是
  /// `DateTime.now()`：墙钟会被系统校时 / NTP 拨回去，而组件测试里
  /// `tester.tap` 合成的按下时间戳恒为 0、假时钟也推不动墙钟——真实时间一旦
  /// 被并发跑测试拖过 300ms，本该落在窗口内的两下就被判成两次单击（这套双击
  /// 用例因此在全量跑时三不五时地红）。间隔为 0（同一次按下、测试里的合成
  /// 事件）不算双击，单击语义与从前一致。
  Duration? _downAt;
  Duration? _lastTapAt;

  /// 只记「按下」的时间戳，判定留到 onTap：拖动、右键都不会走到 [_handleTap]，
  /// 不该污染下一次点击的间隔。
  void _recordDown(PointerDownEvent event) => _downAt = event.timeStamp;

  void _handleTap() {
    final previous = _lastTapAt;
    final current = _downAt;
    _lastTapAt = current;
    final isDouble =
        previous != null &&
        current != null &&
        current > previous &&
        current - previous < kDoubleTapTimeout;
    if (isDouble) {
      widget.onDoubleTap();
    } else {
      widget.onTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final server = widget.server;
    final visible = _hovered || widget.selected;
    final subtitle = server.accountWithPort;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onSecondaryTapUp: (details) =>
            widget.onContextMenu(details.globalPosition),
        // 整行内缩 8px 后再交给 InkWell：悬停底色与选中底色落在同一个圆角
        // 矩形里。以前 AnimatedContainer 自己内缩、InkWell 的高亮却铺满整行，
        // 两层错位，行两侧会露出一圈深浅不一的边。
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _kRowInset,
            vertical: 1,
          ),
          // Listener 只旁观按下、不进手势竞技场：点击 / 拖动 / 右键的判定
          // 一个字都不变，它只负责把时间戳递进来（见 [_recordDown]）。
          child: Listener(
            onPointerDown: _recordDown,
            child: InkWell(
              onTap: _handleTap,
              borderRadius: BorderRadius.circular(_kRowRadius),
              hoverColor: theme.rowHover,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                // 最小高度而不是写死：常态仍是 [_kRowHeight]（分组头、主机行、
                // 底部入口等高），无障碍大字号下两行文字能自己撑开，不被裁。
                constraints: const BoxConstraints(minHeight: _kRowHeight),
                padding: const EdgeInsets.symmetric(horizontal: _kRowPadding),
                decoration: BoxDecoration(
                  // 悬停由 InkWell 画，这里只管选中态；选中时悬停不再叠一层。
                  color: widget.selected
                      ? theme.selectedOverlay
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(_kRowRadius),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: _kRowLeadingWidth,
                      child: Center(child: StatusDot(status: server.status)),
                    ),
                    const SizedBox(width: _kRowGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            server.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: _kSidebarTitleFontSize,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: widget.selected ? 1 : 0.88,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: _kSidebarSecondaryFontSize,
                              height: 1.2,
                              color: theme.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 120),
                      opacity: visible ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !visible,
                        child: IconButton(
                          tooltip:
                              server.status == ServerStatus.connected ||
                                  server.status == ServerStatus.connecting
                              ? l10n.disconnect
                              : l10n.connect,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: _kRowActionSize,
                            height: _kRowActionSize,
                          ),
                          iconSize: 17,
                          icon: Icon(
                            server.status == ServerStatus.connected ||
                                    server.status == ServerStatus.connecting
                                ? Icons.link_off_rounded
                                : Icons.play_arrow_rounded,
                            color: theme.secondaryText,
                          ),
                          onPressed: widget.onToggleConnect,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
