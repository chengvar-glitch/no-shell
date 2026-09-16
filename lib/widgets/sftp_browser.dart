import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../ssh/local_files.dart';
import '../ssh/sftp.dart';
import '../ssh/sftp_browser.dart';
import '../ssh/sftp_transfer.dart';
import '../ssh/terminal_session.dart';
import '../theme.dart';

part 'sftp_browser_actions.dart';
part 'sftp_browser_list.dart';
part 'sftp_browser_toolbar.dart';
part 'sftp_browser_transfer.dart';

/// SFTP 面板：路径栏 + 文件列表 + 传输队列 + 状态栏。
/// 桌面端详情面板与移动端详情页共用，窄屏自动收起为紧凑工具条。
/// 拆分约定：本文件是库入口，组件按区域放在同目录的 part 文件中，
/// 私有类仍限定在库内，外部只可见 [SftpTab]。
final class SftpTab extends StatefulWidget {
  const SftpTab({super.key, this.session, this.onRetry, this.idleHint});

  /// 当前主机的 SSH 会话；为空或未连接时展示引导画面。
  final TerminalSession? session;

  /// 失败 / 已结束时的重连动作。
  final VoidCallback? onRetry;

  /// 未连接时的提示文案，桌面端与移动端措辞不同。
  final String? idleHint;

  @override
  State<SftpTab> createState() => _SftpTabState();
}

class _SftpTabState extends State<SftpTab> {
  SftpBrowserController? _controller;

  /// 当前订阅的会话：阶段变化（连接就绪）时补开通道。
  TerminalSession? _session;

  /// 面板的重建来源：控制器 + 传输队列。
  Listenable? _source;

  bool _filterOpen = false;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(SftpTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      _attach();
      // 会话换了但可见性没变，didChangeDependencies 不会再触发：补一次。
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureReadyIfVisible(),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 桌面端三个 Tab 常驻在树里保活，挂载时并不代表用户要看 SFTP；
    // 这里用 Visibility.of 订阅可见性，真正切到 SFTP 的那一刻才开通道。
    _ensureReadyIfVisible();
  }

  /// 首次进入 SFTP Tab 才真正打开通道。
  /// 挂载即连接会在 SSH 刚连上时抢跑一条 SFTP 连接：既抢带宽，也容易赶在
  /// 连接就绪前失败，让面板只剩一个错误状态、像要重连一次。
  void _ensureReadyIfVisible() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    if (!Visibility.of(context)) return;
    unawaited(controller.ensureReady());
  }

  /// 连接就绪后补开一次：用户可能还没连上就先点开了 SFTP Tab，
  /// 那次 `ensureReady` 只会在连接建立前失败，等阶段变成 connected 再开一次。
  void _onSessionChanged() {
    if (_session?.phase != TerminalPhase.connected) return;
    _ensureReadyIfVisible();
  }

  @override
  void dispose() {
    _session?.removeListener(_onSessionChanged);
    _controller?.transfers.onTransferFinished = null;
    super.dispose();
  }

  /// 会话驱动：控制器由会话持有，面板只订阅与转发回调。
  void _attach() {
    final previous = _controller;
    final session = widget.session;
    if (!identical(_session, session)) {
      _session?.removeListener(_onSessionChanged);
      _session = session;
      session?.addListener(_onSessionChanged);
    }
    if (previous != null && previous != session?.sftp) {
      previous.transfers.onTransferFinished = null;
    }
    final controller = session?.sftp;
    _controller = controller;
    // 面板订阅控制器 + 传输队列：队列只在任务入队 / 结束 / 清空时才通知，
    // 传输进度走每行自己的 ListenableBuilder，不会带着列表一起重绘。
    _source = controller == null
        ? null
        : Listenable.merge([controller, controller.transfers]);
    if (controller == null) return;
    controller.transfers.onTransferFinished = _announceTransfer;
  }

  void _announceTransfer(SftpTransfer transfer) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final message = switch (transfer.state) {
      SftpTransferState.done =>
        transfer.direction == SftpTransferDirection.upload
            ? l10n.sftpUploaded(transfer.name)
            : l10n.sftpDownloaded(transfer.name),
      SftpTransferState.failed =>
        transfer.direction == SftpTransferDirection.upload
            ? l10n.sftpUploadFailed(transfer.name)
            : l10n.sftpDownloadFailed(transfer.name),
      SftpTransferState.canceled => l10n.sftpTransferCanceledMsg(transfer.name),
      SftpTransferState.queued || SftpTransferState.running => null,
    };
    if (message == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final idleHint = widget.idleHint ?? '';
    if (session == null || !session.isActive) {
      return _IdleState(
        title: AppLocalizations.of(context).sftp,
        hint: idleHint,
        onRetry: widget.onRetry,
      );
    }
    final controller = _controller;
    final source = _source;
    if (controller == null || source == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: source,
      builder: (context, _) => _Browser(
        controller: controller,
        filterOpen: _filterOpen,
        onToggleFilter: () => setState(() => _filterOpen = !_filterOpen),
        onError: _showError,
      ),
    );
  }

  void _showError(Object error) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(sftpErrorText(l10n, error))));
  }
}

/// 未建立会话时的引导画面。
final class _IdleState extends StatelessWidget {
  const _IdleState({required this.title, required this.hint, this.onRetry});

  final String title;
  final String hint;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_rounded,
              size: 34,
              color: theme.colorScheme.primary,
            ),
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
                label: Text(l10n.reconnect),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 已连接状态下的浏览界面。
final class _Browser extends StatelessWidget {
  const _Browser({
    required this.controller,
    required this.filterOpen,
    required this.onToggleFilter,
    required this.onError,
  });

  final SftpBrowserController controller;
  final bool filterOpen;
  final VoidCallback onToggleFilter;
  final ValueChanged<Object> onError;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 12,
            8,
            compact ? 8 : 12,
            8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Toolbar(
                controller: controller,
                compact: compact,
                filterOpen: filterOpen,
                onToggleFilter: onToggleFilter,
                onError: onError,
              ),
              if (filterOpen || controller.query.isNotEmpty) ...[
                const SizedBox(height: 6),
                _FilterField(controller: controller, compact: compact),
              ],
              const SizedBox(height: 6),
              if (controller.isRefreshing)
                const LinearProgressIndicator(minHeight: 2)
              else
                const SizedBox(height: 2),
              const SizedBox(height: 4),
              Expanded(
                child: RepaintBoundary(
                  child: _Body(controller: controller, compact: compact),
                ),
              ),
              if (controller.transfers.transfers.isNotEmpty) ...[
                const SizedBox(height: 8),
                RepaintBoundary(
                  child: _TransferPanel(queue: controller.transfers),
                ),
              ],
              const SizedBox(height: 6),
              _StatusBar(controller: controller, onError: onError),
            ],
          ),
        );
      },
    );
  }
}
