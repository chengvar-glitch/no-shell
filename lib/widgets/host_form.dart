/// 主机表单：输入框、校验、元数据粘贴、认证方式与凭据落盘只此一份。
///
/// 桌面端是编辑弹窗、移动端是整页表单，两端的**外壳**不同（滚动容器、按钮
/// 位置、间距密度），字段与保存逻辑共用这里的 [HostFormController] 与
/// [HostFormFields]——此前两端各写一遍，`jumpServerId` 的传法已经漂移成
/// 两种（一端从零构造再 `copyWith(clearJumpServer:)`，一端直接传）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../host_portable.dart';
import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../ssh/connect_flow.dart';
import '../ssh/credential_store.dart';
// 与 ssh/credentials_dialog 相互引用是刻意的：弹窗共用这里的三段选择器，
// 这里的「更换记住的凭据」复用弹窗，不再另写一份认证输入。
import '../ssh/credentials_dialog.dart';
import '../ssh/ssh_agent.dart';
import '../ssh/ssh_credentials.dart';
import '../theme.dart';
import 'confirm_dialog.dart';
import 'group_controls.dart';
import 'jump_host_field.dart';

/// 外壳的密度：桌面是弹窗（紧凑字号、12 间距），移动端是整页（跟随主题字号、
/// 14 间距、输入框给「下一项」动作）。
enum HostFormDensity {
  desktop(
    spacing: 12,
    fieldFontSize: 13.5,
    metadataFontSize: 12.5,
    notesMaxLines: 2,
    nextAction: false,
  ),
  mobile(
    spacing: 14,
    fieldFontSize: null,
    metadataFontSize: null,
    notesMaxLines: 3,
    nextAction: true,
  );

  const HostFormDensity({
    required this.spacing,
    required this.fieldFontSize,
    required this.metadataFontSize,
    required this.notesMaxLines,
    required this.nextAction,
  });

  final double spacing;
  final double? fieldFontSize;
  final double? metadataFontSize;
  final int notesMaxLines;

  /// 输入框是否给「下一项」动作（桌面弹窗里没有下一项可跳）。
  final bool nextAction;

  TextStyle? get fieldStyle =>
      fieldFontSize == null ? null : TextStyle(fontSize: fieldFontSize);

  TextStyle? get metadataStyle =>
      metadataFontSize == null ? null : TextStyle(fontSize: metadataFontSize);
}

/// 主机表单的状态与保存逻辑。外壳持有它，在 [State.dispose] 里调 [dispose]。
class HostFormController {
  HostFormController({
    SshServer? initial,
    String? initialGroup,
    this.credentials,
    this.onChanged,
  }) : initial = initial,
       group = initial?.group ?? initialGroup,
       auth = initial?.authMethod ?? AuthMethod.privateKey,
       jumpServerId = initial?.jumpServerId,
       name = TextEditingController(text: initial?.name),
       host = TextEditingController(text: initial?.host),
       port = TextEditingController(text: (initial?.port ?? 22).toString()),
       username = TextEditingController(text: initial?.username),
       notes = TextEditingController(text: initial?.notes) {
    unawaited(_loadStoredCredential());
  }

  /// 传入则为编辑，否则为新建。
  final SshServer? initial;

  /// 安全存储。编辑表单用它读出已记住的凭据、保存时落盘更换 / 清除；
  /// null（测试或没接存储的外壳）时凭据段整体不可见、保存不做凭据副作用。
  final CredentialStore? credentials;

  /// 凭据异步读取完成、待定状态变化后通知外壳重建——与
  /// [HostFormFields.onChanged] 是同一个回调，由外壳 setState。
  final VoidCallback? onChanged;

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController metadata = TextEditingController();
  final TextEditingController name;
  final TextEditingController host;
  final TextEditingController port;
  final TextEditingController username;
  final TextEditingController notes;

  /// 选中的分组名；null 表示默认分组（没动过下拉就是它）。
  String? group;

  AuthMethod auth;

  /// 选中的跳板机 id；null 表示直连。
  String? jumpServerId;

  /// 粘贴的元数据里带的密码，保存时写进安全存储。
  String? password;

  /// 已记住的凭据（安全存储异步读出，完成前为 null）。
  SshCredentials? storedCredential;

