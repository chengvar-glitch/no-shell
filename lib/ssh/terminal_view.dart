import 'dart:async';

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
import 'terminal_session.dart';

/// 链接点击的容差：按下与抬起之间超过这么多像素就算拖选，不算点击。
/// 鼠标会抖，但不能大到把「选一小段字」也算成点击。
const double _linkTapSlop = 6;

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

  /// 键位表只在 init 时算一次：平台运行中不会变，每次 build 新建只会
  /// 让包的 ShortcutManager 白白换表。
  late final Map<ShortcutActivator, Intent> _shortcuts = terminalShortcuts();

  /// 选中即复制的去抖：拖选过程中选区连续变化（每次都通知），等最后一次
  /// 变化后静默一小段时间再复制，落进剪贴板的才是完整选区；双击选词、
  /// 长按选词也走同一条路。
  Timer? _copyOnSelectTimer;

  /// 当前是否开启选中即复制；每次偏好重建时刷新，供控制器回调读取。
  bool _copyOnSelect = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSelectionChanged);
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

  /// 指针按下：只有鼠标左键单击才是链接点击的候选。
  void _onPointerDown(PointerDownEvent event) {
    _linkTapOrigin =
        event.kind == PointerDeviceKind.mouse && event.buttons == kPrimaryButton
        ? event.position
        : null;
  }

  /// 指针在终端上移动（没按任何键）：重新判定下划线。
  void _onPointerHover(PointerHoverEvent event) {
    _pointer = event.position;
    _refreshLinkHover();
  }

  /// 按住键拖动（拖选文字）期间不画下划线：指针位置作废，松手时再恢复。
  void _onPointerMove(PointerMoveEvent event) {
    _pointer = null;
    _refreshLinkHover();
  }

  void _onPointerExit(PointerExitEvent event) {
    _pointer = null;
    _refreshLinkHover();
  }

  /// Cmd/Ctrl+单击：命中链接就交给系统打开；普通点击原样还给终端。
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

    final origin = _linkTapOrigin;
    _linkTapOrigin = null;
    if (origin == null) return;
    // 拖着选字松手不算点击。
    if ((event.position - origin).distance > _linkTapSlop) return;
    if (!isLinkModifierPressed()) return;
    final cell = _cellAt(event.position);
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

  Future<void> _showContextMenu(TapUpDetails details, CellOffset cell) async {
    final l10n = AppLocalizations.of(context);
    final position = details.globalPosition;
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
          },
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
                    // 滚轮 / 拖动滚动条也会顶动画面，通知往上冒到这里。
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        _refreshLinkHover();
                        return false;
                      },
                      child: ValueListenableBuilder<TerminalLink?>(
                        valueListenable: _hoveredLink,
                        builder: (context, link, _) => TerminalView(
                          widget.session.terminal,
                          key: _terminalKey,
                          controller: _controller,
                          theme: prefs.theme,
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
                          onSecondaryTapUp: _showContextMenu,
                        ),
                      ),
                    ),
                  ),
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
  const _SessionToolbar({required this.session, required this.controller});

  final TerminalSession session;

  /// 选区状态源：复制按钮的可用态跟着它走。
  final TerminalController controller;

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
                color: foreground,
                onTap: () => pasteIntoTerminal(session.terminal),
              ),
              if (snippets != null)
                _ToolbarButton(
                  tooltip: l10n.snippets,
                  icon: Icons.code_rounded,
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

/// 工具条按钮：紧凑的图标按钮，尺寸手工收紧以贴合圆角胶囊。
final class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 17, color: color),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(5),
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
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
