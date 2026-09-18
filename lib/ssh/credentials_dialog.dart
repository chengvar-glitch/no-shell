import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/confirm_dialog.dart' show showToast;
import '../widgets/host_form.dart' show AuthMethodSelector;
import 'ssh_credentials.dart';

/// 一次密钥文件选择的结果：显示名 + 文件文本（PEM）。
final class PickedKeyFile {
  const PickedKeyFile({required this.name, required this.text});

  final String name;
  final String text;
}

/// 真正的 PEM 只有几 KB；超限必是选错了文件，别把整个文件读进内存。
const _maxKeyFileLength = 1 << 20;

/// 密钥文件选择入口。生产实现走系统文件对话框，测试注入假实现——
/// widget 测试不能真的弹系统面板（同 `SshTerminalView.openLink` 的注入方式）。
Future<PickedKeyFile?> Function(String confirmLabel) pickPrivateKeyFile =
    pickPrivateKeyFileViaSelector;

/// 生产实现：不加类型过滤——私钥文件通常没有扩展名（id_rsa / id_ed25519），
/// 按扩展名过滤会把它们藏起来；读不出文本（超限 / 平台不支持）时抛错，
/// 由弹窗统一提示「无法读取」，绝不与「用户取消」（返回 null）混同。
Future<PickedKeyFile?> pickPrivateKeyFileViaSelector(
  String confirmLabel,
) async {
  final file = await openFile(confirmButtonText: confirmLabel);
  if (file == null) return null;
  if (await file.length() > _maxKeyFileLength) {
    throw StateError('key file too large: ${file.name}');
  }
  return PickedKeyFile(name: file.name, text: await file.readAsString());
}

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

  /// 最近一次选中的密钥文件名，仅作来源提示；手改输入框后即失效。
  String? _keyFileName;

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

  /// 选密钥文件并把内容灌进私钥输入框。取消（null）什么都不动；
  /// 读不出来（超限 / 平台不支持）提示后留在原状，不清用户已贴的内容。
  Future<void> _pickKeyFile() async {
    final l10n = AppLocalizations.of(context);
    final PickedKeyFile? picked;
    try {
      picked = await pickPrivateKeyFile(l10n.pickKeyFile);
    } catch (_) {
      if (!mounted) return;
      showToast(context, l10n.pickKeyFileFailedMsg);
      return;
    }
    if (picked == null || !mounted) return;
    // setState 的闭包里做不了类型提升，先取成非空局部量。
    final keyFile = picked;
    setState(() {
      _privateKey.text = keyFile.text;
      _keyFileName = keyFile.name;
    });
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
            // 与弹窗其他输入框同宽，不按内容居中。
            AuthMethodSelector(
              value: _auth,
              style: const ButtonStyle(
                textStyle: WidgetStatePropertyAll(
                  TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
              ),
              onChanged: (method) => setState(() => _auth = method),
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
                // 手改内容后「来自文件」的提示不再成立。
                onChanged: (_) {
                  if (_keyFileName == null) return;
                  setState(() => _keyFileName = null);
                },
              ),
              const SizedBox(height: 8),
              // 手贴与选文件两条路都汇入同一个输入框；文件名让用户知道
              // 当前内容来自哪份文件。
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickKeyFile,
                    icon: const Icon(Icons.file_open_outlined, size: 16),
                    label: Text(
                      l10n.pickKeyFile,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  if (_keyFileName != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _keyFileName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.secondaryText,
                        ),
                      ),
                    ),
                  ],
                ],
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
