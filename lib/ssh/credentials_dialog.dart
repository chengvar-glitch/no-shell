import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../theme.dart';
import 'ssh_agent.dart';
import 'ssh_credentials.dart';

/// 一次凭据弹窗的提交结果：[remember] 表示用户愿意把凭据存入安全存储。
final class CredentialsSubmission {
  const CredentialsSubmission({
    required this.credentials,
    required this.remember,
  });

  final SshCredentials credentials;
  final bool remember;
}

/// 连接前的凭据输入弹窗：按主机预设的认证方式展示对应输入项。
/// [initial] 用于预填（重试或已保存的凭据）；[allowRemember] 由当前平台的
/// CredentialStore 决定是否展示「记住凭据」开关。
/// [viaJumpHost] 为 true 时多给一行说明：这次输的是跳板机的凭据，
/// 用户看到的标题仍是那台跳板机的名字，不至于以为输错了主机。
Future<CredentialsSubmission?> showCredentialsDialog(
  BuildContext context,
  SshServer server, {
  SshCredentials? initial,
  bool allowRemember = false,
  bool rememberInitially = false,
  bool viaJumpHost = false,
}) {
  return showDialog<CredentialsSubmission>(
    context: context,
    builder: (_) => _CredentialsDialog(
      server: server,
      initial: initial,
      allowRemember: allowRemember,
      rememberInitially: rememberInitially,
      viaJumpHost: viaJumpHost,
    ),
  );
}

final class _CredentialsDialog extends StatefulWidget {
  const _CredentialsDialog({
    required this.server,
    this.initial,
    required this.allowRemember,
    required this.rememberInitially,
    required this.viaJumpHost,
  });

  final SshServer server;
  final SshCredentials? initial;
  final bool allowRemember;
  final bool rememberInitially;
  final bool viaJumpHost;

  @override
  State<_CredentialsDialog> createState() => _CredentialsDialogState();
}

final class _CredentialsDialogState extends State<_CredentialsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _privateKey = TextEditingController();
  final _passphrase = TextEditingController();
  late AuthMethod _auth = _inferAuthMethod();
  bool _obscure = true;
  late bool _remember = widget.rememberInitially;

  @override
  void initState() {
    super.initState();
    _password.text = widget.initial?.password ?? '';
    _privateKey.text = widget.initial?.privateKey ?? '';
    _passphrase.text = widget.initial?.passphrase ?? '';
  }

  @override
  void dispose() {
    _password.dispose();
    _privateKey.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  /// 优先跟随预填凭据实际携带的认证方式（上次连接可能与主机预设不同）。
  AuthMethod _inferAuthMethod() {
    final initial = widget.initial;
    if (initial?.password != null) return AuthMethod.password;
    if (initial?.privateKey != null) return AuthMethod.privateKey;
    if (initial?.useAgent ?? false) return AuthMethod.agent;
    return widget.server.authMethod;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      CredentialsSubmission(
        credentials: switch (_auth) {
          AuthMethod.password => SshCredentials(
            password: _password.text,
            passphrase: _passphraseOrNull(),
          ),
          AuthMethod.privateKey => SshCredentials(
            privateKey: _privateKey.text,
            passphrase: _passphraseOrNull(),
          ),
          // agent 里没有可输入的机密：只带意图标记，密钥清单连接时再向
          // 本机 agent 要。
          AuthMethod.agent => const SshCredentials(useAgent: true),
        },
        remember: widget.allowRemember && _remember,
      ),
    );
  }

  String? _passphraseOrNull() {
    final passphrase = _passphrase.text.trim();
    return passphrase.isEmpty ? null : passphrase;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.connectAuthTitle(widget.server.name)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.authMemoryHint,
              style: TextStyle(fontSize: 12, color: theme.secondaryText),
            ),
            if (widget.viaJumpHost) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.alt_route_rounded,
                    size: 14,
                    color: theme.secondaryText,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.jumpCredentialsHint(widget.server.name),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
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
                // 本平台没有 agent 时不给这个入口；但主机预设就是 Agent 时
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
              style: const ButtonStyle(
                textStyle: WidgetStatePropertyAll(
                  TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
              ),
              onSelectionChanged: (selection) =>
                  setState(() => _auth = selection.first),
            ),
            const SizedBox(height: 12),
            if (_auth == AuthMethod.password)
              TextFormField(
                controller: _password,
                autofocus: true,
                obscureText: _obscure,
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(
                  labelText: l10n.authPassword,
                  suffixIcon: IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? l10n.credentialsRequired
                    : null,
                onFieldSubmitted: (_) => _submit(),
              )
            else if (_auth == AuthMethod.agent) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: theme.secondaryText,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.agentAuthHint,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ] else ...[
              TextFormField(
                controller: _privateKey,
                autofocus: true,
                maxLines: 4,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  labelText: l10n.fieldPrivateKey,
                  hintText: l10n.privateKeyHint,
                  alignLabelWithHint: true,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? l10n.credentialsRequired
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passphrase,
                obscureText: true,
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(labelText: l10n.fieldPassphrase),
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
            if (widget.allowRemember) ...[
              const SizedBox(height: 4),
              CheckboxListTile(
                value: _remember,
                onChanged: (value) =>
                    setState(() => _remember = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                title: Text(
                  l10n.rememberCredentials,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.connect)),
      ],
    );
  }
}
