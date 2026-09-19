import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme.dart';

/// Tab 未建立会话时的引导空态：图标 + 标题 + 提示，可选「重连」按钮。
/// SFTP Tab 与移动端终端 Tab 共用，保证同一详情页里各 Tab 的空态观感一致。
class SessionIdleView extends StatelessWidget {
  const SessionIdleView({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String hint;

  /// 失败 / 已结束时的重连动作；为空（从未连接过）时不显示按钮。
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: theme.secondaryText,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: Text(AppLocalizations.of(context).reconnect),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
