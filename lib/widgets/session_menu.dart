import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../ssh/session_manager.dart';
import '../ssh/terminal_session.dart';
import '../ssh/terminal_view.dart' show serverStatusOf;
import '../theme.dart';
import 'session_log_dialog.dart';
import 'status_badges.dart';

/// 会话菜单：多会话时点详情头部的状态胶囊弹出来的那个小浮层。
///
/// 一行一条会话：状态点 + 标题 + 行尾关闭。标题优先用远端 OSC 标题
/// （shell / tmux 会发 `user@host: ~/dir` 这种串），远端没设过才退回
/// 「会话 N」——同一台主机的两条 shell 因此一眼能分开。
///
/// 单独一条会话时界面不弹这个菜单（点胶囊直接进会话日志），所以这里
/// 只处理「切会话 / 关一条 / 再开一条 / 看日志」四件事，不承担单会话入口。
Future<void> showSessionMenu(
  BuildContext context, {
  required SessionManager sessions,
  required SshServer server,

  /// 胶囊的 key：菜单锚在它下方，宽度与位置都跟着它走。
  required GlobalKey anchor,
  required VoidCallback onNewSession,
}) async {
  final l10n = AppLocalizations.of(context);
  final box = anchor.currentContext?.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  // 锚在「胶囊左下角再往下 4pt」的零尺寸点上：showMenu 直接把锚点当成菜单
  // 左上角（_PopupMenuRouteLayout 取的就是 position.top/left），拿整块胶囊
  // rect 当锚会把胶囊、⊕ 一起压在菜单底下——点开反而看不见自己点了什么。
  // 侧边栏的 ⋯ 菜单用的也是这套零尺寸锚法。下方放不下时 Flutter 自己会往上翻。
  final anchorOrigin = box?.localToGlobal(Offset.zero);
  final position = RelativeRect.fromRect(
    box == null || anchorOrigin == null
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : Rect.fromLTWH(
            anchorOrigin.dx,
            anchorOrigin.dy + box.size.height + 4,
            0,
            0,
          ),
    Offset.zero & overlay.size,
  );
  final current = sessions.activeOf(server.id);
  final selected = await showMenu<Object>(
    context: context,
    position: position,
    items: [
      for (final session in sessions.sessionsOf(server.id))
        PopupMenuItem<Object>(
          value: session,
          // 与侧边栏菜单同高（36）：本项目的菜单行只有这一档密度。
          height: 36,
          padding: EdgeInsets.zero,
          child: _SessionRow(
            session: session,
            ordinal: sessions.ordinalOf(session),
            selected: identical(session, current),
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem<Object>(
        value: _SessionMenuAction.newSession,
        height: 36,
        // 与会话行同样零内边距：两边的文字才会落在同一列（36pt）。
        padding: EdgeInsets.zero,
        child: _MenuAction(icon: Icons.add_rounded, label: l10n.newSession),
      ),
      PopupMenuItem<Object>(
        value: _SessionMenuAction.log,
        height: 36,
        padding: EdgeInsets.zero,
        child: _MenuAction(
          icon: Icons.receipt_long_outlined,
          label: l10n.sessionLog,
        ),
      ),
    ],
  );
  if (!context.mounted || selected == null) return;
  if (selected is _CloseRequest) {
    sessions.closeSession(selected.session);
  } else if (selected is TerminalSession) {
    sessions.activate(selected);
  } else if (selected == _SessionMenuAction.newSession) {
    onNewSession();
  } else if (selected == _SessionMenuAction.log) {
    final session = sessions.activeOf(server.id);
    if (session != null) await showSessionLogDialog(context, session: session);
  }
}

/// 菜单里两项固定动作；会话行本身以 [TerminalSession] 作为返回值。
enum _SessionMenuAction { newSession, log }

/// 「关掉这一条」请求：行尾 × 不能直接关（菜单已经展开，行会变成幽灵），
/// 于是先关菜单、回到 [showSessionMenu] 里再动手。
final class _CloseRequest {
  const _CloseRequest(this.session);

  final TerminalSession session;
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.ordinal,
    required this.selected,
  });

  final TerminalSession session;
  final int ordinal;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // 标题随远端输出实时变（cd 一下就该跟着改），只重建这一行。
    return ValueListenableBuilder<String>(
      valueListenable: session.title,
      builder: (context, title, _) => Padding(
        // 整行内容从菜单左缘内缩 8pt：当前会话那道具竖条因此不会贴在菜单
        // 圆角上被切掉，文字列也正好落在动作项那一列（都是 36pt）。
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          children: [
            // 当前会话：左侧一道 2pt 竖条。不加底色块——菜单本来就窄，
            // 一块底色会把整行压得比其它行重。
            Container(
              width: 2,
              height: 18,
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(width: 10),
            StatusDot(status: serverStatusOf(session.phase), size: 7),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title.isEmpty ? l10n.sessionN(ordinal) : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: theme.colorScheme.onSurface.withValues(
                    alpha: selected ? 1 : 0.86,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: l10n.closeSession,
              icon: Icon(
                Icons.close_rounded,
                size: 14,
                color: theme.secondaryText,
              ),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 26, height: 26),
              onPressed: () =>
                  Navigator.of(context).pop(_CloseRequest(session)),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

class _MenuAction extends StatelessWidget {
  const _MenuAction({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 12),
        Icon(icon, size: 16),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}
