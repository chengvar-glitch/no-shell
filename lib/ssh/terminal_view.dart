import 'dart:async';

import 'package:flutter/material.dart';
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
/// Cmd/Ctrl+点击打开链接，以及可选的「选中即复制」。
final class SshTerminalView extends StatefulWidget {
  const SshTerminalView({
    super.key,
    required this.session,
    this.onRetry,
    this.reconnectPlan,
    this.onStopAutoReconnect,
  });

  final TerminalSession session;

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
  }

  @override
  void dispose() {
    _copyOnSelectTimer?.cancel();
    _controller
      ..removeListener(_onSelectionChanged)
      ..dispose();
    super.dispose();
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

  /// Cmd/Ctrl+点击：命中链接就交给系统打开；普通点击原样还给终端。
  Future<void> _onTapUp(TapUpDetails details, CellOffset cell) async {
    if (!isLinkModifierPressed()) return;
    final url = findLinkAtCell(widget.session.terminal, cell);
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final opened = await openTerminalLink(uri);
    if (!opened && mounted) {
      showToast(context, AppLocalizations.of(context).linkOpenFailed);
    }
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
                child: TerminalView(
                  widget.session.terminal,
                  controller: _controller,
                  theme: prefs.theme,
                  autofocus: true,
                  // 移动端软键盘的删除键不走硬件按键事件，需要开启检测。
                  deleteDetection: true,
                  textStyle: _styleOf(prefs),
                  padding: const EdgeInsets.all(10),
                  shortcuts: _shortcuts,
                  onTapUp: _onTapUp,
                  onSecondaryTapUp: _showContextMenu,
                ),
              ),
              if (phase != TerminalPhase.connected) _overlay(context, phase),
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

  Widget _overlay(BuildContext context, TerminalPhase phase) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final plan = widget.reconnectPlan;
    final message = phase == TerminalPhase.connecting
        ? l10n.connectingTo(widget.session.server.account)
        : _failureText(l10n, phase);
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xCC0A0C0F),
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
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xFFB9C4CF),
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
