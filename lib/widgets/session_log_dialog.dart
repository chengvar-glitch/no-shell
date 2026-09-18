/// 会话日志查看器：桌面弹窗，移动端同样以弹窗呈现（内容可全屏滚动）。
/// 入口是主机详情头部 / 全屏终端页标题旁的状态胶囊——点连接状态打开。
/// 查看的是终端画面（含回滚）的纯文本快照，复制与保存都出自同一份。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';
import '../settings.dart';
import '../theme.dart';
import 'confirm_dialog.dart';
import '../ssh/local_files.dart';
import '../ssh/terminal_session.dart';

/// 打开会话日志弹窗：展示画面快照全文，支持复制与另存为 `.log` 文件。
/// 保存走 [LocalFileGateway]（桌面「另存为」，移动端写临时目录后交分享面板）。
Future<void> showSessionLogDialog(
  BuildContext context, {
  required TerminalSession session,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _SessionLogDialog(session: session),
  );
}

/// 会话日志弹窗：打开时取一份终端缓冲区的快照，正文按行虚拟化渲染。
///
/// 快照只取一次：弹窗不会因为主题动画 / 重建而重读整份缓冲区，读到的内容
/// 也不会在用户眼前变来变去。正文交给 `ListView.builder` 逐行懒构建——
/// 回滚上限五万行，整段塞进单个 `Text` 会让开窗时主线程停几百毫秒
/// （实测两万行约 180ms，且每次重建重来一遍）。
final class _SessionLogDialog extends StatefulWidget {
  const _SessionLogDialog({required this.session});

  final TerminalSession session;

  @override
  State<_SessionLogDialog> createState() => _SessionLogDialogState();
}

class _SessionLogDialogState extends State<_SessionLogDialog> {
  late final List<String> _lines = widget.session.sessionLog.lines;

  /// 复制 / 保存用的整段文本，同样取自这份快照。
  late final String _text = _lines.join('\n');

  Future<void> _copy(BuildContext context) async {
    Clipboard.setData(ClipboardData(text: _text));
    showToast(context, AppLocalizations.of(context).sessionLogCopied);
  }

  Future<void> _save(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final localFiles = widget.session.localFiles;
    final destination = await localFiles.pickExportDestination(
      suggestedFileName(widget.session.server.name),
      confirmLabel: l10n.sessionLogSave,
    );
    if (destination == null || !context.mounted) return;
    try {
      final handle = localFiles.openWrite(destination.path, ownerOnly: true);
      handle.add(utf8.encode(_text));
      await handle.close();
    } on Object {
      await localFiles.discard(destination.path);
      if (!context.mounted) return;
      showToast(context, l10n.sessionLogSaveFailed);
      return;
    }
    if (destination.share) {
      await localFiles.shareLocalFile(
        destination.path,
        title: destination.name,
      );
    }
    if (!context.mounted) return;
    showToast(context, l10n.sessionLogSaved(destination.name));
  }

  /// 日志文件名：主机名只保留文件系统安全字符，再带上导出时刻。
  static String suggestedFileName(String serverName) {
    final safe = serverName.replaceAll(RegExp(r'[^\w.-]'), '-');
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return 'noshell-$safe-$stamp.log';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 画面快照：读的是终端缓冲区，不是另存的原始流，所以不会有控制序列。
    final empty = _lines.isEmpty;
    return AlertDialog(
      title: Text(l10n.sessionLog),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.sessionLogHint,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Theme.of(context).secondaryText,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(child: _LogBody(lines: _lines)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: empty ? null : () => _copy(context),
          child: Text(l10n.copy),
        ),
        OutlinedButton.icon(
          onPressed: empty ? null : () => _save(context),
          icon: const Icon(Icons.save_outlined, size: 16),
          label: Text(l10n.sessionLogSave),
        ),
      ],
    );
  }
}

/// 日志正文：终端同款等宽字体，可选中、可滚动；空日志给占位说明。
final class _LogBody extends StatelessWidget {
  const _LogBody({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).sessionLogEmpty,
          style: TextStyle(
            fontSize: 12.5,
            color: Theme.of(context).secondaryText,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    // 字体与字号跟终端偏好走：日志内容与终端画面同源，观感也应一致。
    final prefs = TerminalStyleScope.of(context).notifier.value;
    final logStyle = TextStyle(
      fontSize: (prefs.fontSize - 1).clamp(9, 20).toDouble(),
      height: 1.45,
      color: prefs.theme.foreground,
      fontFamily: prefs.resolvedFontFamily,
      fontFamilyFallback: prefs.fontFallback,
    );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: prefs.theme.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).hairline),
      ),
      child: SelectionArea(
        // 逐行懒构建：几万行回滚也只排版视口内的那几十行。
        child: ListView.builder(
          itemCount: lines.length,
          itemBuilder: (context, index) => Text(lines[index], style: logStyle),
        ),
      ),
    );
  }
}
