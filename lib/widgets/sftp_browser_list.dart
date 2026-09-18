// 文件列表区：表头 / 排序热区 / 单行条目与右键菜单，及加载、错误、空态。
part of 'sftp_browser.dart';

/// 列表主体：加载 / 错误 / 空 / 表格四种形态。
final class _Body extends StatelessWidget {
  const _Body({required this.controller, required this.compact});

  final SftpBrowserController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (controller.isLoading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }
    final error = controller.error;
    if (error != null) {
      return _ErrorState(
        message: _sftpErrorText(l10n, error),
        onRetry: () => unawaited(controller.refresh()),
      );
    }
    final entries = controller.entries;
    if (entries.isEmpty) {
      final filtered = controller.query.trim().isNotEmpty;
      return _EmptyState(
        icon: filtered ? Icons.search_off_rounded : Icons.folder_open_rounded,
        title: filtered ? l10n.sftpNoMatches : l10n.sftpFolderEmpty,
        hint: filtered ? null : l10n.sftpFolderEmptyHint,
      );
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.panelBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.hairline),
      ),
      child: Column(
        children: [
          if (!compact) _ListHeader(controller: controller),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(vertical: compact ? 2 : 0),
              itemCount: entries.length,
              itemExtent: compact ? 44 : 34,
              itemBuilder: (context, index) => _EntryRow(
                controller: controller,
                index: index,
                compact: compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 32,
            color: AppPalette.danger,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text(l10n.sftpRetry),
          ),
        ],
      ),
    );
  }
}

final class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, this.hint});

  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: theme.secondaryText),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(
              hint!,
              style: TextStyle(fontSize: 12, color: theme.secondaryText),
            ),
          ],
        ],
      ),
    );
  }
}

final class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.controller});

  final SftpBrowserController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final style = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: theme.secondaryText,
    );
    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: 34, right: 30),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SortArea(
              controller: controller,
              field: SftpSortField.name,
              child: Text(l10n.sftpColumnName, style: style),
            ),
          ),
          SizedBox(
            width: _kSizeWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: _SortHeaderLabel(
                controller: controller,
                field: SftpSortField.size,
                label: l10n.sftpColumnSize,
                style: style,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: _kTimeWidth,
            child: _SortHeaderLabel(
              controller: controller,
              field: SftpSortField.modified,
              label: l10n.sftpColumnModified,
              style: style,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: _kModeWidth,
            child: Text(l10n.sftpColumnPermissions, style: style),
          ),
        ],
      ),
    );
  }
}

/// 名称列表头：整格都是排序热区。
final class _SortArea extends StatelessWidget {
  const _SortArea({
    required this.controller,
    required this.field,
    required this.child,
  });

  final SftpBrowserController controller;
  final SftpSortField field;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.toggleSort(field),
      child: MouseRegion(cursor: SystemMouseCursors.click, child: child),
    );
  }
}

final class _SortHeaderLabel extends StatelessWidget {
  const _SortHeaderLabel({
    required this.controller,
    required this.field,
    required this.label,
    required this.style,
  });

