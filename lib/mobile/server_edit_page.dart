import 'package:flutter/material.dart';

import '../host_portable.dart';
import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../ssh/credential_store.dart';
import '../ssh/ssh_credentials.dart';
import '../store.dart';
import '../widgets/group_controls.dart';

/// 移动端新建 / 编辑主机页（桌面端继续使用弹窗表单）。
class ServerEditPage extends StatefulWidget {
  const ServerEditPage({
    super.key,
    required this.store,
    required this.credentials,
    this.initial,
    this.initialGroup,
  });

  final ServerStore store;
  final CredentialStore credentials;

  /// 传入则为编辑，否则为新建。
  final SshServer? initial;

  /// 新建时预填的分组（分组头菜单的「在此分组新建连接」传进来）。
  final String? initialGroup;

  @override
  State<ServerEditPage> createState() => _ServerEditPageState();
}

class _ServerEditPageState extends State<ServerEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _metadata = TextEditingController();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _host = TextEditingController(text: widget.initial?.host);
  late final _port = TextEditingController(
    text: (widget.initial?.port ?? 22).toString(),
  );
  late final _username = TextEditingController(text: widget.initial?.username);
  late final _group = TextEditingController(
    text: widget.initial?.group ?? widget.initialGroup ?? '',
  );
  late final _notes = TextEditingController(text: widget.initial?.notes);
  late AuthMethod _auth = widget.initial?.authMethod ?? AuthMethod.privateKey;

  /// 粘贴的元数据里带的密码，保存时写进安全存储。
  String? _password;

  @override
  void dispose() {
    for (final controller in [
      _metadata,
      _name,
      _host,
      _port,
      _username,
      _group,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 把粘贴的元数据填进下方表单：只覆盖识别到的字段，用户仍可继续手动改。
  void _applyMetadata(String text) {
    final drafts = parseHostsText(
      text,
      defaultGroup: AppLocalizations.of(context).defaultGroupName,
    );
    if (drafts.isEmpty) return;
    final draft = drafts.first;
    setState(() {
      _name.text = draft.name;
      _host.text = draft.host;
      _port.text = draft.port.toString();
      _username.text = draft.username;
      _password = draft.password;
      // 元数据只承载密码认证；没写密码时保留手动选择的认证方式。
      if (draft.password != null) _auth = AuthMethod.password;
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    final group = _group.text.trim();
    final id =
        widget.initial?.id ?? 'srv-${DateTime.now().microsecondsSinceEpoch}';
    final password = _password;
    if (password != null &&
        _auth == AuthMethod.password &&
        widget.credentials.supported) {
      await widget.credentials.write(id, SshCredentials(password: password));
    }
    if (!mounted) return;
    widget.store.upsert(
      SshServer(
        id: id,
        group: group.isEmpty ? l10n.defaultGroupName : group,
        name: _name.text.trim(),
        host: _host.text.trim(),
        username: _username.text.trim(),
        port: int.parse(_port.text.trim()),
        authMethod: _auth,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        tags: widget.initial?.tags ?? const [],
        lastConnectedAt: widget.initial?.lastConnectedAt,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initial != null;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? l10n.editConnection : l10n.newConnection),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // 粘贴为主、手输兜底：两处输入共存，元数据只覆盖识别到的字段。
            TextField(
              controller: _metadata,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: l10n.pasteMetadata,
                hintText: l10n.pasteMetadataHint,
                alignLabelWithHint: true,
              ),
              onChanged: _applyMetadata,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _name,
              autofocus: !isEditing,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.fieldName,
                hintText: l10n.nameHint,
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? l10n.nameRequired : null,
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _host,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: l10n.fieldHost,
                      hintText: l10n.hostHint,
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? l10n.hostRequired
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _port,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: l10n.port),
                    validator: (v) {
                      final port = int.tryParse(v ?? '');
                      if (port == null || port < 1 || port > 65535) {
                        return l10n.portInvalid;
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _username,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.username,
                hintText: l10n.usernameHint,
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? l10n.usernameRequired : null,
            ),
            const SizedBox(height: 14),
            GroupField(controller: _group, groups: widget.store.groupNames),
            const SizedBox(height: 16),
            SegmentedButton<AuthMethod>(
              segments: [
                ButtonSegment(
                  value: AuthMethod.password,
                  label: Text(l10n.authPassword),
                  icon: const Icon(Icons.password_rounded, size: 16),
                ),
                ButtonSegment(
                  value: AuthMethod.privateKey,
                  label: Text(l10n.authKey),
                  icon: const Icon(Icons.vpn_key_outlined, size: 16),
                ),
              ],
              selected: {_auth},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _auth = selection.first),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.notesOptional,
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(l10n.save),
        ),
      ),
    );
  }
}
