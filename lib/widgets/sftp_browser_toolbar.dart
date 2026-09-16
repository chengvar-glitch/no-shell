// 工具条区：上级 / 面包屑路径栏 / 搜索 / 排序 / 上传等入口。
part of 'sftp_browser.dart';

/// 工具条：上级 / 面包屑 / 刷新 / 上传 / 新建目录 / 隐藏文件 / 排序。
final class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.compact,
    required this.filterOpen,
    required this.onToggleFilter,
    required this.onError,
  });

  final SftpBrowserController controller;
  final bool compact;
  final bool filterOpen;
  final VoidCallback onToggleFilter;
  final ValueChanged<Object> onError;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // 载入 / 刷新期间同样禁用写操作，避免把文件传进过期的目录。
    final busy =
        controller.isMutating ||
        controller.isLoading ||
        controller.isRefreshing;
    return Row(
      children: [
        _ToolButton(
          icon: Icons.arrow_upward_rounded,
          tooltip: l10n.sftpUp,
          onPressed: controller.isReady
              ? () => unawaited(controller.goUp())
              : null,
        ),
        const SizedBox(width: 4),
        Expanded(child: _PathBar(controller: controller)),
        const SizedBox(width: 4),
        if (!compact) ...[
          _ToolButton(
            icon: Icons.search_rounded,
            tooltip: l10n.sftpFilter,
            active: filterOpen,
            onPressed: onToggleFilter,
          ),
          _ToolButton(
            icon: controller.showHidden
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded,
            tooltip: controller.showHidden
                ? l10n.sftpHideHidden
                : l10n.sftpShowHidden,
            active: controller.showHidden,
            onPressed: controller.toggleHidden,
          ),
          _SortButton(controller: controller),
          _ToolButton(
            icon: Icons.refresh_rounded,
            tooltip: l10n.sftpRefresh,
            onPressed: () => unawaited(controller.refresh()),
          ),
          const SizedBox(width: 4),
          _ToolButton(
            icon: Icons.create_new_folder_outlined,
            tooltip: l10n.sftpNewFolder,
            onPressed: busy ? null : () => _createFolder(context, controller),
          ),
          const SizedBox(width: 4),
          FilledButton.tonalIcon(
            onPressed: busy ? null : () => _upload(context, controller),
            icon: const Icon(Icons.upload_rounded, size: 16),
            label: Text(l10n.sftpUpload),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ] else
          _CompactMenu(
            controller: controller,
            busy: busy,
            filterOpen: filterOpen,
            onToggleFilter: onToggleFilter,
          ),
        // 载入 / 传输中的转圈恒定占位：忙时画圈，闲时留白。
        // 之前是「忙了才插入」，它一出现就把 Expanded 的地址栏挤窄 20px、
        // 一结束又弹回来 —— 每次进目录、每次刷新，地址栏都要抖一下。
        const SizedBox(width: 6),
        SizedBox(
          key: const ValueKey('sftp-busy-slot'),
          width: 14,
          height: 14,
          child: busy
              ? CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: theme.colorScheme.primary,
                )
              : null,
        ),
      ],
    );
  }
}

/// 紧凑模式的溢出菜单，把桌面端的按钮收进一层。
final class _CompactMenu extends StatelessWidget {
  const _CompactMenu({
    required this.controller,
    required this.busy,
    required this.filterOpen,
    required this.onToggleFilter,
  });

