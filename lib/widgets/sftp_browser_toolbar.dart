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
    required this.pathBarKey,
  });

  final SftpBrowserController controller;
  final bool compact;
  final bool filterOpen;
  final VoidCallback onToggleFilter;
  final ValueChanged<Object> onError;

  /// 面板级的 Ctrl/⌘+L 要落在这条地址栏上（见 [_SftpTabState]）。
  final GlobalKey<_PathBarState> pathBarKey;

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
        Expanded(
          child: _PathBar(key: pathBarKey, controller: controller),
        ),
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
          // 间隔固定、只有内容变，转圈又是不定动画：包一层边界把逐帧重绘
          // 收在这 14px 里，别带着整个工具条一起重画。
          child: busy
              ? RepaintBoundary(
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: theme.colorScheme.primary,
                  ),
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

/// 路径栏：与 GNOME 文件管理器（Nautilus）的位置栏对齐。
///
/// 浏览态是面包屑：段间一个暗色的 `/`，家目录折成一段「主目录」，每一段都是
/// 粗体，非当前段压暗；点哪一段去哪一层，点当前段（或空白处）进编辑态。
/// 路径装不下就横向滚（竖直滚轮也滚它），并自动把当前目录露出来——GNOME
/// 从不把中间几层收起来，滚一下就能看到，收起去反而不知道自己在哪。
///
/// 编辑态是纯文本路径栏：`~` 与相对路径都认，边敲边补（候选下拉 + 行内补全，
/// 补上来的那一截选中，接着敲就顶掉），回车前往、Esc 回面包屑。
final class _PathBar extends StatefulWidget {
  const _PathBar({super.key, required this.controller});

  final SftpBrowserController controller;

  @override
  State<_PathBar> createState() => _PathBarState();
}

class _PathBarState extends State<_PathBar> {
  /// 太长的一层在面包屑里留几个字：GNOME 给普通层 7 个字、给当前层 28 个，
  /// 中间省略（保住开头与结尾，`2026-09-21` 这种尾巴才分得出来）。
  static const int _crumbChars = 7;
  static const int _currentChars = 28;

  /// 下拉每行的高度，两处（下拉本体与滚动定位）共用。
  static const double _suggestionRow = 30;

  final TextEditingController _editor = TextEditingController();
  final FocusNode _node = FocusNode();
  final ScrollController _scroll = ScrollController();
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();

  /// 输入框与补全下拉同属一个点按区域：点候选不算「点到外面」。
  final Object _tapGroup = Object();

  bool _editing = false;
  bool _hovered = false;
  List<String> _suggestions = const [];

  /// 下拉里高亮的那条；-1 表示没选中。GNOME 每次重开下拉都不预选，这样
  /// 「敲完直接回车」是前往，而不是把第一条候选吃进去。
  int _highlight = -1;

  /// 上下键预览候选之前输入框里的内容，Esc 要还回去。
  String? _restore;

  /// 边敲边补的去抖：一次补全可能要问一趟服务端，逐字发请求太糟。
  Timer? _debounce;

  /// 补全请求的序号：晚到的候选不许盖掉用户之后敲进去的内容。
  int _token = 0;

  /// 下拉的宽度（与地址栏对齐），由 build 里的 LayoutBuilder 记下。
  double _width = 320;

  /// 上一次画出来的路径（见 [_crumbs] 的自动滚动）。
  String? _shownPath;

