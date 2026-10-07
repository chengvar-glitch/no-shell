/// 慢动作的等待遮罩：scrypt 派生（生产参数一次约 0.35 秒）与逐条读写安全存储
/// 都发生在口令弹窗关掉之后、结果提示出现之前。没有遮罩时这段空窗看起来就是
/// 「点了没反应」，用户会转头再点一次菜单——导出因此被触发两次。
///
/// 两条纪律：
/// - 出现前先等 [kBusyShowDelay]，本机瞬时完成的动作不该闪一下遮罩；
/// - 遮罩不可取消（`barrierDismissible: false` + [PopScope]）：它护的就是这段
///   窗口，点掉它只会让用户以为动作被取消了，而动作还在跑。
///
/// 测试注意：遮罩一现身就是不停转的 [CircularProgressIndicator]，`pumpAndSettle`
/// 会一路推到超时——要把它推出来只能按固定步长 `pump`，且别让它在无谓的用例里
/// 现身（动作都在微任务里做完时，定时器已被取消，不会闪）。
library;

import 'confirm_dialog.dart';

import 'dart:async';

import 'package:flutter/material.dart';

/// 遮罩现身前先等这么久；快于此的动作不闪遮罩。
const kBusyShowDelay = Duration(milliseconds: 200);

/// 跑 [run]；慢的话中间盖一层写着 [message] 的等待遮罩，跑完（含抛错）收走。
///
/// [run] 里不许再开自己的路由（遮罩弹在栈顶，收尾靠弹走栈顶那一个）：要选
/// 文件、要输口令的步骤留在遮罩外面。
Future<T> runWithBusyOverlay<T>(
  BuildContext context, {
  required String message,
  required Future<T> Function() run,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  var shown = false;
  final delayed = Timer(kBusyShowDelay, () {
    if (!context.mounted) return;
    shown = true;
    unawaited(
      showAppDialog<void>(
        context: context,
        escapeDismissible: false,
        builder: (_) => _BusyDialog(message: message),
      ),
    );
  });
  try {
    return await run();
  } finally {
    delayed.cancel();
    if (shown) navigator.pop();
  }
}

/// 转圈 + 一句话。进出场用 [Dialog] 自带的淡入缩放，不另写过渡动画。
class _BusyDialog extends StatelessWidget {
  const _BusyDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 28, 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              const SizedBox(width: 18),
              Flexible(
                child: Text(message, style: const TextStyle(fontSize: 13.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
