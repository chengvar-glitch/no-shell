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
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final ServerStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.statusColor(status);
    final label = switch (status) {
      ServerStatus.connected => AppLocalizations.of(context).statusConnected,
      ServerStatus.connecting => AppLocalizations.of(context).statusConnecting,
      ServerStatus.error => AppLocalizations.of(context).statusError,
      ServerStatus.idle => AppLocalizations.of(context).statusIdle,
    };
    return Container(
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
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.brightness == Brightness.dark
                  ? Color.lerp(color, Colors.white, 0.3)!
                  : Color.lerp(color, Colors.black, 0.2),
            ),
          ),
        ],
      ),
    );
  }
}