  @override
  void dispose() {
    _debounce?.cancel();
    _editor.dispose();
    _node.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _path => widget.controller.path ?? '/';

  /// 进入编辑态。点路径栏、点当前段，以及面板里的 Ctrl/⌘+L 都走这里。
  ///
  /// 整条路径**全选**：远端路径动辄一长串，全选后直接敲就是要换一条路，
  /// 比让用户先 Ctrl+A 再敲省一步（GNOME 是把光标放到末尾，那是本地路径的
  /// 习惯，搬到这儿只会让人敲出 `/home/deploy/logs/etc`）。
  void startEdit() {
    final path = _path;
    _debounce?.cancel();
    _token++;
    _editor.value = TextEditingValue(
      text: path,
      selection: TextSelection(baseOffset: 0, extentOffset: path.length),
    );
    setState(() {
      _editing = true;
      _suggestions = const [];
      _highlight = -1;
      _restore = null;
    });
    _portal.hide();
  }

  void _stopEdit() {
    _debounce?.cancel();
    _token++;
    if (!_editing) return;
    setState(() {
      _editing = false;
      _suggestions = const [];
      _highlight = -1;
      _restore = null;
    });
    _portal.hide();
  }

  /// 敲字就补。GNOME 的位置栏不用按 Tab：候选与行内补全自己跟上来。
  void _onChanged(String _) {
    _restore = null;
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 120),
      () => unawaited(_complete()),
    );
  }

  /// 按当前输入重算候选并把能确定的那截补进输入框（补上来的部分选中，
  /// 接着敲就顶掉它——GTK 的行内补全就是这个手感）。
  Future<void> _complete() async {
    final token = ++_token;
    final text = _editor.text;
    final candidates = await widget.controller.completePath(text);
    if (!mounted || !_editing || token != _token || text != _editor.text) {
      return;
    }
    if (candidates.isEmpty) {
      _setSuggestions(const []);
      return;
    }
    final prefix = _commonPrefix(candidates);
    if (prefix.length > text.length) {
      // 只选中补上来的那一截：接着敲就把它顶掉，与 GTK 的行内补全一致。
      _editor.value = TextEditingValue(
        text: prefix,
        selection: TextSelection(
          baseOffset: text.length,
          extentOffset: prefix.length,
        ),
      );
    }
    _setSuggestions(candidates);
  }

  void _setSuggestions(List<String> suggestions) {
    setState(() {
      _suggestions = suggestions;
      _highlight = -1;
    });
    if (suggestions.isEmpty) {
      _portal.hide();
    } else {
      _portal.show();
    }
  }

  /// 上下键：候选写进输入框当作预览（GTK 的 inline-selection 就是这个）；
  /// 回到 -1 时把用户原本敲的内容还回去。
  void _moveHighlight(int delta) {
    if (_suggestions.isEmpty) return;
    final base = _highlight < 0 ? _editor.text : _restore ?? _editor.text;
    final next = _highlight + delta;
    if (next < 0) {
      setState(() => _highlight = -1);
      _setText(base);
      _restore = null;
      return;
    }
    final index = next % _suggestions.length;
    setState(() {
      _highlight = index;
      _restore = base;
    });
    _setText(_suggestions[index]);
  }

  void _setText(String value) {
    _editor.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  /// 回车：有高亮就收下它（第二次回车才前往），否则直接按输入前往。
  void _submit() {
    if (_highlight >= 0 && _highlight < _suggestions.length) {
      _accept(_suggestions[_highlight]);
      return;
    }
    unawaited(_go());
  }

  /// Tab：收下行内补全（把选区收到末尾）并关掉下拉，光标留在原地——
  /// GNOME 的位置栏里 Tab 也不触发补全，补全是敲字时自己来的。
  void _acceptInline() {
    if (_suggestions.isNotEmpty) _setSuggestions(const []);
    final selection = _editor.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    _editor.value = TextEditingValue(
      text: _editor.text,
      selection: TextSelection.collapsed(offset: selection.end),
    );
  }

  void _accept(String value) {
    _setText(value);
    _setSuggestions(const []);
    _restore = null;
    _node.requestFocus();
  }

  /// Esc：先收下拉（有预览就把输入还回去），没有下拉才退出编辑态。
  void _escape() {
    if (_suggestions.isEmpty) {
      _stopEdit();
      return;
    }
    final restore = _restore;
    _setSuggestions(const []);
    if (restore != null) _setText(restore);
    _restore = null;
  }

  Future<void> _go() async {
    final target = resolveSftpPath(
      _editor.text,
      home: widget.controller.home,
      base: widget.controller.path,
    );
    if (target == null || target == widget.controller.path) {
      _stopEdit();
      return;
    }
    _setSuggestions(const []);
    await widget.controller.navigate(target);
    if (!mounted || !_editing) return;
    // 到了就回面包屑；没到就把输入留着——用户改一个字就能重来，
    // 列表那边已经在展示失败原因。
    if (widget.controller.error == null) _stopEdit();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final editing = _editing;
    final bar = TapRegion(
      groupId: _tapGroup,
      onTapOutside: (_) => _stopEdit(),
      child: MouseRegion(
        // 空白处是「可以在这里打字」，所以整条给的是文本光标（细线段）；
        // 面包屑自己那层会把它改成手型。
        cursor: SystemMouseCursors.text,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: editing ? null : startEdit,
          child: _frame(
            theme,
            highlighted: editing || _hovered,
            // 提示挂在面包屑上、不裹在 OverlayPortal 外面：两种状态换的是
            // 外框**里面**的内容，裹到外面去就会把 OverlayPortal 连同补全
            // 下拉的控制器一起重建——而切状态正是它要 show/hide 的时候。
            child: editing
                ? _field(context, theme, l10n)
                : Tooltip(
                    message: l10n.sftpEditPath,
                    child: _crumbs(context, l10n),
                  ),
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        return CompositedTransformTarget(
          link: _link,
          child: OverlayPortal(
            controller: _portal,
            overlayChildBuilder: _suggestionOverlay,
            child: bar,
          ),
        );
      },
    );
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

  Widget _field(BuildContext context, ThemeData theme, AppLocalizations l10n) {
    return CallbackShortcuts(
      bindings: {
        // Esc 收下拉 / 退出，Tab 收下行内补全，上下键在候选里走。
        // 回车不走这里：桌面端引擎把回车翻成 done 动作，只能从 onSubmitted 收。
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
        const SingleActivator(LogicalKeyboardKey.tab): _acceptInline,
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _moveHighlight(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _moveHighlight(-1),
      },
      child: TextField(
        controller: _editor,
        focusNode: _node,
        autofocus: true,
        style: const TextStyle(fontSize: 12.5),
        cursorHeight: 15,
        decoration: InputDecoration(
          isDense: true,
          // 外框已经由 [_frame] 画好了，输入框自己不许再画一层：主题里的
          // `filled: true` 会铺一块灰底，而 `enabledBorder` / `focusedBorder`
          // 会**压过** `border: none`（那两项在 decoration 里没写就取主题值），
          // 于是框里套框——每个状态都得显式按掉，光写 border 不够。
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          hintText: l10n.sftpPathHint,
          hintStyle: TextStyle(fontSize: 12.5, color: theme.secondaryText),
          // 与面包屑文字左右各 5px 的内边距对齐：点进编辑态时
          // 路径文字原地不动，不会横向跳一下。
          contentPadding: const EdgeInsets.symmetric(horizontal: 5),
        ),
        onSubmitted: (_) => _submit(),
        onChanged: _onChanged,
      ),
    );
  }

  Widget _crumbs(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final path = widget.controller.path ?? '/';
    // 路径变了就把当前目录滚进视野（新路径更深时尤其要紧）。判据得自己记：
    // 控制器是同一个对象，`oldWidget.controller.path` 永远等于新值。
    if (path != _shownPath) {
      _shownPath = path;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
    final crumbs = sftpBreadcrumbs(path, home: widget.controller.home);
    final children = <Widget>[];
    for (var i = 0; i < crumbs.length; i++) {
      final crumb = crumbs[i];
      final current = i == crumbs.length - 1;
      final label = crumb.isHome ? l10n.sftpHome : crumb.label;
      if (i > 0) children.add(_separator(theme));
      children.add(
        _Crumb(
          label: elideSftpName(label, current ? _currentChars : _crumbChars),
          tooltip: label,
          icon: crumb.isHome ? Icons.home_rounded : null,
          current: current,
          onTap: current
              ? startEdit
              : () => unawaited(widget.controller.navigate(crumb.path)),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        // 滚轮监听必须挂在滚动视图**里面**：指针信号由 PointerSignalResolver
        // 派发，只有最先登记的那一个收到，而命中测试是里层先跑——挂在外层就
        // 永远轮不到。铺满整条宽度，空白处的滚轮也算数；右侧那点留白要算在
        // 最小宽度里，否则内容天然比视口宽 8px，一进来就先滚掉 8px。
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: _scrollWithWheel,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(children: children),
            ),
          ),
        ),
      ),
    );
  }

  void _scrollWithWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (delta == 0) return;
    _scroll.jumpTo(
      (_scroll.offset + delta).clamp(0.0, _scroll.position.maxScrollExtent),
    );
  }

  Widget _separator(ThemeData theme) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 1),
    child: Text(
      '/',
      style: TextStyle(fontSize: 12.5, color: theme.secondaryText),
    ),
  );

  /// 补全下拉：浮在地址栏下面，和 GNOME 的位置栏补全一个意思。
  Widget _suggestionOverlay(BuildContext context) {
    final theme = Theme.of(context);
    return CompositedTransformFollower(
      link: _link,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      offset: const Offset(0, 4),
      // Overlay 给的是整屏紧约束，先摊平再让 Material 自己收成列表大小。
      child: Align(
        alignment: Alignment.topLeft,
        child: TapRegion(
          groupId: _tapGroup,
          child: Material(
            elevation: 8,
            color: theme.panelBackground,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                // 地址栏比 180 还窄时别把上下限写反（窄面板里真的会遇到）。
                minWidth: _width < 180 ? _width : 180,
                maxWidth: _width,
                maxHeight: _suggestionRow * 6 + 8,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemExtent: _suggestionRow,
                itemCount: _suggestions.length,
                itemBuilder: (context, index) => _suggestion(theme, index),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _suggestion(ThemeData theme, int index) {
    final value = _suggestions[index];
    final directory = value.endsWith('/');
    final name = value.split('/').where((segment) => segment.isNotEmpty).last;
    final highlighted = index == _highlight;
    return MouseRegion(
      onEnter: (_) => setState(() => _highlight = index),
      child: GestureDetector(
        onTap: () => _accept(value),
        child: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: highlighted ? theme.hoverOverlay : null,
          child: Text(
            directory ? '$name/' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              color: highlighted
                  ? theme.colorScheme.onSurface
                  : theme.secondaryText,
            ),
          ),
        ),
      ),
    );
  }

  static String _commonPrefix(List<String> values) {
    var prefix = values.first;
    for (final value in values.skip(1)) {
      var index = 0;
      while (index < prefix.length &&
          index < value.length &&
          prefix[index] == value[index]) {
        index++;
      }
      prefix = prefix.substring(0, index);
    }
    return prefix;
  }
}

final class _Crumb extends StatefulWidget {
  const _Crumb({
    required this.label,
    required this.tooltip,
    required this.current,
    this.icon,
    this.onTap,
  });

  final String label;

  /// 完整名字：太长时 [label] 是省略过的，悬停仍然要能看全。
  final String tooltip;
  final bool current;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  State<_Crumb> createState() => _CrumbState();
}

class _CrumbState extends State<_Crumb> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clickable = widget.onTap != null;
    // 当前那一段与其余各段一样是粗体，只有明暗不同；当前段是「点开输入框」
    // 而不是跳转，按 GNOME 的样式不给悬停底色。
    final color = widget.current
        ? theme.colorScheme.onSurface
        : theme.secondaryText;
    final box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: _hovered && clickable && !widget.current
            ? theme.hoverOverlay
            : null,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            widget.label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
    return MouseRegion(
      cursor: widget.current
          ? SystemMouseCursors.text
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: widget.label == widget.tooltip
            ? box
            : Tooltip(message: widget.tooltip, child: box),
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
