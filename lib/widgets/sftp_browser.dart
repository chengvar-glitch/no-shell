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
import 'confirm_dialog.dart';
import 'session_idle_view.dart';

part 'sftp_browser_actions.dart';
part 'sftp_browser_list.dart';
part 'sftp_browser_toolbar.dart';
part 'sftp_browser_transfer.dart';

/// SFTP 面板：路径栏 + 文件列表 + 传输队列 + 状态栏。
/// 桌面端详情面板与移动端详情页共用，窄屏自动收起为紧凑工具条。
/// 拆分约定：本文件是库入口，组件按区域放在同目录的 part 文件中，
/// 库内符号一律私有（下划线开头），外部只可见 [SftpTab]。
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
    showToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final idleHint = widget.idleHint ?? '';
    if (session == null || !session.isActive) {
      return SessionIdleView(
        icon: Icons.folder_open_rounded,
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
    showToast(context, _sftpErrorText(l10n, error));
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
              // 刷新细进度条是不定动画、每帧都要重绘，包一层边界免得整块
              // 详情面板（含被保活的终端区域）跟着逐帧重画。
              if (controller.isRefreshing)
                const RepaintBoundary(
                  child: LinearProgressIndicator(minHeight: 2),
                )
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
