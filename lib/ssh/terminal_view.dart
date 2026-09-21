import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/core.dart';
import 'package:xterm/ui.dart';

import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../settings.dart';
import '../snippets.dart';
import '../theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/snippet_dialog.dart';
import 'auto_reconnect.dart';
import 'terminal_interactions.dart';
import 'terminal_key_bar.dart';
import 'terminal_session.dart';

/// 链接点击的容差：按下与抬起之间超过这么多像素就算拖选，不算点击。
/// 鼠标会抖，但不能大到把「选一小段字」也算成点击。
const double _linkTapSlop = 6;

/// 触屏长按多久算「叫我菜单」。xterm 自己的长按选词在 500ms 触发，
/// 这里压后一点：菜单弹出时选区已经落定，「复制」才是可用的。
const Duration _longPressDelay = Duration(milliseconds: 550);

/// 触屏单击链接的延迟：等过双击窗口再打开。xterm 用双击选词，若第一下
/// 就跳浏览器，链接上永远选不中一个词（与侧边栏「双击直连」同一取舍）。
const Duration _doubleTapWindow = Duration(milliseconds: 260);

/// 触屏平台（Android / iOS）：快捷键条与放宽的触控目标只在这里生效。
///
/// 判平台而不是判窗口宽度：窄窗口的桌面用户有物理键盘，给他塞一条软键盘
/// 键条只是噪声（与凭据弹窗判平台、判 web 同一取向）。
bool get _isTouchPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// 会话阶段映射为主机展示状态，复用现有的状态圆点 / 徽章。
ServerStatus serverStatusOf(TerminalPhase phase) => switch (phase) {
  TerminalPhase.connecting => ServerStatus.connecting,
  TerminalPhase.connected => ServerStatus.connected,
  TerminalPhase.failed => ServerStatus.error,
  TerminalPhase.closed => ServerStatus.idle,
};

/// 真实 SSH 终端视图：按全局偏好渲染会话缓冲区，非连接态时叠加状态浮层。
/// 右上角常驻会话工具条（复制 / 粘贴 / 命令片段；会话日志的入口在详情头部
/// 与全屏终端页的状态胶囊上），挂了重连计划时浮层里会多出倒计时与
/// 「停止自动重连」。
///
/// 便捷交互：右键菜单（复制 / 粘贴 / 全选）、Cmd/Ctrl +/- 字号缩放、
/// Cmd/Ctrl+点击打开链接（按住修饰键悬停到链接上会加下划线并换成手型光标），
/// 以及可选的「选中即复制」。
final class SshTerminalView extends StatefulWidget {
  const SshTerminalView({
    super.key,
    required this.session,
    this.onRetry,
    this.reconnectPlan,
    this.onStopAutoReconnect,
    this.openLink = openTerminalLink,
  });

  final TerminalSession session;

  /// Cmd/Ctrl+点击命中链接时的打开动作，返回是否真的打开了。
  /// 默认交给系统浏览器；widget 测试注入假实现——真实现会去碰测试机上
  /// 真实的默认浏览器。
  final Future<bool> Function(Uri uri) openLink;

  /// 失败 / 已结束时的重连动作；为空时不展示重连按钮。
  final VoidCallback? onRetry;

  /// 该会话挂着的自动重连计划；为空表示没有排队中的重连。
  final ReconnectPlan? reconnectPlan;

  /// 停止自动重连；为空时不展示停止按钮。
  final VoidCallback? onStopAutoReconnect;

  @override
  State<SshTerminalView> createState() => _SshTerminalViewState();
}

final class _SshTerminalViewState extends State<SshTerminalView> {
  /// 选区状态归本视图持有：复制按钮、右键菜单与选中即复制都要读写它。
  /// 传给 TerminalView 后手势归包管，这里只订阅变化。
  final TerminalController _controller = TerminalController();

  /// 点击位置换算单元格要用 TerminalView 的 render object：
  /// padding 与滚动偏移都在它手里，自己按格宽算迟早会和包对不上。
  final GlobalKey<TerminalViewState> _terminalKey =
      GlobalKey<TerminalViewState>();

  /// 终端自己的焦点节点：键条按键后要把焦点补回来（丢了焦点软键盘就收起）。
  /// 由本视图持有并 dispose——给了 TerminalView 就不再归它管。
  final FocusNode _focusNode = FocusNode();

  /// 下划线浮层的 render object：它的坐标系就是画布坐标系。
  final GlobalKey _underlineKey = GlobalKey();

  /// 指针当前位置（全局坐标）；不在终端上、或正在拖动选字时为 null。
  Offset? _pointer;

  /// 下划线的判定结果：按住 Cmd/Ctrl 且指针停在链接上时非空，否则为 null。
  /// 光标形状与下划线共用这一份判定。鼠标在同一行的链接上滑动时值不变，
  /// 靠 [TerminalLink] 的 `==` 让 ValueNotifier 不发多余通知。
  final ValueNotifier<TerminalLink?> _hoveredLink =
      ValueNotifier<TerminalLink?>(null);

  /// 链接没变、但画面滚了或刷新了时，让下划线重画一次。
  final _LinkRepaint _linkRepaint = _LinkRepaint();

  /// 上一次看到的修饰键状态。按键时指针不会动，靠它决定要不要重算。
  bool _modifierDown = false;

  /// 最近一次「鼠标左键按下」的全局位置；不是左键时为 null。
  Offset? _linkTapOrigin;

