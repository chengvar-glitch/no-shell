/// 命令片段的共用界面：列表弹窗（点按发送、行内编辑 / 删除）与编辑表单。
/// 桌面端与移动端同一套；发送动作只在会话已连接时可用。
library;

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../snippets.dart';
import '../ssh/terminal_session.dart';
import '../theme.dart';
import 'confirm_dialog.dart';

/// 打开片段列表弹窗。[session] 非空且已连接时点按片段即发送执行；
/// 为空（或未连接）时弹窗退化为纯管理界面。
Future<void> showSnippetDialog(
  BuildContext context, {
  required SnippetStore snippets,
  TerminalSession? session,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _SnippetListDialog(snippets: snippets, session: session),
  );
}

final class _SnippetListDialog extends StatelessWidget {
  const _SnippetListDialog({required this.snippets, this.session});

  final SnippetStore snippets;
  final TerminalSession? session;

  bool get _canSend =>
      session != null && session!.phase == TerminalPhase.connected;

  void _send(CommandSnippet snippet) {
    // 末尾补一个回车：片段大多是完整命令，发送即执行。
    session!.sendText('${snippet.command}\r');
  }

  Future<void> _edit(BuildContext context, [CommandSnippet? initial]) {
    return _showSnippetEditorDialog(
      context,
      snippets: snippets,
      initial: initial,
    );
  }

  Future<void> _delete(BuildContext context, CommandSnippet snippet) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.snippetDeleteTitle(snippet.name),
      body: l10n.snippetDeleteBody,
      confirmLabel: l10n.delete,
    );
    if (!confirmed) return;
    snippets.remove(snippet.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.snippets),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_canSend)
              Text(
                l10n.snippetsHint,
                style: TextStyle(fontSize: 12, color: theme.secondaryText),
              ),
            Flexible(
              child: ListenableBuilder(
                listenable: snippets,
                builder: (context, _) {
                  final all = snippets.snippets;
                  if (all.isEmpty) return _empty(context);
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 380),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: all.length,
                      itemBuilder: (context, index) {
                        final snippet = all[index];
                        return ListTile(
                          enabled: _canSend,
                          dense: true,
                          title: Text(
                            snippet.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            snippet.command,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                          onTap: () {
                            _send(snippet);
                            Navigator.of(context).pop();
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: l10n.snippetEdit,
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.edit_outlined, size: 17),
                                onPressed: () => _edit(context, snippet),
                              ),
                              IconButton(
                                tooltip: l10n.delete,
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 17,
                                ),
                                onPressed: () => _delete(context, snippet),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton.tonalIcon(
          onPressed: () => _edit(context),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: Text(l10n.snippetNew),
        ),
      ],
    );
  }

  Widget _empty(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Icon(Icons.code_rounded, size: 40, color: theme.colorScheme.outline),
          const SizedBox(height: 10),
          Text(l10n.snippetEmpty, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            l10n.snippetEmptyHint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: theme.secondaryText),
          ),
        ],
      ),
    );
  }
}

/// 片段编辑表单：新建与编辑共用；保存即 upsert 进注册表并落盘。
Future<void> _showSnippetEditorDialog(
  BuildContext context, {
  required SnippetStore snippets,
  CommandSnippet? initial,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) =>
        _SnippetEditorDialog(snippets: snippets, initial: initial),
  );
}

final class _SnippetEditorDialog extends StatefulWidget {
  const _SnippetEditorDialog({required this.snippets, this.initial});

  final SnippetStore snippets;
  final CommandSnippet? initial;

  @override
  State<_SnippetEditorDialog> createState() => _SnippetEditorDialogState();
}

final class _SnippetEditorDialogState extends State<_SnippetEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _command = TextEditingController(text: widget.initial?.command);

  @override
  void dispose() {
    _name.dispose();
    _command.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final initial = widget.initial;
    final snippets = widget.snippets;
    final snippet = initial == null
        ? CommandSnippet(
            id: snippets.newId(),
            name: _name.text.trim(),
            command: _command.text.trim(),
          )
        : initial.copyWith(
            name: _name.text.trim(),
            command: _command.text.trim(),
          );
    snippets.upsert(snippet);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.initial == null ? l10n.snippetNew : l10n.snippetEdit),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: widget.initial == null,
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(
                  labelText: l10n.snippetName,
                  hintText: l10n.nameHint,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? l10n.snippetNameRequired
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _command,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  labelText: l10n.snippetCommand,
                  helperText: l10n.snippetCommandHint,
                  alignLabelWithHint: true,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? l10n.snippetCommandRequired
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.save)),
      ],
    );
  }
}