  final SftpBrowserController controller;
  final bool busy;
  final bool filterOpen;
  final VoidCallback onToggleFilter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      tooltip: l10n.moreActions,
      icon: const Icon(Icons.more_vert_rounded, size: 19),
      onSelected: (value) {
        switch (value) {
          case 'upload':
            _upload(context, controller);
          case 'folder':
            _createFolder(context, controller);
          case 'refresh':
            unawaited(controller.refresh());
          case 'hidden':
            controller.toggleHidden();
          case 'filter':
            onToggleFilter();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'upload',
          height: 38,
          child: Text(l10n.sftpUpload),
        ),
        PopupMenuItem(
          value: 'folder',
          height: 38,
          enabled: !busy,
          child: Text(l10n.sftpNewFolder),
        ),
        PopupMenuItem(
          value: 'refresh',
          height: 38,
          child: Text(l10n.sftpRefresh),
        ),
        PopupMenuItem(
          value: 'hidden',
          height: 38,
          child: Text(
            controller.showHidden ? l10n.sftpHideHidden : l10n.sftpShowHidden,
          ),
        ),
        PopupMenuItem(
          value: 'filter',
          height: 38,
          child: Text(l10n.sftpFilter),
        ),
      ],
    );
  }
}

/// 排序菜单：首项为当前字段，再点一次即反向。
final class _SortButton extends StatelessWidget {
  const _SortButton({required this.controller});

  final SftpBrowserController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<SftpSortField>(
      tooltip: l10n.sftpSortBy,
      icon: Icon(
        Icons.sort_rounded,
        size: 18,
        color: Theme.of(context).secondaryText,
      ),
      onSelected: controller.toggleSort,
      itemBuilder: (context) => [
        for (final field in SftpSortField.values)
          PopupMenuItem(
            value: field,
            height: 38,
            child: Row(
              children: [
                Expanded(child: Text(_sortLabel(l10n, field))),
                if (controller.sortField == field)
                  Icon(
                    controller.sortAscending
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 路径栏：面包屑逐级可点（点哪层去哪层），点路径栏空白处 / 当前层即进入
/// 编辑态，直接敲路径回车前往——与 Windows 资源管理器的地址栏一致，
/// 不再需要先找到一个小按钮才能手输路径。
final class _PathBar extends StatefulWidget {
  const _PathBar({required this.controller});

  final SftpBrowserController controller;

  @override
  State<_PathBar> createState() => _PathBarState();
}

class _PathBarState extends State<_PathBar> {
  final _scroll = ScrollController();
  final _editor = TextEditingController();
  bool _editing = false;
  bool _hovered = false;

  @override
  void didUpdateWidget(_PathBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.path != widget.controller.path &&
        _scroll.hasClients) {
      // 路径变深时把视口推到末尾，始终能看到当前目录。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _editor.dispose();
    super.dispose();
  }

  void _startEdit() {
    final path = widget.controller.path ?? '';
    setState(() {
      _editing = true;
      // 与资源管理器一致：整条路径选中，直接敲就能覆盖。
      _editor.text = path;
      _editor.selection = TextSelection(
        baseOffset: 0,
        extentOffset: path.length,
      );
    });
  }

  void _stopEdit({bool navigate = false}) {
    if (!_editing) return;
    final text = _editor.text.trim();
    setState(() => _editing = false);
    if (navigate && text.isNotEmpty) {
      unawaited(widget.controller.navigate(text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // 浏览态与编辑态共用同一个外框与同一个前置文件夹标记：两种状态只在
    // 「内容」上不同（面包屑 / 输入框），不会一选中就换一副长相。
    final bar = MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        // 空白处（以及当前层那一段）吃掉点击后切到编辑态；
        // 点某一层面包屑时由它自己的手势先胜出，正常跳转。
        behavior: HitTestBehavior.opaque,
        onTap: _editing ? null : _startEdit,
        child: _frame(
          theme,
          highlighted: _editing || _hovered,
          child: _editing
              ? CallbackShortcuts(
                  // Esc 放弃这次输入，回到面包屑；回车 / 失焦按输入内容前往。
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.escape): _stopEdit,
                  },
                  child: TextField(
                    controller: _editor,
                    autofocus: true,
                    style: const TextStyle(fontSize: 12.5),
                    cursorHeight: 15,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: l10n.sftpPathHint,
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: theme.secondaryText,
                      ),
                      // 与面包屑文字左右各 5px 的内边距对齐：点进编辑态时
                      // 路径文字原地不动，不会横向跳一下。
                      contentPadding: const EdgeInsets.symmetric(horizontal: 5),
                    ),
                    onSubmitted: (_) => _stopEdit(navigate: true),
                    onTapOutside: (_) => _stopEdit(),
                  ),
                )
              : SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(children: _crumbs(context)),
                ),
        ),
      ),
    );
    if (_editing) return bar;
    return Tooltip(message: l10n.sftpEditPath, child: bar);
  }

  /// 地址栏外框：浏览态与编辑态尺寸、底色、圆角、边框完全一致，
  /// 只有「选中」（编辑中或鼠标悬停）时边框染成品牌色。
  Widget _frame(
    ThemeData theme, {
    required bool highlighted,
    required Widget child,
  }) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: theme.panelBackground,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: highlighted
              ? theme.colorScheme.primary.withValues(alpha: 0.45)
              : theme.hairline,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 9),
          // 两种状态下都带同一个文件夹标记，读起来始终是「当前路径」。
          Icon(Icons.folder_open_rounded, size: 15, color: theme.secondaryText),
          const SizedBox(width: 7),
          Expanded(child: child),
        ],
      ),
    );
  }

  List<Widget> _crumbs(BuildContext context) {
    final theme = Theme.of(context);
    final crumbs = sftpBreadcrumbs(widget.controller.path ?? '/');
    final widgets = <Widget>[];
    for (var i = 0; i < crumbs.length; i++) {
      final crumb = crumbs[i];
      final isLast = i == crumbs.length - 1;
      if (i > 0) {
        widgets.add(
          Text('/', style: TextStyle(fontSize: 12, color: theme.hairline)),
        );
      }
      widgets.add(
        _Crumb(
          label: crumb.label,
          current: isLast,
          onTap: isLast
              ? null
              : () => unawaited(widget.controller.navigate(crumb.path)),
        ),
      );
    }
    return widgets;
  }
}

