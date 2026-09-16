import 'package:flutter/material.dart';

import '../app_locale.dart';
import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'status_badges.dart';
import 'app_icon_mark.dart';
import 'window_caption.dart';

/// 桌面端连接侧边栏。
/// 头部是「收起 / 导入导出 / 新建」三个同级动作，底部只留设置入口：
/// 主题、语言都收进设置，避免同一件事在两个地方各摆一个按钮。
class Sidebar extends StatefulWidget {
  const Sidebar({
    super.key,
    required this.store,
    required this.selectedId,
    required this.onSelect,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleConnect,
    required this.onToggleSidebar,
    required this.onOpenSettings,
    required this.onImportHosts,
    required this.onExportHosts,
  });

  final ServerStore store;
  final String? selectedId;
  final ValueChanged<SshServer> onSelect;
  final VoidCallback onCreate;
  final ValueChanged<SshServer> onEdit;
  final ValueChanged<SshServer> onDelete;
  final ValueChanged<SshServer> onToggleConnect;
  final VoidCallback onToggleSidebar;
  final VoidCallback onOpenSettings;
  final VoidCallback onImportHosts;
  final VoidCallback onExportHosts;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final Set<String> _collapsedGroups = {};

  /// 搜索关键词内聚在侧边栏：输入时只重建本子树，不惊动详情面板与终端。
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _showContextMenu(SshServer server, Offset position) async {
    final l10n = AppLocalizations.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'connect',
          height: 36,
          child: Row(
            children: [
              Icon(
                server.status == ServerStatus.connected
                    ? Icons.link_off_rounded
                    : Icons.play_arrow_rounded,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                server.status == ServerStatus.connected
                    ? l10n.disconnect
                    : l10n.connect,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          height: 36,
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, size: 16),
              const SizedBox(width: 8),
              Text(l10n.edit, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          height: 36,
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 16,
                color: AppPalette.danger,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.delete,
                style: TextStyle(fontSize: 13, color: AppPalette.danger),
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
      case 'edit':
        widget.onEdit(server);
      case 'delete':
        widget.onDelete(server);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.sidebarBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme),
          _buildSearchField(theme),
          const SizedBox(height: 6),
          Expanded(child: _buildList()),
          _buildFooter(theme),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final title = Row(
      children: [
        // 品牌标 30px：在 48px 标题区里上下各留 9px，不再贴边。
        const AppIconMark(size: 30),
        const SizedBox(width: 10),
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
              const SizedBox(height: 3),
              Text(
                l10n.hostCount(widget.store.serverCount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  color: theme.secondaryText,
                ),
              ),
            ],
          ),
        ),
        _headerAction(
          icon: Icons.menu_open,
          tooltip: l10n.collapseSidebar(sidebarToggleShortcut),
          onPressed: widget.onToggleSidebar,
        ),
        // 导入 / 导出：与收起、新建同级的头部动作，排在第二位。
        // 注意 PopupMenuButton.constraints 约束的是菜单本身，不是图标按钮，
        // 命中区尺寸只能靠外层 SizedBox 保证。
        SizedBox(
          width: 34,
          height: 34,
          child: PopupMenuButton<String>(
            tooltip: l10n.importExportHosts,
            icon: const Icon(Icons.import_export_rounded, size: 18),
            padding: EdgeInsets.zero,
            iconSize: 18,
            onSelected: (action) {
              switch (action) {
                case 'import':
                  widget.onImportHosts();
                case 'export':
                  widget.onExportHosts();
              }
            },
            itemBuilder: (menuContext) {
              final menuL10n = AppLocalizations.of(menuContext);
              return [
                PopupMenuItem(
                  value: 'import',
                  height: 36,
                  child: Row(
                    children: [
                      const Icon(Icons.download_rounded, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        menuL10n.importHosts,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'export',
                  height: 36,
                  child: Row(
                    children: [
                      const Icon(Icons.upload_outlined, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        menuL10n.exportHosts,
                        style: const TextStyle(fontSize: 13),
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
          tooltip: l10n.newConnection,
          onPressed: widget.onCreate,
          size: 19,
        ),
      ],
    );
    // Windows/Linux：自绘标题条是详情面板里的真实一行，侧边栏头部与它同高对齐，
    // 整块头部顶到窗口最上沿——顶部不再留白，也就没有独立标题栏的观感。
    // 头部空白处也能拖动窗口；按钮照旧可点（点击与拖拽在竞技场里各归各的）。
    if (usesCustomWindowCaption) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 8, 10),
        child: WindowDragRegion(
          key: const ValueKey('sidebar-header-drag'),
          child: SizedBox(height: kWindowCaptionHeight, child: title),
        ),
      );
    }
    // macOS 红绿灯浮在左上角，其余平台顶部是系统手势区，头部整体下移让位。
    return Padding(
      padding: EdgeInsets.fromLTRB(12, windowTopInset(12.0), 8, 10),
      child: title,
    );
  }

  /// 头部动作按钮：统一 34×34 命中区、无内边距，在 48px 标题区里垂直居中，
  /// 视觉密度与窗口按钮一致。
  Widget _headerAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    double size = 18,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: size),
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    final hasText = _searchController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _query = value),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context).searchHint,
          hintStyle: TextStyle(fontSize: 12.5, color: theme.secondaryText),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 16,
            color: theme.secondaryText,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 34,
          ),
          suffixIcon: hasText
              ? IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: theme.secondaryText,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
          fillColor: theme.hoverOverlay,
        ),
      ),
    );
  }

  Widget _buildList() {
    // 搜索时强制展开所有分组，保证结果可见。
    // 用临时可变集合承接点击，避免误改 const 集合抛错。
    final collapsed = _query.isEmpty ? _collapsedGroups : <String>{};
    // 扁平化为「分组头 / 主机行」序列，交给 ListView.builder 懒构建，
    // 仅可见行会真正创建 Widget，主机数量多时不再整表一次性构建。
    final groups = widget.store.groups(query: _query);
    final rows = <Object>[];
    for (final group in groups) {
      rows.add(group);
      if (!collapsed.contains(group.name)) {
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
              name: row.name,
              count: row.servers.length,
              collapsed: collapsed.contains(row.name),
              onToggle: () => setState(() {
                if (!collapsed.remove(row.name)) collapsed.add(row.name);
              }),
            );
          }
          final server = row as SshServer;
          return _ServerTile(
            server: server,
            selected: server.id == widget.selectedId,
            onTap: () => widget.onSelect(server),
            onToggleConnect: () => widget.onToggleConnect(server),
            onContextMenu: (offset) => _showContextMenu(server, offset),
          );
        },
      ),
    );
  }

  /// 底部只剩设置入口：主题 / 语言 / 导入导出都收进了设置与头部，
  /// 这里保留一个带文字的整行入口，比一枚孤零零的图标更好找。
  Widget _buildFooter(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 1, color: theme.hairline),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          // 侧边栏底色是自绘的不透明 Container，InkWell 的水波默认画在它下面
          // （Scaffold 的 Material 上），悬停因此完全看不见、像一行说明文字。
          // 这里补一层透明 Material 把 ink 抬到侧边栏底色之上，悬停底色与
          // 手型光标才真的出现。
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onOpenSettings,
              borderRadius: BorderRadius.circular(8),
              hoverColor: theme.rowHover,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.settings_outlined,
                      size: 18,
                      color: theme.secondaryText,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.navSettings,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.88,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.name,
    required this.count,
    required this.collapsed,
    required this.onToggle,
  });

  final String name;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          children: [
            AnimatedRotation(
              turns: collapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 15,
                color: theme.secondaryText,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              name,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: theme.secondaryText,
              ),
            ),
            const Spacer(),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                color: theme.secondaryText.withValues(alpha: 0.7),
              ),
            ),
          ],
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
    required this.onToggleConnect,
    required this.onContextMenu,
  });

  final SshServer server;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onToggleConnect;
  final ValueChanged<Offset> onContextMenu;

  @override
  State<_ServerTile> createState() => _ServerTileState();
}

class _ServerTileState extends State<_ServerTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final server = widget.server;
    final visible = _hovered || widget.selected;
    final subtitle = server.port == 22
        ? server.account
        : '${server.account}:${server.port}';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onSecondaryTapUp: (details) =>
            widget.onContextMenu(details.globalPosition),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: widget.selected
                  ? theme.selectedOverlay
                  : _hovered
                  ? theme.hoverOverlay
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                StatusDot(status: server.status),
                const SizedBox(width: 10),
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
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
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
                          fontSize: 11.5,
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
                      tooltip: server.status == ServerStatus.connected
                          ? l10n.disconnect
                          : l10n.connect,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      iconSize: 17,
                      icon: Icon(
                        server.status == ServerStatus.connected
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
    );
  }
}
