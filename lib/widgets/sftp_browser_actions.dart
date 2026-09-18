// 共享操作与工具函数：错误文案 / 图标 / 上传下载重命名删除等对话框流程。
part of 'sftp_browser.dart';

Widget _menuRow(IconData icon, String label, {Color? color}) {
  return Row(
    children: [
      Icon(icon, size: 16, color: color ?? AppPalette.idle),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(fontSize: 13, color: color)),
    ],
  );
}

/// 操作类错误文案：把分类结果翻成当前语言。
String _sftpErrorText(AppLocalizations l10n, Object? error) {
  final kind = error is SftpException
      ? error.kind
      : (error is SftpErrorKind ? error : SftpErrorKind.other);
  return switch (kind) {
    SftpErrorKind.permission => l10n.sftpErrorPermission,
    SftpErrorKind.notFound => l10n.sftpErrorNotFound,
    SftpErrorKind.unsupported => l10n.sftpErrorUnsupported,
    SftpErrorKind.network => l10n.sftpErrorNetwork,
    SftpErrorKind.busy => l10n.sftpErrorBusy,
    SftpErrorKind.other => l10n.sftpErrorOther,
  };
}

String _sortLabel(AppLocalizations l10n, SftpSortField field) =>
    switch (field) {
      SftpSortField.name => l10n.sftpSortName,
      SftpSortField.size => l10n.sftpSortSize,
      SftpSortField.modified => l10n.sftpSortModified,
    };

/// 目录 / 文件图标：按扩展名粗分，够用即可。
IconData _entryIcon(SftpEntry entry) {
  if (entry.isSymlink) return Icons.link_rounded;
  if (entry.isDirectory) return Icons.folder_rounded;
  final dot = entry.name.lastIndexOf('.');
  final extension = dot <= 0 ? '' : entry.name.substring(dot + 1).toLowerCase();
  return switch (extension) {
    'png' ||
    'jpg' ||
    'jpeg' ||
    'gif' ||
    'webp' ||
    'svg' ||
    'bmp' ||
    'ico' => Icons.image_outlined,
    'zip' ||
    'tar' ||
    'gz' ||
    'tgz' ||
    'bz2' ||
    'xz' ||
    '7z' ||
    'rar' => Icons.folder_zip_outlined,
    'dart' ||
    'js' ||
    'ts' ||
    'py' ||
    'go' ||
    'rs' ||
    'java' ||
    'rb' ||
    'php' ||
    'sh' ||
    'c' ||
    'h' ||
    'cpp' ||
    'html' ||
    'css' => Icons.code_rounded,
    'json' ||
    'yaml' ||
    'yml' ||
    'toml' ||
    'ini' ||
    'conf' ||
    'env' => Icons.settings_suggest_outlined,
    'log' || 'txt' || 'md' => Icons.article_outlined,
    'sql' || 'db' || 'sqlite' => Icons.storage_rounded,
    _ => Icons.insert_drive_file_outlined,
  };
}

RelativeRect _toRelativeRect(BuildContext context, Offset globalPosition) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  return RelativeRect.fromLTRB(
    globalPosition.dx,
    globalPosition.dy,
    overlay.size.width - globalPosition.dx,
    overlay.size.height - globalPosition.dy,
  );
}

/// 上传：先选本地文件，同名时整批确认覆盖。
Future<void> _upload(
  BuildContext context,
  SftpBrowserController controller,
) async {
  final l10n = AppLocalizations.of(context);
  final List<LocalUpload> sources;
  try {
    sources = await controller.pickUploads(l10n.sftpUpload);
  } on Object {
    if (!context.mounted) return;
    showToast(context, l10n.sftpPickerFailed);
    return;
  }
  if (sources.isEmpty || !context.mounted) return;
  final conflicts = controller.conflictsWith(sources);
  if (conflicts.isNotEmpty) {
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.sftpOverwriteTitle,
      body: l10n.sftpOverwriteBody(conflicts.length),
      confirmLabel: l10n.sftpOverwrite,
      destructive: false,
    );
    if (confirmed != true) return;
  }
  controller.startUpload(sources);
}

/// 下载：目录不支持，仅取其中的文件。
Future<void> _download(
  BuildContext context,
  SftpBrowserController controller,
  List<SftpEntry> targets,
) async {
  final files = [
    for (final entry in targets)
      if (!entry.isDirectory) entry,
  ];
  if (files.isEmpty) return;
  final l10n = AppLocalizations.of(context);
  final outcome = await controller.downloadEntries(files, l10n.save);
  if (!context.mounted) return;
  if (outcome == SftpDownloadOutcome.unavailable) {
    showToast(context, l10n.sftpTargetUnavailable);
  }
}

Future<void> _rename(
  BuildContext context,
  SftpBrowserController controller,
  SftpEntry entry,
) async {
  final l10n = AppLocalizations.of(context);
  final name = await _promptName(
    context,
    title: l10n.sftpRenameTitle(entry.name),
    fieldLabel: l10n.sftpColumnName,
    initial: entry.name,
    confirmLabel: l10n.save,
  );
  if (name == null) return;
  try {
    await controller.renameEntry(entry, name);
  } on Object catch (error) {
    if (!context.mounted) return;
    showToast(context, _sftpErrorText(l10n, error));
  }
}

Future<void> _createFolder(
  BuildContext context,
  SftpBrowserController controller,
) async {
  final l10n = AppLocalizations.of(context);
  final name = await _promptName(
    context,
    title: l10n.sftpNewFolderTitle,
    fieldLabel: l10n.sftpFolderNameField,
    initial: '',
    confirmLabel: l10n.save,
  );
  if (name == null) return;
  try {
    await controller.createFolder(name);
  } on Object catch (error) {
    if (!context.mounted) return;
    showToast(context, _sftpErrorText(l10n, error));
  }
}

Future<void> _delete(
  BuildContext context,
  SftpBrowserController controller,
  List<SftpEntry> targets,
) async {
  if (targets.isEmpty) return;
  final l10n = AppLocalizations.of(context);
  final hasFolder = targets.any((entry) => entry.isDirectory);
  final confirmed = await showConfirmDialog(
    context,
    title: targets.length == 1
        ? l10n.sftpDeleteTitle(targets.single.name)
        : l10n.sftpDeleteMultiTitle(targets.length),
    body: hasFolder ? l10n.sftpDeleteFolderBody : l10n.sftpDeleteFileBody,
    confirmLabel: l10n.delete,
  );
  if (confirmed != true) return;
  try {
    await controller.deleteEntries(targets);
  } on Object catch (error) {
    if (!context.mounted) return;
    showToast(context, _sftpErrorText(l10n, error));
  }
}

/// 名称输入对话框（新建目录 / 重命名共用），带同名与非法字符校验。
Future<String?> _promptName(
  BuildContext context, {
  required String title,
  required String fieldLabel,
  required String initial,
  required String confirmLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _NameDialog(
      title: title,
      fieldLabel: fieldLabel,
      initial: initial,
      confirmLabel: confirmLabel,
    ),
  );
}

final class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.fieldLabel,
    required this.initial,
    required this.confirmLabel,
  });

  final String title;
  final String fieldLabel;
  final String initial;
  final String confirmLabel;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _editor = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    final value = _editor.text.trim();
    if (value.isEmpty) {
      setState(() => _error = l10n.nameRequired);
      return;
    }
    if (!isValidEntryName(value)) {
      setState(() => _error = l10n.sftpNameInvalid);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: _editor,
          autofocus: true,
          decoration: InputDecoration(
            labelText: widget.fieldLabel,
            errorText: _error,
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