  /// 触屏按下的起点；只用于触屏的长按 / 单击判定。
  Offset? _touchOrigin;

  /// 长按已弹出菜单：这一串指针事件不再当单击处理。
  bool _longPressFired = false;

  /// 长按判定计时器；抬起、拖动、取消都要收掉，否则测试结束会留下悬挂 timer。
  Timer? _longPressTimer;

  /// 待打开的链接（触屏单击）：等过双击窗口，第二次按下即取消。
  Timer? _linkTapTimer;

  /// 这一串指针事件是双击的第二下：它的抬手同样不算「点链接」。
  bool _touchDoubleTap = false;

  /// 键位表只在 init 时算一次：平台运行中不会变，每次 build 新建只会
  /// 让包的 ShortcutManager 白白换表。
  late final Map<ShortcutActivator, Intent> _shortcuts = terminalShortcuts();

  /// 终端自己的滚动控制器：交给 TerminalView 用，同时喂滚动条与「回到最新」。
  /// 由本视图创建并 dispose——给了 TerminalView 就不再归它管（与 focusNode 同理）。
  final ScrollController _scrollController = ScrollController();

  /// 画面是否停在最新输出处。滚动每帧都在变，只有跨过这条边界才通知下游：
  /// 值变化时重画的只是那一颗浮动按钮。
  final ValueNotifier<bool> _atBottom = ValueNotifier<bool>(true);

  /// 选中即复制的去抖：拖选过程中选区连续变化（每次都通知），等最后一次
  /// 变化后静默一小段时间再复制，落进剪贴板的才是完整选区；双击选词、
  /// 长按选词也走同一条路。
  Timer? _copyOnSelectTimer;

  /// 当前是否开启选中即复制；每次偏好重建时刷新，供控制器回调读取。
  bool _copyOnSelect = false;

  /// 查找栏是否展开。
  bool _searching = false;
  String _query = '';

  /// 命中位置（绝对行号，随输出滚动会过期；高亮用的是锚点，不受影响）。
  List<TerminalMatch> _matches = const [];
  int _matchIndex = 0;

  /// 挂在控制器上的高亮对象：重新查找或收起查找栏时必须逐个 dispose，
  /// 否则旧底色会一直留在缓冲区的那些格子上。
  final List<TerminalHighlight> _highlights = [];

