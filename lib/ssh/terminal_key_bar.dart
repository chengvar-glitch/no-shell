import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xterm/core.dart';
import 'package:xterm/ui.dart';

import '../l10n/generated/app_localizations.dart';
import '../settings.dart';
import 'terminal_input_modifiers.dart';
import 'terminal_session.dart';

/// 软键盘上方的快捷键条（`SshTerminalView` 只在触屏平台挂它）。
///
/// 手机软键盘上没有 Esc、Tab、Ctrl 和方向键，而没有这几颗键就做不成最基本
/// 的几件事：Ctrl+C 中断命令、Tab 补全路径、方向键翻历史、Esc 退出插入模式。
/// 键条补的就是这一排。
///
/// 两条实现上的取舍：
/// - 整条键条走 [GestureDetector] 而不是按钮：按钮会参与焦点体系，点一下
///   就把焦点从终端抢走、软键盘跟着收起；`GestureDetector` 压根不碰焦点。
/// - 修饰键是**粘滞**的（点一次作用于下一个按键），见 [TerminalInputModifiers]：
///   触屏上按不出「按住 Ctrl 再按字母」，只有粘滞才用得起来。
final class TerminalKeyBar extends StatefulWidget {
  const TerminalKeyBar({
    super.key,
    required this.session,
    this.onKeySent,
    this.trackpad = false,
    this.trackpadAvailable,
    this.onToggleTrackpad,
  });

  final TerminalSession session;

  /// 每次按键后回调：宿主据此把焦点补回终端（焦点一旦丢了，软键盘会收起）。
  final VoidCallback? onKeySent;

  /// 鼠标模式是否开着（拖动转发给远端，而不是滚本地画面）。
  final bool trackpad;

  /// 远端是否开着鼠标上报；为空或为 false 时鼠标模式那颗键置灰——
  /// 远端没人接鼠标事件，开了也没用。
  final ValueListenable<bool>? trackpadAvailable;

  final VoidCallback? onToggleTrackpad;

  @override
  State<TerminalKeyBar> createState() => _TerminalKeyBarState();
}

class _TerminalKeyBarState extends State<TerminalKeyBar> {
  bool _collapsed = false;

  Terminal get _terminal => widget.session.terminal;

  void _sendKey(TerminalKey key) {
    _terminal.keyInput(key);
    widget.onKeySent?.call();
  }

  /// 字号只改全局偏好：与设置页的步进、Cmd/Ctrl 加减走同一条落盘链路。
  /// 越界由 `withFontSize` 夹住，按钮在边界上直接置灰。
  void _adjustFontSize(int delta) {
    final notifier = TerminalStyleScope.of(context).notifier;
    notifier.value = notifier.value.withFontSize(
      notifier.value.fontSize + delta,
    );
    widget.onKeySent?.call();
  }

