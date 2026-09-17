/// 备份口令弹窗：导出时设口令（两次输入确认），导入时输入口令。
/// 桌面端与移动端共用同一套，两端观感必须一致。
library;

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';

/// 弹窗的两种用途：新建备份要确认口令，打开备份只要输一次。
enum BackupPasswordMode { create, open }

/// 弹出备份口令输入框；确认返回口令，取消返回 null。
Future<String?> showBackupPasswordDialog(
  BuildContext context, {
  required BackupPasswordMode mode,
}) => showDialog<String>(
  context: context,
  builder: (_) => _BackupPasswordDialog(mode: mode),
);

class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog({required this.mode});

  final BackupPasswordMode mode;

  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool get _needsConfirm => widget.mode == BackupPasswordMode.create;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final creating = _needsConfirm;
    return AlertDialog(
      title: Text(creating ? l10n.backupCreateTitle : l10n.backupOpenTitle),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                creating ? l10n.backupCreateHint : l10n.backupOpenHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                autofocus: true,
                obscureText: true,
                style: const TextStyle(fontSize: 13.5),
                textInputAction: creating
                    ? TextInputAction.next
                    : TextInputAction.done,
                decoration: InputDecoration(labelText: l10n.backupPassword),
                validator: (value) =>
                    (value ?? '').isEmpty ? l10n.backupPasswordRequired : null,
                onFieldSubmitted: (_) {
                  if (!creating) _submit();
                },
              ),
              if (creating) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirm,
                  obscureText: true,
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    labelText: l10n.backupPasswordConfirm,
                  ),
                  validator: (value) => value == _password.text
                      ? null
                      : l10n.backupPasswordMismatch,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.backupPasswordWarning,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(
            creating ? l10n.backupCreateConfirm : l10n.backupOpenConfirm,
          ),
        ),
      ],
    );
  }
}