  final TextEditingController _searchField = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSelectionChanged);
    _scrollController.addListener(_onScroll);
    // 修饰键按下 / 抬起时指针不会动，但下划线该跟着出现或消失。
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    // 远端输出会顶动画面：指针底下的链接可能已经换了一条。
    widget.session.terminal.addListener(_refreshLinkHover);
  }

  @override
  void didUpdateWidget(SshTerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session == widget.session) return;
    // 视图被复用到另一条会话上：监听要跟着搬，否则下划线盯着旧终端算。
    oldWidget.session.terminal.removeListener(_refreshLinkHover);
    widget.session.terminal.addListener(_refreshLinkHover);
    _pointer = null;
    _refreshLinkHover();
  }

  @override
  void dispose() {
    _copyOnSelectTimer?.cancel();
    _longPressTimer?.cancel();
    _linkTapTimer?.cancel();
    _focusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _atBottom.dispose();
    _clearHighlights();
    _searchField.dispose();
    _searchFocus.dispose();
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    widget.session.terminal.removeListener(_refreshLinkHover);
    _hoveredLink.dispose();
    _linkRepaint.dispose();
    _controller
      ..removeListener(_onSelectionChanged)
      ..dispose();
    super.dispose();
  }

  /// 修饰键起落：只在状态真的变了时重算，键盘每敲一下都过这里。
  bool _onKeyEvent(KeyEvent event) {
    final down = isLinkModifierPressed();
    if (down != _modifierDown) {
      _modifierDown = down;
      _refreshLinkHover();
    }
    return false;
  }

  void _onSelectionChanged() {
    _copyOnSelectTimer?.cancel();
    if (!_copyOnSelect) return;
    // 选区被点掉（selection 变 null）不算「选完」：没有要复制的东西。
    if (_controller.selection == null) return;
    _copyOnSelectTimer = Timer(const Duration(milliseconds: 160), () {
      copyTerminalSelection(widget.session.terminal, _controller);
    });
  }

  void _adjustFontSize(int delta) {
    final notifier = TerminalStyleScope.of(context).notifier;
    notifier.value = notifier.value.withFontSize(
      notifier.value.fontSize + delta,
    );
  }

  void _resetFontSize() {
    final notifier = TerminalStyleScope.of(context).notifier;
    notifier.value = notifier.value.copyWith(
      fontSize: TerminalStylePrefs.defaultFontSize,
    );
  }

  /// 指针按下：鼠标左键是链接点击的候选；触屏则起一次长按判定。
  void _onPointerDown(PointerDownEvent event) {
    _linkTapOrigin =
        event.kind == PointerDeviceKind.mouse && event.buttons == kPrimaryButton
        ? event.position
        : null;
    if (event.kind != PointerDeviceKind.touch) return;
    // 触屏：单击是「点链接」、长按是「叫我菜单」，两者都在这一串指针事件里判。
    // 用 Listener 而不是 GestureDetector，是为了不参与手势竞技场——xterm
    // 内部已经拿着长按 / 拖动识别器做选词，再去竞技场里抢只会两败俱伤。
    _longPressTimer?.cancel();
    // 上一次单击还在双击窗口里：两下都不算「点链接」——双击是选词。
    if (_linkTapTimer?.isActive ?? false) {
      _linkTapTimer!.cancel();
      _touchDoubleTap = true;
    }
    _touchOrigin = event.position;
    _longPressFired = false;
    _longPressTimer = Timer(_longPressDelay, () {
      if (!mounted) return;
      _longPressFired = true;
      _showContextMenuAt(event.position);
    });
  }

  /// 指针在终端上移动（没按任何键）：重新判定下划线。
  void _onPointerHover(PointerHoverEvent event) {
    _pointer = event.position;
    _refreshLinkHover();
  }

  /// 按住键拖动（拖选文字）期间不画下划线：指针位置作废，松手时再恢复。
  /// 拖动同时作废长按判定——手指挪了就不是「长按」。
  void _onPointerMove(PointerMoveEvent event) {
    final origin = _touchOrigin;
    if (origin != null && (event.position - origin).distance > _linkTapSlop) {
      _longPressTimer?.cancel();
      _touchOrigin = null;
    }
    _pointer = null;
    _refreshLinkHover();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _longPressTimer?.cancel();
    _touchOrigin = null;
    _longPressFired = false;
    _touchDoubleTap = false;
    _pointer = null;
    _refreshLinkHover();
  }

  void _onPointerExit(PointerExitEvent event) {
    _pointer = null;
    _refreshLinkHover();
  }

  /// Cmd/Ctrl+单击（鼠标）或直接单击（触屏）：命中链接就交给系统打开；
  /// 普通点击原样还给终端。
  ///
  /// 这里收的是原始指针事件，没用 `TerminalView.onTapUp`：xterm 4.0.0 里那条
  /// 回调是断的——手势层的 `_handleTapUp` 调的是 `onSingleTapUp`，而
  /// `TerminalView` 把处理器传在 `onTapUp` 上，该字段在包内没有任何读取点，
  /// 回调一次都不会触发（上游 master 同样如此，pub 上也没有更新的版本）。
  /// `Listener` 不参与手势竞技场，因此不会被包内层的 TapGestureRecognizer
  /// 挤掉。等上游修好也**不要**把 onTapUp 一并接上：一次点击会开两个标签页。
  Future<void> _onPointerUp(PointerUpEvent event) async {
    // 松手后指针还在原处：把拖动期间作废的悬停判定恢复回来。
    _pointer = event.position;
    _refreshLinkHover();

    if (event.kind == PointerDeviceKind.touch) {
      _longPressTimer?.cancel();
      final origin = _touchOrigin;
      _touchOrigin = null;
      final longPressed = _longPressFired;
      final doubleTap = _touchDoubleTap;
      _longPressFired = false;
      _touchDoubleTap = false;
      // 长按已经弹过菜单、或这是双击的第二下：都不再当单击
      //（否则菜单刚出来就会去开链接，双击选词也会顺手跳浏览器）。
      if (longPressed || doubleTap || origin == null) return;
      if ((event.position - origin).distance > _linkTapSlop) return;
      _scheduleTouchLinkOpen(event.position);
      return;
    }

    final origin = _linkTapOrigin;
    _linkTapOrigin = null;
    if (origin == null) return;
    // 拖着选字松手不算点击。
    if ((event.position - origin).distance > _linkTapSlop) return;
    if (!isLinkModifierPressed()) return;
    await _openLinkAt(event.position);
  }

  /// 触屏单击落点上的链接：压一个双击窗口再打开。
  void _scheduleTouchLinkOpen(Offset globalPosition) {
    if (!_touchTapOpensLinks) return;
    _linkTapTimer?.cancel();
    _linkTapTimer = Timer(_doubleTapWindow, () {
      unawaited(_openLinkAt(globalPosition));
    });
  }

  /// 触屏上单击就打开链接：手机上按不出 Cmd/Ctrl，否则链接永远点不动。
  ///
  /// 全屏程序（vim / less / tmux 走备用缓冲区）里例外——那里的点按属于
  /// 远端应用（鼠标上报），抢来开浏览器会让「点一下定位光标」失灵。
  bool get _touchTapOpensLinks => !widget.session.terminal.isUsingAltBuffer;

  /// 打开坐标底下的链接；没命中就什么都不做。返回是否真的打开过。
  Future<void> _openLinkAt(Offset globalPosition) async {
    if (!mounted) return;
    final cell = _cellAt(globalPosition);
    if (cell == null) return;
    final link = findLinkAtCell(widget.session.terminal, cell);
    if (link == null) return;
    final uri = Uri.tryParse(link.url);
    if (uri == null) return;
    final opened = await widget.openLink(uri);
    if (!opened && mounted) {
      showToast(context, AppLocalizations.of(context).linkOpenFailed);
    }
  }

  /// 重算「指针此刻是否停在链接上」，并让下划线跟上。
  ///
  /// 调用点很多（鼠标移动、修饰键起落、滚动、每一笔远端输出），所以第一件
  /// 事是尽快退出：没按修饰键、本来也没显示下划线时什么都不用做。
  void _refreshLinkHover() {
    final current = _hoveredLink.value;
    if (!isLinkModifierPressed() && current == null) return;

    final link = _linkUnderPointer();
    if (link != current) {
      _hoveredLink.value = link;
    } else if (link != null) {
      // 还是同一条链接，但画面可能滚了或重排了：几何要重算一次。
      _linkRepaint.ping();
    }
  }

  /// 指针底下的链接。没按修饰键、指针不在终端上、或没命中，都是 null
  /// ——修饰键状态属于判定结果的一部分，松手就该判定成「没有链接」。
  TerminalLink? _linkUnderPointer() {
    if (!isLinkModifierPressed()) return null;
    final position = _pointer;
    if (position == null) return null;
    final cell = _cellAt(position);
    return cell == null ? null : findLinkAtCell(widget.session.terminal, cell);
  }

  /// 全局坐标 → 缓冲区单元格；视图还没挂上时返回 null。
  CellOffset? _cellAt(Offset globalPosition) {
    final render = _terminalKey.currentState?.renderTerminal;
    if (render == null) return null;
    return render.getCellOffset(render.globalToLocal(globalPosition));
  }

  /// 快捷键条只在触屏平台挂载（见 [_isTouchPlatform]）。
  bool get _showKeyBar => _isTouchPlatform;

  /// 键条上的键不该把焦点带走：焦点一丢软键盘就收起，连按几下 Esc 会变成
  /// 「收起键盘」。只在真的丢了焦点时补回来——用户自己按返回键收键盘时焦点
  /// 还在终端上，那时补焦点等于把键盘又弹回来。
  void _restoreTerminalFocus() {
    if (!_focusNode.hasFocus) _focusNode.requestFocus();
  }

  /// 滚到最新输出。用 jumpTo 而不是 animateTo：远端还在输出时
  /// `maxScrollExtent` 每帧都在长，动画的目标值一出门就过期；xterm 自己在
  /// 用户输入时也是直接 jumpTo。
  void _scrollToLatest() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // 阈值 1px：滚到底时 pixels 与 maxScrollExtent 可能差一个浮点尾巴。
    final atBottom = position.maxScrollExtent - position.pixels <= 1;
    if (_atBottom.value == atBottom) return;
    _atBottom.value = atBottom;
  }

  /// 滚动条只挂在触屏平台：桌面端框架自己会按平台加一条
  /// （`MaterialScrollBehavior`），这里再加就是两条；移动端框架不加，
  /// 而手机上没有任何滚动位置反馈，一屏刷过去的日志会让人不知道身在何处。
  ///
  /// `interactive` 保持 false：拖动拇指要跟包内层的选字识别器抢手势，
  /// 而竞技场里更深的那一个（xterm 的）会赢——给了拖动也是白给。
  Widget _withScrollbar(TerminalStylePrefs prefs, Widget child) {
    if (!_isTouchPlatform) return child;
    return Scrollbar(
      controller: _scrollController,
      thickness: 3,
      radius: const Radius.circular(2),
      child: child,
    );
  }

  void _openSearch() {
    if (_searching) {
      _searchFocus.requestFocus();
      return;
    }
    setState(() => _searching = true);
    // 展开之后再申请焦点：焦点一挪走软键盘就会跳出来，而这是用户主动点
    // 「查找」的预期结果；收起时再还给终端（见 _closeSearch）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _clearHighlights();
    _searchField.clear();
    setState(() {
      _searching = false;
      _query = '';
      _matches = const [];
      _matchIndex = 0;
    });
    _restoreTerminalFocus();
  }

  void _runSearch(String query) {
    final matches = findTerminalMatches(widget.session.terminal.buffer, query);
    _query = query;
    _matches = matches;
    _matchIndex = 0;
    _paintHighlights();
    setState(() {});
    if (matches.isNotEmpty) _scrollToMatch(0);
  }

  /// 上一条 / 下一条，首尾相接。
  void _stepMatch(int delta) {
    if (_matches.isEmpty) return;
    final next = (_matchIndex + delta) % _matches.length;
    _matchIndex = next < 0 ? next + _matches.length : next;
    _paintHighlights();
    setState(() {});
    _scrollToMatch(_matchIndex);
  }

  /// 命中全部上底色，当前那一处换更实的颜色。
  ///
  /// 颜色必须**半透明**：xterm 画高亮就是在字上面盖一个实心矩形
  /// （`paintHighlight` 只有 drawRect，主题里的 `searchHitForeground`
  /// 在包里根本没人读），不透明就把命中的字整片盖掉了。
  void _paintHighlights() {
    final theme = TerminalStyleScope.of(context).notifier.value.theme;
    _clearHighlights();
    for (var i = 0; i < _matches.length; i++) {
      final match = _matches[i];
      final current = i == _matchIndex;
      final color = current
          ? theme.searchHitBackgroundCurrent
          : theme.searchHitBackground;
      _highlights.add(
        _controller.highlight(
          p1: widget.session.terminal.buffer.createAnchor(
            match.startCell,
            match.row,
          ),
          // 区间是「含首含尾」的，所以末格要减一。
          p2: widget.session.terminal.buffer.createAnchor(
            match.endCell - 1,
            match.row,
          ),
          color: color.withValues(alpha: current ? 0.55 : 0.26),
        ),
      );
    }
  }

  void _clearHighlights() {
    for (final highlight in _highlights) {
      highlight.dispose();
    }
    _highlights.clear();
  }

  /// 把命中行滚进视野。已经在视野里（留一行余量）就不动，免得每敲一个字
  /// 画面都跳一下。
  void _scrollToMatch(int index) {
    final render = _terminalKey.currentState?.renderTerminal;
    if (render == null || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final lineHeight = render.lineHeight;
    if (lineHeight <= 0) return;
    final row = _matches[index].row;
    final first = position.pixels / lineHeight;
    final last = (position.pixels + position.viewportDimension) / lineHeight;
    if (row >= first + 1 && row <= last - 1) return;
    final target = (row * lineHeight - lineHeight * 3).clamp(
      0.0,
      position.maxScrollExtent,
    );
    _scrollController.jumpTo(target);
  }

  Widget _searchBar(TerminalStylePrefs prefs) {
    final l10n = AppLocalizations.of(context);
    final theme = prefs.theme;
    final foreground = theme.foreground;
    final counter = _query.isEmpty
        ? ''
        : (_matches.isEmpty
              ? l10n.searchNoResults
              : '${_matchIndex + 1}/${_matches.length}');
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: theme.background,
        border: Border(
          top: BorderSide(color: foreground.withValues(alpha: 0.14)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 17,
            color: foreground.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchField,
              focusNode: _searchFocus,
              onChanged: _runSearch,
              onSubmitted: (_) => _stepMatch(1),
              textInputAction: TextInputAction.search,
              style: TextStyle(fontSize: 13, color: foreground),
              cursorColor: theme.cursor,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: l10n.searchHint,
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: foreground.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
          if (counter.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              counter,
              style: TextStyle(
                fontSize: 12,
                color: _matches.isEmpty
                    ? AppPalette.warning
                    : foreground.withValues(alpha: 0.75),
              ),
            ),
          ],
          _searchButton(
            Icons.keyboard_arrow_up_rounded,
            l10n.searchPrevious,
            _matches.isEmpty ? null : () => _stepMatch(-1),
            foreground,
          ),
          _searchButton(
            Icons.keyboard_arrow_down_rounded,
            l10n.searchNext,
            _matches.isEmpty ? null : () => _stepMatch(1),
            foreground,
          ),
          _searchButton(
            Icons.close_rounded,
            MaterialLocalizations.of(context).closeButtonTooltip,
            _closeSearch,
            foreground,
          ),
        ],
      ),
    );
  }

  /// 查找栏上的按钮：与键条同理，走 GestureDetector 不碰焦点体系，
  /// 否则点一下「下一个」软键盘就收起来了。
  Widget _searchButton(
    IconData icon,
    String tooltip,
    VoidCallback? onTap,
    Color color,
  ) {
    final size = _isTouchPlatform ? 44.0 : 32.0;
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(
                icon,
                size: 19,
                color: color.withValues(alpha: onTap == null ? 0.3 : 1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _scrollToLatestButton(TerminalStylePrefs prefs) {
    final foreground = prefs.theme.foreground;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _scrollToLatest,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: prefs.theme.background.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: foreground.withValues(alpha: 0.24)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_downward_rounded, size: 16, color: foreground),
            const SizedBox(width: 6),
            Text(
              AppLocalizations.of(context).scrollToBottom,
              style: TextStyle(fontSize: 12, color: foreground),
            ),
          ],
        ),
      ),
    );
  }

  /// 在 [globalPosition] 处弹出会话菜单：桌面右键与触屏长按都走这里。
  Future<void> _showContextMenuAt(Offset globalPosition) =>
      _showContextMenu(globalPosition, _cellAt(globalPosition));

  Future<void> _showContextMenu(Offset position, CellOffset? cell) async {
    final l10n = AppLocalizations.of(context);
    // 按到的格子上正好是链接时多给一项「打开链接」：触屏上长按是选词，
    // 想开链接要么点它、要么走这里，后者不受备用缓冲区那条限制。
    final link = cell == null
        ? null
        : findLinkAtCell(widget.session.terminal, cell);
    final action = await showMenu<String>(
      context: context,
      // 四边都收敛到指针处，菜单从点击位置弹出。
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'copy',
          enabled: _controller.selection != null,
          child: Text(l10n.copy),
        ),
        PopupMenuItem(value: 'paste', child: Text(l10n.paste)),
        PopupMenuItem(value: 'selectAll', child: Text(l10n.selectAll)),
        if (link != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(value: 'openLink', child: Text(l10n.openLink)),
        ],
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'copy':
        await copyTerminalSelection(widget.session.terminal, _controller);
      case 'paste':
        await pasteIntoTerminal(widget.session.terminal);
      case 'selectAll':
        selectAllInTerminal(widget.session.terminal, _controller);
      case 'openLink':
        final uri = Uri.tryParse(link!.url);
        if (uri == null) return;
        final opened = await widget.openLink(uri);
        if (!opened && mounted) {
          showToast(context, AppLocalizations.of(context).linkOpenFailed);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = widget.session.phase;
    // 只监听终端样式偏好：切换预设 / 字体时仅终端区域重建。
    return ValueListenableBuilder<TerminalStylePrefs>(
      valueListenable: TerminalStyleScope.of(context).notifier,
      builder: (context, prefs, _) {
        _copyOnSelect = prefs.copyOnSelect;
        // 缩放意图的键位挂在包内部的 Shortcuts 上，Actions 解析沿树向上
        // 走，所以动作方必须是 TerminalView 的祖先——包住整个 Stack。
        return Actions(
          actions: {
            TerminalFontSizeAdjustIntent:
                CallbackAction<TerminalFontSizeAdjustIntent>(
                  onInvoke: (intent) {
                    _adjustFontSize(intent.delta);
                    return null;
                  },
                ),
            TerminalFontSizeResetIntent:
                CallbackAction<TerminalFontSizeResetIntent>(
                  onInvoke: (intent) {
                    _resetFontSize();
                    return null;
                  },
                ),
            TerminalSearchIntent: CallbackAction<TerminalSearchIntent>(
              onInvoke: (intent) {
                _openSearch();
                return null;
              },
            ),
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: Column(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: MouseRegion(
                              // 指针离开终端：下划线跟着消失。
                              onExit: _onPointerExit,
                              child: Listener(
                                onPointerHover: _onPointerHover,
                                onPointerMove: _onPointerMove,
                                onPointerDown: _onPointerDown,
                                onPointerUp: _onPointerUp,
                                onPointerCancel: _onPointerCancel,
                                // 滚轮 / 拖动滚动条也会顶动画面，通知往上冒到这里。
                                child: NotificationListener<ScrollNotification>(
                                  onNotification: (notification) {
                                    _refreshLinkHover();
                                    return false;
                                  },
                                  child: ValueListenableBuilder<TerminalLink?>(
                                    valueListenable: _hoveredLink,
                                    builder: (context, link, _) =>
                                        _withScrollbar(
                                          prefs,
                                          TerminalView(
                                            widget.session.terminal,
                                            key: _terminalKey,
                                            controller: _controller,
                                            theme: prefs.theme,
                                            focusNode: _focusNode,
                                            // 自己拿着滚动控制器：滚动条与
                                            // 「回到最新」都要读同一个位置。
                                            scrollController: _scrollController,
                                            autofocus: true,
                                            // 移动端软键盘的删除键不走硬件按键事件，需要开启检测。
                                            deleteDetection: true,
                                            textStyle: _styleOf(prefs),
                                            padding: const EdgeInsets.all(10),
                                            shortcuts: _shortcuts,
                                            // 悬停在链接上换成手型光标：与下划线同一份判定。
                                            mouseCursor: link == null
                                                ? SystemMouseCursors.text
                                                : SystemMouseCursors.click,
                                            onSecondaryTapUp: (details, cell) =>
                                                _showContextMenu(
                                                  details.globalPosition,
                                                  cell,
                                                ),
                                          ),
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // 「回到最新」浮在终端右下角：只在滚上去时出现，
                          // 新输出不再自动把画面拽回底部（xterm 只在用户输入时
                          // 跳到底），刷屏日志后想回底就得有这颗按钮。
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: ValueListenableBuilder<bool>(
                              valueListenable: _atBottom,
                              builder: (context, atBottom, _) => atBottom
                                  ? const SizedBox.shrink()
                                  : _scrollToLatestButton(prefs),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 查找栏与键条都排在终端之下：用 Column 而不是浮层，
                    // 两者因此永远不遮住输出，终端行数跟着它们让出的高度重排。
                    if (_searching) _searchBar(prefs),
                    // 快捷键条排在终端之下、软键盘之上：用 Column 而不是浮层，
                    // 键条因此永远不遮住输出，终端行数会跟着它让出的高度重排。
                    if (_showKeyBar)
                      TerminalKeyBar(
                        session: widget.session,
                        onKeySent: _restoreTerminalFocus,
                      ),
                  ],
                ),
              ),
              // 链接下划线：浮在终端之上、不接指针事件。
              Positioned.fill(
                child: IgnorePointer(
                  child: ValueListenableBuilder<TerminalLink?>(
                    valueListenable: _hoveredLink,
                    builder: (context, link, _) => CustomPaint(
                      key: _underlineKey,
                      painter: LinkUnderlinePainter(
                        link: link,
                        color: prefs.theme.foreground,
                        terminalKey: _terminalKey,
                        overlayKey: _underlineKey,
                        repaint: _linkRepaint,
                      ),
                    ),
                  ),
                ),
              ),
              if (phase != TerminalPhase.connected)
                _overlay(context, phase, prefs),
              Positioned(
                top: 6,
                right: 8,
                child: _SessionToolbar(
                  session: widget.session,
                  controller: _controller,
                  onSearch: _openSearch,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 按偏好缓存 [TerminalStyle]。
  ///
  /// 必须缓存，不能每次 build 新建：xterm 的 `TerminalStyle` 没有
  /// `operator ==`，而它在 painter 与 render 两处的守卫都是身份比较。
  /// 新建一个内容相同的实例会一路穿过守卫，触发 `_measureCharSize()`
  /// （一次 `mmmmmmmmmm` 的 TextPainter 排版）并清空 10240 条段落缓存，
  /// 随后整个视口重排版。偏好没变就复用同一个实例。
  static TerminalStylePrefs? _cachedPrefsStyle;
  static TerminalStyle? _cachedStyle;

  static TerminalStyle _styleOf(TerminalStylePrefs prefs) {
    final cached = _cachedStyle;
    if (cached != null && _cachedPrefsStyle == prefs) return cached;
    final style = TerminalStyle(
      fontSize: prefs.fontSize.toDouble(),
      height: 1.45,
      fontFamily: prefs.resolvedFontFamily,
      fontFamilyFallback: prefs.fontFallback,
    );
    _cachedPrefsStyle = prefs;
    _cachedStyle = style;
    return style;
  }

  Widget _overlay(
    BuildContext context,
    TerminalPhase phase,
    TerminalStylePrefs prefs,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final plan = widget.reconnectPlan;
    final message = phase == TerminalPhase.connecting
        ? l10n.connectingTo(widget.session.server.account)
        : _failureText(l10n, phase);
    return Positioned.fill(
      child: ColoredBox(
        color: AppPalette.terminalDark.withValues(alpha: 0.8),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (phase == TerminalPhase.connecting)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              else
                Icon(
                  phase == TerminalPhase.failed
                      ? Icons.error_outline_rounded
                      : Icons.link_off_rounded,
                  size: 34,
                  color: phase == TerminalPhase.failed
                      ? AppPalette.danger
                      : theme.colorScheme.outline,
                ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  // 取终端配色的前景白：遮罩底色是固定的深色，文案跟着预设走
                  // 才能与用户挑的配色对得上。
                  color: prefs.theme.white,
                ),
              ),
              // 自动重连排在错误原因之后：先看到发生了什么，再看到接下来
              // 会发生什么；点「停止」后这行连同按钮一起消失，错误现场还原。
              if (plan != null) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.autoReconnectCountdown(
                    plan.delay.inSeconds,
                    plan.attempt,
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.outline.withValues(alpha: 0.9),
                  ),
                ),
              ],
              if (phase != TerminalPhase.connecting &&
                  widget.onRetry != null) ...[
                const SizedBox(height: 18),
                FilledButton.tonalIcon(
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: Text(l10n.reconnect),
                ),
                if (plan != null && widget.onStopAutoReconnect != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: widget.onStopAutoReconnect,
                    child: Text(l10n.autoReconnectStop),
                  ),
                ],
                // 指纹读不出来时不给「清除指纹」这条路：那会真的丢掉可信
                // 记录，而故障在存储层，重连或重启才是有意义的动作。
                if (phase == TerminalPhase.failed &&
                    widget.session.errorKind == TerminalErrorKind.hostKey &&
                    widget.session.hostKeys != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _forgetHostKeyAndRetry,
                    icon: const Icon(Icons.key_off_rounded, size: 17),
                    label: Text(l10n.hostKeyForgetAndRetry),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _failureText(AppLocalizations l10n, TerminalPhase phase) {
    // 干净地断开（远端关闭）不是失败原因：别把「网络错误」扣在它头上。
    if (phase == TerminalPhase.closed) return l10n.sessionClosedMsg;
    final reason = _reasonText(l10n);
    // 跳板链路上出的错必须指出是哪一跳：三台机器排在一起时，
    // 只说「认证失败」用户不知道该去改哪台的密码。
    final hop = widget.session.failedHop;
    return hop == null ? reason : l10n.jumpHopFailure(hop, reason);
  }

  String _reasonText(AppLocalizations l10n) =>
      switch (widget.session.errorKind) {
        TerminalErrorKind.auth => l10n.authFailedMsg,
        TerminalErrorKind.network => l10n.networkErrorMsg,
        TerminalErrorKind.unsupported => l10n.webUnsupportedMsg,
        // 指纹带上：用户需要拿它跟服务器上的实际指纹（ssh-keygen -lf）核对，
        // 只说「不匹配」等于让人无从判断，只能盲点「清除指纹」。
        TerminalErrorKind.hostKey =>
          widget.session.hostKeyChanged == null
              ? l10n.hostKeyChangedMsg
              : l10n.hostKeyChangedMsgWithFingerprint(
                  widget.session.hostKeyChanged!.keyType,
                  widget.session.hostKeyChanged!.fingerprint,
                ),
        TerminalErrorKind.hostKeyStore => l10n.hostKeyUnavailableMsg,
        TerminalErrorKind.privateKey => l10n.privateKeyUnsupportedMsg,
        TerminalErrorKind.agent => l10n.agentErrorMsg,
        TerminalErrorKind.jumpChain => l10n.jumpChainErrorMsg,
        TerminalErrorKind.other => widget.session.error ?? l10n.networkErrorMsg,
      };

  /// 清除指纹后重连。指纹对不上的是跳板机上那一跳时，清的必须是那一跳的
  /// 记录（[HostKeyChangedException] 自带 host / port），否则记录原封不动、
  /// 用户点几次都还是同一个错。
  ///
  /// 清之前先确认一次：这个按钮就摆在「疑似中间人」那段文案下面，一键点掉
  /// 等于把「警告 → 信任新密钥」压缩成一次点击，而新密钥此后就是可信记录。
  /// 文案里点明「下次连接直接信任对方出示的密钥」，把带外核对这件事说清楚。
  Future<void> _forgetHostKeyAndRetry() async {
    final l10n = AppLocalizations.of(context);
    final changed = widget.session.hostKeyChanged;
    final host = changed?.host ?? widget.session.server.host;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.hostKeyForgetConfirmTitle,
      body: l10n.hostKeyForgetConfirmBody(host),
      confirmLabel: l10n.hostKeyForgetConfirmAction,
    );
    if (!confirmed || !mounted) return;
    await widget.session.hostKeys?.delete(
      host,
      changed?.port ?? widget.session.server.port,
    );
    // 删除是异步的：这期间会话可能已经被换掉或关掉，别去重连一条用户
    // 已经不看了的会话。
    if (!mounted) return;
    widget.onRetry?.call();
  }
}

/// 终端右上角的会话工具条：复制 / 粘贴 / 命令片段的入口。
/// 悬浮在终端内容之上，底色用终端配色，图标对比度不随主题漂移。
final class _SessionToolbar extends StatelessWidget {
  const _SessionToolbar({
    required this.session,
    required this.controller,
    required this.onSearch,
  });

  final TerminalSession session;

  /// 选区状态源：复制按钮的可用态跟着它走。
  final TerminalController controller;

  /// 展开查找栏（⌘F / Ctrl+Shift+F 与工具栏按钮同一入口）。
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snippets = SnippetScope.maybeOf(context);
    // 终端样式只在「本工具条」这一小棵子树里监听：配色 / 字号变化时
    // 不连带终端视口重排。
    return ValueListenableBuilder<TerminalStylePrefs>(
      valueListenable: TerminalStyleScope.of(context).notifier,
      builder: (context, prefs, _) {
        final foreground = prefs.theme.foreground;
        // 触屏上按 44 的落点下限放大：工具条悬浮在终端之上，28 见方的按钮
        // 在手机上点十次错三次。桌面上保持紧凑——那里有鼠标，精度不是问题。
        final size = _isTouchPlatform ? 44.0 : 28.0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          decoration: BoxDecoration(
            color: prefs.theme.background.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: foreground.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 复制按钮只在有选区时可用；监听只包住按钮，选区高频变化
              // 时不牵动工具条其余部分。
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final hasSelection = controller.selection != null;
                  return _ToolbarButton(
                    tooltip: l10n.copy,
                    icon: Icons.copy_rounded,
                    size: size,
                    color: hasSelection
                        ? foreground
                        : foreground.withValues(alpha: 0.35),
                    onTap: hasSelection
                        ? () => copyTerminalSelection(
                            session.terminal,
                            controller,
                          )
                        : null,
                  );
                },
              ),
              _ToolbarButton(
                tooltip: l10n.paste,
                icon: Icons.content_paste_rounded,
                size: size,
                color: foreground,
                onTap: () => pasteIntoTerminal(session.terminal),
              ),
              _ToolbarButton(
                tooltip: l10n.searchTerminal,
                icon: Icons.search_rounded,
                size: size,
                color: foreground,
                onTap: onSearch,
              ),
              if (snippets != null)
                _ToolbarButton(
                  tooltip: l10n.snippets,
                  icon: Icons.code_rounded,
                  size: size,
                  color: foreground,
                  onTap: () => showSnippetDialog(
                    context,
                    snippets: snippets,
                    session: session,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 工具条按钮：尺寸手工收紧以贴合圆角胶囊；触屏上传 [size] 44 满足落点下限。
final class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 28,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  /// 触控目标边长（逻辑像素）。
  final double size;

  @override
  Widget build(BuildContext context) {
    final touch = size >= 44;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: touch ? 20 : 17, color: color),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.all(touch ? 10 : 5),
      constraints: BoxConstraints.tightFor(width: size, height: size),
    );
  }
}

/// 链接下划线：把命中的链接按格子跨度换算成像素，画一条 1px 线。
///
/// 公开只为可测：widget 测试直接断言它拿到的链接跨度，不必去抠像素。
///
/// 几何全部问终端自己的 render object（`RenderTerminal.getOffset`），
/// 坐标换算走 `globalToLocal`：浮层与终端之间隔着 Container 的 padding，
/// 自己按格宽乘会和包对不上。改字号 / 折行 / 滚动因此都不会错位。
@visibleForTesting
final class LinkUnderlinePainter extends CustomPainter {
  LinkUnderlinePainter({
    required this.link,
    required this.color,
    required this.terminalKey,
    required this.overlayKey,
    required Listenable repaint,
  }) : super(repaint: repaint);

  /// 要画下划线的链接；为空时整层什么都不画。
  final TerminalLink? link;

  /// 下划线颜色：跟终端前景色走，与格子里的文字同一套配色。
  final Color color;

  final GlobalKey<TerminalViewState> terminalKey;

  /// 浮层自己的 key：拿它的 render object 当坐标系原点。
  final GlobalKey overlayKey;

  @override
  void paint(Canvas canvas, Size size) {
    final target = link;
    if (target == null) return;
    final overlay = overlayKey.currentContext?.findRenderObject();
    final render = terminalKey.currentState?.renderTerminal;
    if (overlay is! RenderBox || render == null) return;

    final start = render.getOffset(CellOffset(target.startCell, target.row));
    final end = render.getOffset(CellOffset(target.endCell, target.row));
    final from = overlay.globalToLocal(render.localToGlobal(start));
    final to = overlay.globalToLocal(render.localToGlobal(end));

    // 贴着格子底边画。整行滚出视口时 y 会落在框外，跳过。
    final y = from.dy + render.cellSize.height - 1;
    if (y < 0 || y > size.height) return;
    canvas.drawLine(
      Offset(from.dx, y),
      Offset(to.dx, y),
      Paint()
        ..color = color
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(LinkUnderlinePainter oldDelegate) =>
      oldDelegate.link != link || oldDelegate.color != color;
}

/// 只为「让下划线重画一次」存在的通知源：
/// `ChangeNotifier.notifyListeners` 是 protected，外面调不到。
final class _LinkRepaint extends ChangeNotifier {
  void ping() => notifyListeners();
}