  /// 「更换凭据」弹窗提交的新凭据；点保存才落盘，取消表单即丢弃。
  SshCredentials? credentialReplacement;

  /// 点了「清除」；点保存才删除，再点「更换」会被覆盖。
  bool credentialCleared = false;

  bool _disposed = false;

  bool get isEditing => initial != null;

  bool get credentialsSupported => credentials?.supported ?? false;

  void dispose() {
    _disposed = true;
    for (final controller in [metadata, name, host, port, username, notes]) {
      controller.dispose();
    }
  }

  /// 读出已记住的凭据供状态行展示（只在编辑已有主机时有意义）。
  /// 完成时机不可控（钥匙串可能慢），回调前都查 [_disposed]。
  Future<void> _loadStoredCredential() async {
    final store = credentials;
    final id = initial?.id;
    if (store == null || !store.supported || id == null) return;
    final saved = await store.read(id);
    if (_disposed) return;
    storedCredential = saved;
    onChanged?.call();
  }

  /// 弹出凭据弹窗（lockRemember：这次输入就是要记住的内容）让用户更换。
  /// 提交结果先挂在 [credentialReplacement] 上，保存时才落盘——与表单其余
  /// 字段同一套「取消不生效」的语义。
  Future<void> replaceCredential(BuildContext context) async {
    final store = credentials;
    final host = initial;
    if (store == null || !store.supported || host == null) return;
    final l10n = AppLocalizations.of(context);
    final submission = await showCredentialsDialog(
      context,
      host,
      initial: credentialReplacement ?? storedCredential,
      lockRemember: true,
      title: l10n.credentialsDialogTitle(host.name),
      confirmLabel: l10n.save,
    );
    if (submission == null || _disposed) return;
    credentialReplacement = submission.credentials;
    credentialCleared = false;
    onChanged?.call();
  }

  /// 点「清除」：挂起删除，保存时生效。
  void clearCredential() {
    credentialReplacement = null;
    credentialCleared = true;
    onChanged?.call();
  }

  /// 把粘贴的元数据填进表单：只覆盖识别到的字段，用户仍可继续手动改。
  /// 返回是否有可用的识别结果；外壳据此决定要不要 setState。
  bool applyMetadata(AppLocalizations l10n, String text) {
    final drafts = parseHostsText(text, defaultGroup: l10n.defaultGroupName);
    if (drafts.isEmpty) return false;
    final draft = drafts.first;
    name.text = draft.name;
    host.text = draft.host;
    port.text = draft.port.toString();
    username.text = draft.username;
    password = draft.password;
    // 元数据只承载密码认证；没写密码时保留手动选择的认证方式。
    if (draft.password != null) auth = AuthMethod.password;
    return true;
  }

  /// 校验 + 落盘凭据，返回要保存的主机；校验不过或外壳已卸载时返回 null。
  ///
  /// 跳板机直接按 [jumpServerId] 构造（不从零拼再补）：取消跳板机就是传 null，
  /// 两端由此得到同一份语义。
  Future<SshServer?> build({required BuildContext context}) async {
    if (!(formKey.currentState?.validate() ?? false)) return null;
    final id = initial?.id ?? 'srv-${DateTime.now().microsecondsSinceEpoch}';
    await _persistCredentialChange(context, id);
    if (!context.mounted) return null;
    return SshServer(
      id: id,
      // 分组下拉里只有已建好的分组，没动过就是默认分组。
      group: group ?? AppLocalizations.of(context).defaultGroupName,
      name: name.text.trim(),
      host: host.text.trim(),
      username: username.text.trim(),
      port: int.parse(port.text.trim()),
      authMethod: auth,
      notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
      tags: initial?.tags ?? const [],
      lastConnectedAt: initial?.lastConnectedAt,
      jumpServerId: jumpServerId,
      // 转发规则不归本表单管（在转发页里编辑），原样带走；
      // 漏掉这一行等于每次保存都把该主机的规则清空。
      forwards: initial?.forwards ?? const [],
    );
  }