  final SftpBrowserController controller;
  final SftpSortField field;
  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = controller.sortField == field;
    return GestureDetector(
      onTap: () => controller.toggleSort(field),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            if (active)
              Icon(
                controller.sortAscending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 12,
                color: theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}

const _kSizeWidth = 74.0;
const _kTimeWidth = 96.0;
const _kModeWidth = 88.0;

/// 单行文件条目：自管 hover 状态，避免鼠标移入移出重建整个列表。
final class _EntryRow extends StatefulWidget {
  const _EntryRow({
    required this.controller,
    required this.index,
    required this.compact,
  });

  final SftpBrowserController controller;
  final int index;
  final bool compact;

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<_EntryRow> {
  bool _hovered = false;

  SftpBrowserController get _controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final entry = _controller.entries[widget.index];
    final theme = Theme.of(context);
    final selected = _controller.isSelected(entry.path);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // 选中走原始指针事件：双击手势会让竞技场等到 100ms 超时才裁决，
      // 而文件列表里单击极其频繁，走 Listener 才能做到点哪选哪。
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons != kPrimaryButton) return;
          _onPrimaryDown(entry);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: () => _onActivate(entry),
          onSecondaryTapDown: (details) => _showMenu(
            context,
            _toRelativeRect(context, details.globalPosition),
            entry,
          ),
          onLongPressStart: (details) => _showMenu(
            context,
            _toRelativeRect(context, details.globalPosition),
            entry,
            select: true,
          ),
          child: Container(
            padding: const EdgeInsets.only(left: 10, right: 4),
            color: selected
                ? theme.selectedOverlay
                : (_hovered ? theme.hoverOverlay : null),
            child: Row(
              children: [
                Icon(
                  _entryIcon(entry),
                  size: 17,
                  color: entry.isDirectory
                      ? theme.colorScheme.primary
                      : theme.secondaryText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: entry.isDirectory
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (entry.isSymlink) ...[
                        const SizedBox(width: 5),
                        Icon(
                          Icons.link_rounded,
                          size: 12,
                          color: theme.secondaryText,
                        ),
                      ],
                    ],
                  ),
                ),
                if (!widget.compact) ...[
                  SizedBox(
                    width: _kSizeWidth,
                    child: Text(
                      entry.isDirectory ? '—' : formatSftpSize(entry.size),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.secondaryText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: _kTimeWidth,
                    child: Text(
                      entry.modifiedAt == null
                          ? '—'
                          : formatRelativeTime(
                              AppLocalizations.of(context),
                              entry.modifiedAt,
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.secondaryText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: _kModeWidth,
                    child: Text(
                      entry.permissions ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: theme.secondaryText.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
                SizedBox(
                  width: 26,
                  child: (_hovered || selected)
                      ? IconButton(
                          tooltip: AppLocalizations.of(context).moreActions,
                          icon: const Icon(Icons.more_horiz_rounded, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 24,
                            height: 24,
                          ),
                          color: theme.secondaryText,
                          onPressed: () => _showMenuFromButton(context, entry),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onPrimaryDown(SftpEntry entry) {
    // 移动端单击目录即进入；文件则用于多选（批量下载）。
    if (widget.compact) {
      if (entry.isDirectory) {
        unawaited(_controller.navigate(entry.path));
      } else {
        _controller.toggleSelection(entry.path);
      }
      return;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed) {
      _controller.selectTo(entry.path, additive: keyboard.isMetaPressed);
    } else {
      _controller.select(entry.path, additive: keyboard.isMetaPressed);
    }
  }

  /// 桌面端双击：目录进入，文件直接下载。
  void _onActivate(SftpEntry entry) {
    if (entry.isDirectory) {
      unawaited(_controller.navigate(entry.path));
    } else {
      unawaited(_download(context, _controller, [entry]));
    }
  }

  void _showMenuFromButton(BuildContext context, SftpEntry entry) {
    final box = context.findRenderObject()! as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero);
    _showMenu(
      context,
      RelativeRect.fromLTRB(
        topLeft.dx + box.size.width,
        topLeft.dy + box.size.height,
        0,
        0,
      ),
      entry,
    );
  }

  Future<void> _showMenu(
    BuildContext context,
    RelativeRect position,
    SftpEntry entry, {
    bool select = false,
  }) async {
    if (select) _controller.select(entry.path);
    final l10n = AppLocalizations.of(context);
    final action = await showMenu<String>(
      context: context,
      position: position,
      items: [
        if (!entry.isDirectory)
          PopupMenuItem(
            value: 'download',
            height: 38,
            child: _menuRow(Icons.download_rounded, l10n.sftpDownload),
          ),
        PopupMenuItem(
          value: 'rename',
          height: 38,
          child: _menuRow(Icons.drive_file_rename_outline, l10n.sftpRename),
        ),
        PopupMenuItem(
          value: 'copy',
          height: 38,
          child: _menuRow(Icons.content_copy_rounded, l10n.sftpCopyPath),
        ),
        PopupMenuItem(
          value: 'delete',
          height: 38,
          child: _menuRow(
            Icons.delete_outline_rounded,
            l10n.delete,
            color: AppPalette.danger,
          ),
        ),
      ],
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'download':
        await _download(context, _controller, [entry]);
      case 'rename':
        await _rename(context, _controller, entry);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: entry.path));
        if (!context.mounted) return;
        showToast(context, l10n.copied(entry.path));
      case 'delete':
        await _delete(context, _controller, [entry]);
    }
  }
}