final class _Crumb extends StatefulWidget {
  const _Crumb({required this.label, required this.current, this.onTap});

  final String label;
  final bool current;
  final VoidCallback? onTap;

  @override
  State<_Crumb> createState() => _CrumbState();
}

class _CrumbState extends State<_Crumb> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: BoxDecoration(
            color: _hovered && widget.onTap != null ? theme.hoverOverlay : null,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: widget.current ? FontWeight.w600 : FontWeight.w400,
              color: widget.current
                  ? theme.colorScheme.onSurface
                  : theme.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}

/// 当前目录内的即时筛选（纯客户端过滤，不触发重新读目录）。
final class _FilterField extends StatefulWidget {
  const _FilterField({required this.controller, required this.compact});

  final SftpBrowserController controller;
  final bool compact;

  @override
  State<_FilterField> createState() => _FilterFieldState();
}

class _FilterFieldState extends State<_FilterField> {
  late final TextEditingController _editor = TextEditingController(
    text: widget.controller.query,
  );

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 32,
      child: TextField(
        controller: _editor,
        style: const TextStyle(fontSize: 12.5),
        decoration: InputDecoration(
          isDense: true,
          hintText: l10n.sftpFilterHint,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 15),
          suffixIcon: _editor.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 15),
                  tooltip: l10n.cancelSearch,
                  onPressed: () {
                    _editor.clear();
                    widget.controller.setQuery('');
                    setState(() {});
                  },
                ),
        ),
        onChanged: (value) {
          widget.controller.setQuery(value);
          setState(() {});
        },
      ),
    );
  }
}

/// 小尺寸工具按钮：与详情面板头部的图标按钮保持同一节奏。
final class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 17),
      color: active ? theme.colorScheme.primary : theme.secondaryText,
      disabledColor: theme.secondaryText.withValues(alpha: 0.35),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 28),
      onPressed: onPressed,
    );
  }
}