  /// 保存时的凭据落盘。优先级：显式更换 > 显式清除 > 粘贴元数据带的密码 >
  /// 认证方式改离密码时丢弃旧密码（改完后旧密码没人再认，留在存储里只会
  /// 在导出备份时被打包带走）。写入失败必须提示（同连接流程），绝不静默。
  Future<void> _persistCredentialChange(BuildContext context, String id) async {
    final store = credentials;
    final replacement = credentialReplacement;
    if (replacement != null) {
      if (store == null || !store.supported) return;
      final saved = await store.write(id, replacement);
      if (!saved && context.mounted) {
        showToast(
          context,
          AppLocalizations.of(context).credentialsSaveFailedMsg,
        );
      }
      return;
    }
    if (credentialCleared) {
      if (store == null) return;
      await dropStoredCredential(store, id);
      return;
    }
    final pasted = password;
    if (pasted != null && auth == AuthMethod.password) {
      if (store == null || !store.supported) return;
      final saved = await store.write(id, SshCredentials(password: pasted));
      if (!saved && context.mounted) {
        showToast(
          context,
          AppLocalizations.of(context).credentialsSaveFailedMsg,
        );
      }
      return;
    }
    if (auth != AuthMethod.password &&
        initial?.authMethod == AuthMethod.password &&
        store != null) {
      await dropStoredCredential(store, id);
    }
  }
}

/// 三选一的认证方式选择器：主机表单与凭据弹窗共用。
class AuthMethodSelector extends StatelessWidget {
  const AuthMethodSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.style,
  });

  final AuthMethod value;
  final ValueChanged<AuthMethod> onChanged;

  /// 收窄字号之类的微调；默认跟随所在外壳。
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
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
          // 本平台没有 agent 时不给这个入口；但取值本来就是 Agent 时仍要展示，
          // 否则保存的值在界面上无从呈现。
          if (sshAgentSupported || value == AuthMethod.agent)
            ButtonSegment(
              value: AuthMethod.agent,
              label: Text(l10n.authAgent),
              icon: const Icon(Icons.extension_outlined, size: 16),
            ),
        ],
        selected: {value},
        showSelectedIcon: false,
        style: style,
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

/// 表单的字段列。外壳负责滚动容器与内边距（弹窗比整页紧），字段顺序、
/// 校验规则与文案只此一份。
class HostFormFields extends StatelessWidget {
  const HostFormFields({
    super.key,
    required this.controller,
    required this.groups,
    required this.servers,
    required this.onChanged,
    this.density = HostFormDensity.desktop,
  });

  final HostFormController controller;

  /// 已建好的分组名。
  final List<String> groups;

  /// 全部已保存的主机，供跳板机下拉选；正在编辑的那台由
  /// [JumpHostField] 自己过滤掉。
  final List<SshServer> servers;

  /// 分组 / 跳板机 / 认证方式变了要通知外壳重建——这几项存在 controller 的
  /// 可变字段里，不走 TextEditingController，自己是不会刷新的。
  final VoidCallback onChanged;

