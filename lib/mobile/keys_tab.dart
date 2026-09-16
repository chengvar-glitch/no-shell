import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme.dart';

/// 密钥 Tab：占位页，密钥管理（生成 / 导入 Ed25519 / RSA）在后续阶段接入。
class KeysTab extends StatelessWidget {
  const KeysTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navKeys)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.key_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(l10n.keysComingSoon, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              l10n.keysComingSoonHint,
              style: TextStyle(fontSize: 12.5, color: theme.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}
