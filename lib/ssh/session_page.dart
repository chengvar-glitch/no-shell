import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets/session_menu.dart';
import '../widgets/status_badges.dart';
import 'connect_flow.dart';
import 'credential_store.dart';
import 'session_manager.dart';
import 'terminal_session.dart';
import 'terminal_view.dart';

/// 全屏终端页：从移动端会话列表进入，断开后自动退回。
///
/// **不挂 AppBar**：手机上一行 AppBar + 状态栏要吃掉 ~80pt，键盘弹起时终端
/// 只剩个位数行。改成浮在终端之上的一条头部——进页面先亮 3 秒，之后收起；
/// 轻点顶部一条（translucent，事件照旧落给终端）唤出，点终端正文立刻收回。
/// 头部里是返回、主机名、状态胶囊（点开是会话日志，多开了才换成会话菜单，
/// 见 [openSessionPill]）与断开。
final class SessionPage extends StatefulWidget {
  const SessionPage({
    super.key,
    required this.sessions,
    required this.serverId,
    required this.credentials,
  });

  final SessionManager sessions;
  final String serverId;

  /// 「新建会话」要按连接流程再取一次凭据（存档 / 现存会话 / agent / 弹窗）。
  final CredentialStore credentials;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  /// 胶囊自己的 key：会话菜单锚在它下方（与桌面头部同一套锚法）。
  final GlobalKey _pillKey = GlobalKey();

  /// 头部亮多久。够读完一行「主机名 + 已连接」，又不至于一直压着终端。
  static const Duration _hideDelay = Duration(seconds: 3);

  /// 顶部唤出条的高度（不含状态栏）：头部收起后，这一条仍然认得轻点。
  static const double _revealStripHeight = 44;

  bool _headerVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (mounted) setState(() => _headerVisible = false);
    });
  }

  void _showHeader() {
    if (!_headerVisible) setState(() => _headerVisible = true);
    _scheduleHide();
  }

  void _hideHeader() {
    _hideTimer?.cancel();
    if (_headerVisible) setState(() => _headerVisible = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sessions = widget.sessions;
    final store = sessions.store;
    final terminalTheme = TerminalStyleScope.of(context).notifier.value.theme;
    return ListenableBuilder(
      listenable: sessions,
      builder: (context, _) {
        final session = sessions.activeOf(widget.serverId);
        final server = store.byId(widget.serverId);
        final count = sessions.sessionsOf(widget.serverId).length;
        // 顶部唤出条要把状态栏那一带也算进去：刘海机上空出的一截也认得轻点。
        final strip = MediaQuery.paddingOf(context).top + _revealStripHeight;
        return Scaffold(
          // 底色跟着终端走：不挂 AppBar 之后，状态栏那一带露出的是页面底色，
          // 与终端底色差一点点就会在顶部留一道接缝。
          backgroundColor: session == null ? null : terminalTheme.background,
          body: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  // 点终端正文就收起头部：终端是全屏的，头部只是浮在上面的一层。
                  onPointerDown: (event) {
                    if (event.localPosition.dy > strip) _hideHeader();
                  },
                  child: SafeArea(
                    child: session == null
                        ? Center(child: Text(l10n.sessionClosedMsg))
                        : SshTerminalView(
                            session: session,
                            onRetry: () => sessions.retry(session),
                            reconnectPlan: sessions.reconnectPlanOf(session),
                            onStopAutoReconnect: () =>
                                sessions.cancelAutoReconnect(session),
                          ),
                  ),
                ),
              ),
              // 唤出条：translucent 只把自己加进命中结果、不吃掉事件，
              // 终端照样收得到这一下轻点（Listener 也不进手势竞技场）。
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: strip,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => _showHeader(),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !_headerVisible,
                  child: AnimatedOpacity(
                    opacity: _headerVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: _header(
                      context,
                      server?.name ?? 'SSH',
                      session,
                      count,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(
    BuildContext context,
    String title,
    TerminalSession? session,
    int count,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: theme.panelBackground.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.hairline),
          ),
          child: Row(
            children: [
              const BackButton(),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (session != null) ...[
                const SizedBox(width: 8),
                StatusPill(
                  key: _pillKey,
                  status: serverStatusOf(session.phase),
                  // 多开了才显示计数：一条会话时胶囊的外观与多会话功能
                  // 之前完全一样。
                  sessionCount: count,
                  tooltip: count > 1 ? l10n.sessionMenu : null,
                  onTap: () {
                    _showHeader();
                    final server = widget.sessions.store.byId(widget.serverId);
                    if (server == null) return;
                    openSessionPill(
                      context,
                      sessions: widget.sessions,
                      server: server,
                      anchor: _pillKey,
                      onNewSession: () => newSessionFlow(
                        context,
                        sessions: widget.sessions,
                        server: server,
                        credentials: widget.credentials,
                        store: widget.sessions.store,
                      ),
                    );
                  },
                ),
                const Spacer(),
                IconButton(
                  tooltip: l10n.disconnect,
                  icon: const Icon(Icons.link_off_rounded, size: 19),
                  onPressed: () => widget.sessions.closeAll(widget.serverId),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