  final HostFormDensity density;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final spacing = density.spacing;
    final fieldStyle = density.fieldStyle;
    final next = density.nextAction ? TextInputAction.next : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 粘贴为主、手输兜底：两处输入共存，元数据只覆盖识别到的字段。
        TextField(
          controller: controller.metadata,
          maxLines: 5,
          style: density.metadataStyle,
          decoration: InputDecoration(
            labelText: l10n.pasteMetadata,
            hintText: l10n.pasteMetadataHint,
            alignLabelWithHint: true,
          ),
          onChanged: (text) {
            if (controller.applyMetadata(l10n, text)) onChanged();
          },
        ),
        SizedBox(height: spacing),
        TextFormField(
          controller: controller.name,
          autofocus: !controller.isEditing,
          textInputAction: next,
          style: fieldStyle,
          decoration: InputDecoration(
            labelText: l10n.fieldName,
            hintText: l10n.nameHint,
          ),
          validator: (v) =>
              v == null || v.trim().isEmpty ? l10n.nameRequired : null,
        ),
        SizedBox(height: spacing),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: controller.host,
                textInputAction: next,
                style: fieldStyle,
                decoration: InputDecoration(
                  labelText: l10n.fieldHost,
                  hintText: l10n.hostHint,
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? l10n.hostRequired : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: controller.port,
                keyboardType: TextInputType.number,
                style: fieldStyle,
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
        SizedBox(height: spacing),
        TextFormField(
          controller: controller.username,
          textInputAction: next,
          style: fieldStyle,
          decoration: InputDecoration(
            labelText: l10n.username,
            hintText: l10n.usernameHint,
          ),
          validator: (v) =>
              v == null || v.trim().isEmpty ? l10n.usernameRequired : null,
        ),
        SizedBox(height: spacing),
        GroupField(
          value: controller.group ?? l10n.defaultGroupName,
          groups: groups,
          onChanged: (name) {
            controller.group = name;
            onChanged();
          },
        ),
        SizedBox(height: spacing),
        // 排在分组之后：分组是「这台主机属于哪」，跳板机是「怎么连过去」，
        // 紧挨着认证方式（同为连接参数）。
        JumpHostField(
          servers: servers,
          self: controller.initial,
          value: controller.jumpServerId,
          onChanged: (id) {
            controller.jumpServerId = id;
            onChanged();
          },
        ),
        SizedBox(height: spacing),
        // 分组 / 跳板机都有自带标签，认证方式补一个同级小标题，
        // 三选一的语义一眼可读。
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            l10n.authMethod,
            style: TextStyle(fontSize: 12, color: theme.secondaryText),
          ),
        ),
        const SizedBox(height: 6),
        // 与上下输入框同宽：不撑满时按钮组按内容居中，夹在整列全宽字段中间
        // 显得散乱。
        AuthMethodSelector(
          value: controller.auth,
          onChanged: (method) {
            controller.auth = method;
            onChanged();
          },
        ),
        if (controller.auth == AuthMethod.agent) ...[
          const SizedBox(height: 8),
          Text(
            l10n.agentAuthHint,
            style: TextStyle(fontSize: 12, color: theme.secondaryText),
          ),
        ],
        // 紧挨认证方式：这里管理的就是连接时自动用的那一份。只给编辑态、
        // 且本平台支持安全存储；新建主机的凭据照旧在首次连接时录入。
        if (controller.isEditing && controller.credentialsSupported) ...[
          SizedBox(height: spacing),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              l10n.rememberedCredentials,
              style: TextStyle(fontSize: 12, color: theme.secondaryText),
            ),
          ),
          const SizedBox(height: 6),
          _RememberedCredentialRow(controller: controller),
        ],
        SizedBox(height: spacing),
        TextFormField(
          controller: controller.notes,
          maxLines: density.notesMaxLines,
          style: fieldStyle,
          decoration: InputDecoration(
            labelText: l10n.notesOptional,
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}

/// 「记住的凭据」段的一行：当前状态 + 更换 / 清除。更换复用凭据弹窗
/// （lockRemember），结果先挂在 controller 的待定状态上，点保存才落盘；
/// 与表单其余字段同一套「取消不生效」的语义。
class _RememberedCredentialRow extends StatelessWidget {
  const _RememberedCredentialRow({required this.controller});

  final HostFormController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final replacement = controller.credentialReplacement;
    final stored = controller.storedCredential;
    final status = controller.credentialCleared
        ? l10n.credentialClearOnSave
        : replacement != null
        ? l10n.credentialRememberOnSave(_kindLabel(l10n, replacement))
        : stored != null
        ? l10n.credentialRememberedKind(_kindLabel(l10n, stored))
        : l10n.noRememberedCredential;
    return Row(
      children: [
        Expanded(child: Text(status, style: const TextStyle(fontSize: 12.5))),
        TextButton(
          onPressed: () => controller.replaceCredential(context),
          child: Text(
            replacement == null && stored == null
                ? l10n.rememberCredential
                : l10n.replaceCredential,
          ),
        ),
        if (replacement != null || stored != null)
          TextButton(
            onPressed: controller.clearCredential,
            child: Text(l10n.clearStoredCredential),
          ),
      ],
    );
  }
}

/// 已存凭据在界面上的类别名，与认证方式三段选择器共用一套文案。
String _kindLabel(AppLocalizations l10n, SshCredentials credential) =>
    authMethodLabel(
      l10n,
      credential.useAgent
          ? AuthMethod.agent
          : credential.privateKey != null
          ? AuthMethod.privateKey
          : AuthMethod.password,
    );
