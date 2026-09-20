import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../theme.dart';

/// 主机状态圆点，已连接时带光晕。
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.status, this.size = 8});

  final ServerStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).statusColor(status);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: status == ServerStatus.connected
            ? [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 6)]
            : null,
      ),
    );
  }
}

/// 状态胶囊的配色：底色（状态色 13%）+ 文字色。
///
/// 抽成纯函数是为了可测：11px 半粗小字在浅色底上很容易掉到 WCAG AA 以下
/// （曾经是 3.2:1），而这里没有 BuildContext 也能算——见
/// `test/status_badges_test.dart` 的对比度断言。
///
/// 浅色主题的状态色本身已是深色值（见 [AppPalette]），圆点直接铺底就过
/// 非文字元素的 3:1；胶囊文字要过的是 13% 状态色叠出来的底上的 AA，比纯白
/// 深一截，所以浅色底还得再往黑压一档。深色底上提亮同样的量（本来就有
/// 6:1 以上）。
({Color background, Color foreground}) pillColors(
  ThemeData theme,
  ServerStatus status,
) {
  final color = theme.statusColor(status);
  return (
    background: color.withValues(alpha: 0.13),
    foreground: theme.brightness == Brightness.dark
        ? Color.lerp(color, Colors.white, 0.3)!
        : Color.lerp(color, Colors.black, 0.25)!,
  );
}

/// 主机状态胶囊标签。
///
/// [onTap] 非空时整颗胶囊可点：会话日志的入口就挂在连接状态上——
/// 有会话才有日志可看，调用方据此决定是否传回调。
///
/// [sessionCount] 大于 1 时胶囊多出 ` · N` 与一枚 `⌄`：这台主机开了多条
/// 会话，点开是会话菜单（见 `session_menu.dart`）而不是单条会话的日志。
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.status,
    this.onTap,
    this.sessionCount = 0,
    this.tooltip,
  });

  final ServerStatus status;

  final VoidCallback? onTap;

  /// 该主机挂着的会话数；0 / 1 时胶囊与只有一个会话时完全一样。
  final int sessionCount;

  /// 悬停提示；为空时按「点开的是会话日志」给提示。
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final color = theme.statusColor(status);
    final palette = pillColors(theme, status);
    final label = switch (status) {
      ServerStatus.connected => l10n.statusConnected,
      ServerStatus.connecting => l10n.statusConnecting,
      ServerStatus.error => l10n.statusError,
      ServerStatus.idle => l10n.statusIdle,
    };
    final multi = sessionCount > 1;
    final pill = Container(
      // 左 8 右 7：chevron 字形自带约 1pt 右侧留白，扣掉它两边看起来才等宽。
      padding: const EdgeInsets.fromLTRB(8, 4, 7, 4),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            multi ? l10n.statusWithCount(label, sessionCount) : label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: palette.foreground,
            ),
          ),
          if (multi) ...[
            // 与文字只隔 1pt：图标盒子里本来就有留白，视觉间距落在 4pt 上下，
            // 和左侧「圆点—文字」的 5pt 成比例。12pt 的箭头笔画比 11pt 文字还重，
            // 降一档让它退回"可展开"的提示位。
            const SizedBox(width: 1),
            Icon(
              Icons.expand_more_rounded,
              size: 11,
              color: palette.foreground,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return pill;
    // Tooltip 与点击能力一起出现：胶囊长得不像按钮，悬停提示是唯一的
    // 可发现性线索（单会话点开的是会话日志，多会话点开的是会话菜单）。
    // 反馈色用状态色而不是中性灰：13% 的底色透上来正好是同一色系加深一层。
    return Tooltip(
      message: tooltip ?? l10n.sessionLog,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        hoverColor: color.withValues(alpha: 0.12),
        highlightColor: color.withValues(alpha: 0.14),
        splashColor: color.withValues(alpha: 0.18),
        child: pill,
      ),
    );
  }
}
