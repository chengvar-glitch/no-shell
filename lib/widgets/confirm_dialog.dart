/// 共用确认框与轻提示：桌面端与移动端同一观感、同一行为，
/// 各处不再自绘「取消 / 确认」和 SnackBar。
library;

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme.dart';

/// 确认框：取消（文字按钮）+ 确认（实心按钮）。
///
/// [destructive] 为 true（删除等危险操作）时确认键为红色实心，
/// 否则用主色实心（如覆盖确认）。返回 true 表示用户点了确认。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool destructive = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: AppPalette.danger)
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

/// 说明框：只有「完成」一个动作，用于用户需要**读完**的提示
/// （失败原因 + 替代做法），一闪而过的 [showToast] 承担不了。
Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  required String body,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext);
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.done),
          ),
        ],
      );
    },
  );
}

/// 轻提示：统一样式与排队行为（先收起当前一条再弹新的）。
void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
