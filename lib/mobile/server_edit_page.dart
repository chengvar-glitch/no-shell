import 'package:flutter/material.dart';

import '../host_portable.dart';
import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../ssh/connect_flow.dart';
import '../ssh/credential_store.dart';
import '../ssh/ssh_agent.dart';
import '../ssh/ssh_credentials.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/group_controls.dart';
import '../widgets/jump_host_field.dart';
import '../widgets/confirm_dialog.dart';

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

  /// 选中的分组名；null 表示默认分组（没动过下拉就是它）。
  late String? _group = widget.initial?.group ?? widget.initialGroup;
  late final _notes = TextEditingController(text: widget.initial?.notes);
  late AuthMethod _auth = widget.initial?.authMethod ?? AuthMethod.privateKey;

  /// 跳板机选择：null 表示直连（不使用）。新建时默认直连。
  late String? _jumpServerId = widget.initial?.jumpServerId;

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
    // 分组下拉里只有已建好的分组，没动过就是默认分组。
    final group = _group ?? l10n.defaultGroupName;
    final id =
        widget.initial?.id ?? 'srv-${DateTime.now().microsecondsSinceEpoch}';
    final password = _password;
    if (password != null &&
        _auth == AuthMethod.password &&
        widget.credentials.supported) {
      final saved = await widget.credentials.write(
        id,
        SshCredentials(password: password),
      );
      if (!saved && mounted) {
        showToast(context, l10n.credentialsSaveFailedMsg);
      }
    } else if (_auth != AuthMethod.password &&
        widget.initial?.authMethod == AuthMethod.password) {
      // 改成密钥认证后旧密码没人再用，但导出备份时会把它一起打包走。
      await dropStoredCredential(widget.credentials, id);
    }
    if (!mounted) return;
    widget.store.upsert(
      SshServer(
        id: id,
        group: group,
        name: _name.text.trim(),
        host: _host.text.trim(),
        username: _username.text.trim(),
        port: int.parse(_port.text.trim()),
        authMethod: _auth,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        tags: widget.initial?.tags ?? const [],
        lastConnectedAt: widget.initial?.lastConnectedAt,
        // 这里是从零构造（不是 copyWith），jumpServerId 传 null 即等价于清除跳板机。
        jumpServerId: _jumpServerId,
        // 转发规则不归本表单管（在详情页的转发 Tab 里编辑），原样带走；
        // 漏掉这一行等于每次保存都把该主机的规则清空。
        forwards: widget.initial?.forwards ?? const [],
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
            GroupField(
              value: _group ?? l10n.defaultGroupName,
              groups: widget.store.groupNames,
              onChanged: (name) => setState(() => _group = name),
            ),
            const SizedBox(height: 14),
            JumpHostField(
              servers: widget.store.servers,
              self: widget.initial,
              value: _jumpServerId,
              onChanged: (value) => setState(() => _jumpServerId = value),
            ),
            const SizedBox(height: 14),
            // 分组 / 跳板机都有自带标签，认证方式补一个同级小标题，
            // 三选一的语义一眼可读；按钮组与输入框同宽，不按内容居中。
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                l10n.authMethod,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).secondaryText,
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<AuthMethod>(
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
                  // 本平台没有 agent 时不给这个入口；主机预设就是 Agent 时
                  // 仍要展示，否则保存的取值在界面上无从呈现。
                  if (sshAgentSupported || _auth == AuthMethod.agent)
                    ButtonSegment(
                      value: AuthMethod.agent,
                      label: Text(l10n.authAgent),
                      icon: const Icon(Icons.extension_outlined, size: 16),
                    ),
                ],
                selected: {_auth},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    setState(() => _auth = selection.first),
              ),
            ),
            if (_auth == AuthMethod.agent) ...[
              const SizedBox(height: 8),
              Text(
                l10n.agentAuthHint,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).secondaryText,
                ),
              ),
            ],
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
