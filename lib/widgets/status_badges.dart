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
    final label = switch (status) {
      ServerStatus.connected => l10n.statusConnected,
      ServerStatus.connecting => l10n.statusConnecting,
      ServerStatus.error => l10n.statusError,
      ServerStatus.idle => l10n.statusIdle,
    };
    final multi = sessionCount > 1;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
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
              color: theme.brightness == Brightness.dark
                  ? Color.lerp(color, Colors.white, 0.3)!
                  : Color.lerp(color, Colors.black, 0.2),
            ),
          ),
          if (multi) ...[
            const SizedBox(width: 3),
            Icon(
              Icons.expand_more_rounded,
              size: 12,
              color: theme.brightness == Brightness.dark
                  ? Color.lerp(color, Colors.white, 0.3)!
                  : Color.lerp(color, Colors.black, 0.2),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return pill;
    // Tooltip 与点击能力一起出现：胶囊长得不像按钮，悬停提示是唯一的
    // 可发现性线索（单会话点开的是会话日志，多会话点开的是会话菜单）。
    return Tooltip(
      message: tooltip ?? l10n.sessionLog,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: pill,
      ),
    );
  }
}
