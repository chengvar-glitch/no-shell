import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../ssh/session_manager.dart';
import '../ssh/terminal_session.dart';

/// 会话切换的瞬时提示：切到另一条会话后，终端顶部短暂浮出
/// 「会话 N · 远端标题」，约 1.4 秒后自动淡出（tmux 切窗口的提示条同款
/// 思路）。
///
/// 为什么要有它：终端内容直接换掉，两条 shell 长得一样时用户看不出切过了；
/// 常驻的线索只有状态胶囊上的「会话 N/M」文字。键盘切换（⌘1…⌘9）不看胶囊，
/// 这条浮条就是那一下按键的即时回执。
///
/// 纪律：整层 [IgnorePointer]——浮条不许吃终端的点击、不许进手势竞技场；
/// 挂在与终端同级的 Stack 上、不占布局高度，PTY 不因此重排。单会话主机
/// 不提示（没有「切」可言）。
class SessionSwitchFlash extends StatefulWidget {
  const SessionSwitchFlash({
    super.key,
    required this.sessions,
    required this.serverId,
  });

  final SessionManager sessions;
  final String serverId;

  @override
  State<SessionSwitchFlash> createState() => _SessionSwitchFlashState();
}

class _SessionSwitchFlashState extends State<SessionSwitchFlash> {
  static const _holdDuration = Duration(milliseconds: 1400);
  static const _fadeDuration = Duration(milliseconds: 220);

  /// 上一次看到的当前会话；身份变化即「切过了一下」。
  TerminalSession? _last;

  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _last = widget.sessions.activeOf(widget.serverId);
    widget.sessions.addListener(_onSessionsChanged);
  }

  @override
  void didUpdateWidget(SessionSwitchFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessions != widget.sessions ||
        oldWidget.serverId != widget.serverId) {
      oldWidget.sessions.removeListener(_onSessionsChanged);
      widget.sessions.addListener(_onSessionsChanged);
      _last = widget.sessions.activeOf(widget.serverId);
      _dismiss();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.sessions.removeListener(_onSessionsChanged);
    super.dispose();
  }

  void _onSessionsChanged() {
    final current = widget.sessions.activeOf(widget.serverId);
    if (identical(current, _last)) return;
    _last = current;
    // 当前会话没了（全部关掉）不提示，收掉可能还挂着的上一条即可。
    if (current == null || !mounted) {
      _dismiss();
      return;
    }
    // 单会话没有切换语义（第一次连上不算「切」）。
    if (widget.sessions.sessionsOf(widget.serverId).length <= 1) return;
    _timer?.cancel();
    setState(() => _visible = true);
    _timer = Timer(_holdDuration, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _dismiss() {
    _timer?.cancel();
    _timer = null;
    if (mounted && _visible) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = _last;
    if (session == null) return const SizedBox.shrink();
    final ordinal = widget.sessions.ordinalOf(session);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: _fadeDuration,
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Center(
            child: _Chip(session: session, ordinal: ordinal),
          ),
        ),
      ),
    );
  }
}

/// 浮条本体：深色圆角底 + 「会话 N · 标题」。标题用远端 OSC 标题
/// （shell / tmux 会设 `user@host: ~/dir`），没有就退回「会话 N」；
/// 标题随远端输出实时变，浮条内自己订阅。
class _Chip extends StatelessWidget {
  const _Chip({required this.session, required this.ordinal});

  final TerminalSession session;
  final int ordinal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<String>(
      valueListenable: session.title,
      builder: (context, title, _) {
        // 文案带「已切到」前缀：与会话菜单里的「会话 N」行、胶囊上的
        // 「会话 n/N」在 find.text 断言与读感上都区分开。
        final label = title.isEmpty
            ? l10n.switchedToSession(ordinal)
            : '${l10n.switchedToSession(ordinal)} · $title';
        return Material(
          color: theme.colorScheme.inverseSurface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onInverseSurface,
              ),
            ),
          ),
        );
      },
    );
  }
}
