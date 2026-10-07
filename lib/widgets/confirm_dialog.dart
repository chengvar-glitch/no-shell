/// 共用确认框与轻提示：桌面端与移动端同一观感、同一行为，
/// 各处不再自绘「取消 / 确认」和 SnackBar。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme.dart';

/// 应用内弹窗的唯一入口：遮罩不可点关，Esc 照常关。
///
/// 两件事必须一起管：Flutter 把「点遮罩关」与「Esc 关」挂在同一个开关上
/// （`ModalRoute._DismissModalAction.isEnabled` 读的就是 `barrierDismissible`），
/// 关掉遮罩误点等于顺手把 Esc 也关掉——用户按 Esc 没反应，只能去够按钮。
/// 这里把 Esc 补回来：它挂在弹窗内容外面那层 [FocusScope] 上，比框架那层
/// 更近，而输入框的 autofocus 仍然落得进去（scope 拿到焦点后会把焦点推给
/// 子树里申请自动聚焦的那个输入框）。
///
/// [escapeDismissible] 为 false 时不补 Esc——专给「等待遮罩」这类不允许
/// 中途取消的弹窗用。
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool escapeDismissible = true,
  bool useSafeArea = true,
  Color? barrierColor,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    useSafeArea: useSafeArea,
    barrierColor: barrierColor,
    builder: (dialogContext) {
      final content = builder(dialogContext);
      if (!escapeDismissible) return content;
      return FocusScope(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent ||
              event.logicalKey != LogicalKeyboardKey.escape) {
            return KeyEventResult.ignored;
          }
          Navigator.of(dialogContext).maybePop();
          return KeyEventResult.handled;
        },
        child: content,
      );
    },
  );
}

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
  final confirmed = await showAppDialog<bool>(
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
  return showAppDialog<void>(
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
