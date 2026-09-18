import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../ssh/credential_store.dart';
import '../store.dart';
import '../widgets/host_form.dart';

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
  late final _form = HostFormController(
    initial: widget.initial,
    initialGroup: widget.initialGroup,
  );

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final saved = await _form.build(
      context: context,
      credentials: widget.credentials,
    );
    if (saved == null || !mounted) return;
    widget.store.upsert(saved);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_form.isEditing ? l10n.editConnection : l10n.newConnection),
      ),
      body: Form(
        key: _form.formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            HostFormFields(
              controller: _form,
              groups: widget.store.groupNames,
              servers: widget.store.servers,
              density: HostFormDensity.mobile,
              onChanged: () => setState(() {}),
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
