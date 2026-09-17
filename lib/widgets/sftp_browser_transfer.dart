// 传输与状态区：底部状态栏与上传 / 下载队列面板。
part of 'sftp_browser.dart';

/// 底部状态栏：计数、总大小与选中项操作。
final class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller, required this.onError});

  final SftpBrowserController controller;
  final ValueChanged<Object> onError;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final selected = controller.selectedEntries;
    final entries = controller.entries;
    final style = TextStyle(fontSize: 11.5, color: theme.secondaryText);
    if (selected.isNotEmpty) {
      final files = [
        for (final entry in selected)
          if (!entry.isDirectory) entry,
      ];
      return Row(
        children: [
          Text(l10n.sftpSelectedCount(selected.length), style: style),
          const Spacer(),
          if (files.isNotEmpty)
            TextButton.icon(
              onPressed: () => _download(context, controller, files),
              icon: const Icon(Icons.download_rounded, size: 15),
              label: Text(l10n.sftpDownload),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          TextButton.icon(
            onPressed: () => _delete(context, controller, selected),
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 15,
              color: AppPalette.danger,
            ),
            label: Text(
              l10n.delete,
              style: const TextStyle(fontSize: 12, color: AppPalette.danger),
            ),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          IconButton(
            tooltip: l10n.cancel,
            icon: const Icon(Icons.close_rounded, size: 15),
            color: theme.secondaryText,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            onPressed: controller.clearSelection,
          ),
        ],
      );
    }
    final total = controller.totalBytes;
    return Row(
      children: [
        Text(l10n.sftpItemCount(entries.length), style: style),
        const SizedBox(width: 10),
        if (total > 0)
          Text(l10n.sftpTotalSize(formatSftpSize(total)), style: style),
        const Spacer(),
      ],
    );
  }
}

/// 传输队列面板：进度按行订阅，只有该行随进度重绘。
final class _TransferPanel extends StatelessWidget {
  const _TransferPanel({required this.queue});

  final SftpTransferQueue queue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final transfers = queue.transfers;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.panelBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 6, 0),
            child: Row(
              children: [
                Icon(
                  Icons.swap_vert_rounded,
                  size: 15,
                  color: theme.secondaryText,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.sftpTransfersTitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                if (queue.hasFinished)
                  TextButton(
                    onPressed: queue.clearFinished,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 11.5),
                    ),
                    child: Text(l10n.sftpClearFinished),
                  ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 132),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 6),
              itemCount: transfers.length,
              itemBuilder: (context, index) => RepaintBoundary(
                child: _TransferRow(transfer: transfers[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _TransferRow extends StatelessWidget {
  const _TransferRow({required this.transfer});

  final SftpTransfer transfer;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: transfer,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context);
        final theme = Theme.of(context);
        final upload = transfer.direction == SftpTransferDirection.upload;
        final color = switch (transfer.state) {
          SftpTransferState.done => AppPalette.success,
          SftpTransferState.failed => AppPalette.danger,
          SftpTransferState.canceled => AppPalette.idle,
          SftpTransferState.queued ||
          SftpTransferState.running => theme.colorScheme.primary,
        };
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    upload
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 14,
                    color: color,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      transfer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _statusText(l10n, transfer),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.secondaryText,
                    ),
                  ),
                  SizedBox(
                    width: 26,
                    child: transfer.isFinished
                        ? Icon(
                            switch (transfer.state) {
                              SftpTransferState.done => Icons.check_rounded,
                              SftpTransferState.failed =>
                                Icons.error_outline_rounded,
                              _ => Icons.block_rounded,
                            },
                            size: 15,
                            color: color,
                          )
                        : IconButton(
                            tooltip: l10n.cancel,
                            icon: const Icon(Icons.close_rounded, size: 15),
                            color: theme.secondaryText,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 22,
                              height: 22,
                            ),
                            onPressed: transfer.cancel,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: transfer.isFinished
                      ? (transfer.state == SftpTransferState.done ? 1 : null)
                      : transfer.progress,
                  color: color,
                  backgroundColor: theme.hairline,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _statusText(AppLocalizations l10n, SftpTransfer transfer) {
    switch (transfer.state) {
      case SftpTransferState.done:
        return l10n.sftpDone;
      case SftpTransferState.canceled:
        return l10n.sftpCanceled;
      case SftpTransferState.failed:
        return sftpErrorText(l10n, transfer.errorKind);
      case SftpTransferState.queued:
      case SftpTransferState.running:
        // 还在收尾（等当前数据块结束）：「已取消」会让人以为已经完事了。
        if (transfer.isCanceling) return l10n.sftpCanceling;
        final progress = transfer.progress;
        final parts = <String>[
          if (progress != null) '${(progress * 100).round()}%',
          if (transfer.state == SftpTransferState.running) ...[
            '${formatSftpSize(transfer.bytesPerSecond.round())}/s',
            if (transfer.remaining case final remaining?)
              l10n.sftpRemaining(formatSftpDuration(remaining)),
          ] else
            formatSftpSize(transfer.total),
        ];
        return parts.join(' · ');
    }
  }
}