  void _toggleModifier({required bool ctrl}) {
    final modifiers = widget.session.inputModifiers;
    ctrl ? modifiers.toggleCtrl() : modifiers.toggleAlt();
    widget.onKeySent?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 跟着终端配色走：键条紧贴终端，用界面主题的底色会在深浅主题下露出接缝。
    return ValueListenableBuilder<TerminalStylePrefs>(
      valueListenable: TerminalStyleScope.of(context).notifier,
      builder: (context, prefs, _) => ListenableBuilder(
        listenable: widget.session.inputModifiers,
        builder: (context, _) {
          final modifiers = widget.session.inputModifiers;
          final colors = prefs.theme;
          final armed = [
            if (modifiers.ctrl) 'Ctrl',
            if (modifiers.alt) 'Alt',
          ].join(' + ');
          return Container(
            decoration: BoxDecoration(
              color: colors.background,
              border: Border(
                top: BorderSide(
                  color: colors.foreground.withValues(alpha: 0.14),
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Stack(
              // 待命提示浮在键条上方，不占布局：键条高度一变，PTY 就跟着
              // 重排一次，按一下 Ctrl 抖一下画面。
              clipBehavior: Clip.none,
              children: [
                _collapsed ? _collapsedRow(l10n, colors) : _keyRow(l10n, prefs),
                if (armed.isNotEmpty && !_collapsed)
                  Positioned(
                    right: 0,
                    bottom: 44,
                    child: _hint(l10n.stickyModifierHint(armed), colors),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _keyRow(AppLocalizations l10n, TerminalStylePrefs prefs) {
    final colors = prefs.theme;
    final modifiers = widget.session.inputModifiers;
    return Row(
      children: [
        // 窄屏（320pt）放不下整排键：让键位横向滚动，折叠按钮始终留在右端。
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _KeyButton(
                  label: 'esc',
                  onTap: () => _sendKey(TerminalKey.escape),
                ),
                _KeyButton(
                  label: 'tab',
                  onTap: () => _sendKey(TerminalKey.tab),
                ),
                _KeyButton(
                  label: 'ctrl',
                  active: modifiers.ctrl,
                  onTap: () => _toggleModifier(ctrl: true),
                ),
                _KeyButton(
                  label: 'alt',
                  active: modifiers.alt,
                  onTap: () => _toggleModifier(ctrl: false),
                ),
                _KeyButton(
                  label: '←',
                  onTap: () => _sendKey(TerminalKey.arrowLeft),
                ),
                _KeyButton(
                  label: '↑',
                  onTap: () => _sendKey(TerminalKey.arrowUp),
                ),
                _KeyButton(
                  label: '↓',
                  onTap: () => _sendKey(TerminalKey.arrowDown),
                ),
                _KeyButton(
                  label: '→',
                  onTap: () => _sendKey(TerminalKey.arrowRight),
                ),
                // 字号：触屏上调字号此前只能进设置页点步进（或接物理键盘按
                // Cmd/Ctrl 加减）。捏合缩放要在 Scrollable 已经认领第一根
                // 手指之后再拿两指跨度，且逐帧改字号会让 PTY 每帧重排一次，
                // 所以在键条上给一对明确的加减键。
                _KeyButton(
                  label: 'A-',
                  tooltip: l10n.fontSizeDecrease,
                  enabled: prefs.fontSize > TerminalStylePrefs.minFontSize,
                  onTap: () => _adjustFontSize(-1),
                ),
                _KeyButton(
                  label: 'A+',
                  tooltip: l10n.fontSizeIncrease,
                  enabled: prefs.fontSize < TerminalStylePrefs.maxFontSize,
                  onTap: () => _adjustFontSize(1),
                ),
                // 鼠标模式：触屏上拖动默认是滚画面，而远端程序（vim / tmux）
                // 开了鼠标上报时拖动本该是「按住左键拖」。两者只能二选一，
                // 所以做成一颗可切换的键，远端着鼠标上报时它才亮起来。
                if (widget.onToggleTrackpad != null) _trackpadKey(l10n),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        _KeyButton(
          icon: Icons.keyboard_arrow_down_rounded,
          tooltip: l10n.keyBarCollapse,
          color: colors,
          onTap: () => setState(() => _collapsed = true),
        ),
      ],
    );
  }

  /// 鼠标模式那颗键：可用性跟着远端走，只重建它自己。
  Widget _trackpadKey(AppLocalizations l10n) {
    final available = widget.trackpadAvailable;
    Widget button(bool enabled) => _KeyButton(
      label: l10n.trackpadMode,
      tooltip: enabled ? l10n.trackpadModeHint : l10n.trackpadUnavailable,
      active: widget.trackpad,
      enabled: enabled,
      onTap: widget.onToggleTrackpad!,
    );
    if (available == null) return button(true);
    return ValueListenableBuilder<bool>(
      valueListenable: available,
      builder: (context, enabled, child) => button(enabled),
    );
  }

  Widget _collapsedRow(AppLocalizations l10n, TerminalTheme colors) {
    return Align(
      alignment: Alignment.centerRight,
      child: _KeyButton(
        icon: Icons.keyboard_arrow_up_rounded,
        label: l10n.keyBarTitle,
        tooltip: l10n.keyBarExpand,
        color: colors,
        onTap: () => setState(() => _collapsed = false),
      ),
    );
  }

  Widget _hint(String text, TerminalTheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: colors.foreground.withValues(alpha: 0.28)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, color: colors.foreground),
      ),
    );
  }
}

/// 键条上的一颗键：固定 44×40 的触控目标，不参与焦点体系。
///
/// 尺寸取 44×40 而不是 40 见方：宽度按拇指落点（44 是各家指南的下限），
/// 高度收一点，键条整体才不至于占掉一整行终端。图标键（折叠）同样 44 宽。
final class _KeyButton extends StatelessWidget {
  const _KeyButton({
    this.label,
    this.icon,
    this.tooltip,
    this.active = false,
    this.enabled = true,
    this.color,
    required this.onTap,
  }) : assert(label != null || icon != null, '键帽要么有文字要么有图标');

  final String? label;
  final IconData? icon;
  final String? tooltip;

  /// 修饰键待命时点亮。
  final bool active;

  /// 置灰（如字号已经到顶）；点了不做事。
  final bool enabled;

  /// 键条配色（终端配色）；不传时用默认深色，仅供无主题场景兜底。
  final TerminalTheme? color;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = color;
    final base = palette?.foreground ?? const Color(0xFFD6DEE7);
    final foreground = enabled ? base : base.withValues(alpha: 0.35);
    final background = palette?.background ?? const Color(0xFF0A0C0F);
    final Widget content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 40,
          constraints: const BoxConstraints(minWidth: 44),
          margin: const EdgeInsets.only(right: 5),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active
                ? foreground.withValues(alpha: 0.22)
                : background.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: active
                  ? foreground.withValues(alpha: 0.55)
                  : foreground.withValues(alpha: 0.18),
            ),
          ),
          child: Center(
            widthFactor: 1,
            child: icon != null && label == null
                ? Icon(icon, size: 20, color: foreground)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 18, color: foreground),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        label!,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1,
                          color: foreground,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: active,
      label: tooltip ?? label,
      child: tooltip == null
          ? content
          : Tooltip(message: tooltip!, child: content),
    );
  }
}
