/// 主机表单：输入框、校验、元数据粘贴、认证方式与凭据落盘只此一份。
///
/// 桌面端是编辑弹窗、移动端是整页表单，两端的**外壳**不同（滚动容器、按钮
/// 位置、间距密度），字段与保存逻辑共用这里的 [HostFormController] 与
/// [HostFormFields]——此前两端各写一遍，`jumpServerId` 的传法已经漂移成
/// 两种（一端从零构造再 `copyWith(clearJumpServer:)`，一端直接传）。
library;

import 'package:flutter/material.dart';

import '../host_portable.dart';
import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../ssh/connect_flow.dart';
import '../ssh/credential_store.dart';
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

  TextStyle? get metadataStyle => metadataFontSize == null
      ? null
      : TextStyle(fontSize: metadataFontSize);
}

/// 主机表单的状态与保存逻辑。外壳持有它，在 [State.dispose] 里调 [dispose]。
class HostFormController {
  HostFormController({SshServer? initial, String? initialGroup})
    : initial = initial,
      group = initial?.group ?? initialGroup,
      auth = initial?.authMethod ?? AuthMethod.privateKey,
      jumpServerId = initial?.jumpServerId,
      name = TextEditingController(text: initial?.name),
      host = TextEditingController(text: initial?.host),
      port = TextEditingController(text: (initial?.port ?? 22).toString()),
      username = TextEditingController(text: initial?.username),
      notes = TextEditingController(text: initial?.notes);

  /// 传入则为编辑，否则为新建。
  final SshServer? initial;

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

  bool get isEditing => initial != null;

  void dispose() {
    for (final controller in [
      metadata,
      name,
      host,
      port,
      username,
      notes,
    ]) {
      controller.dispose();
    }
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
  Future<SshServer?> build({
    required BuildContext context,
    required CredentialStore credentials,
  }) async {
    if (!(formKey.currentState?.validate() ?? false)) return null;
    final l10n = AppLocalizations.of(context);
    final id = initial?.id ?? 'srv-${DateTime.now().microsecondsSinceEpoch}';
    final pasted = password;
    if (pasted != null &&
        auth == AuthMethod.password &&
        credentials.supported) {
      final saved = await credentials.write(
        id,
        SshCredentials(password: pasted),
      );
      if (!saved && context.mounted) {
        showToast(context, l10n.credentialsSaveFailedMsg);
      }
    } else if (auth != AuthMethod.password &&
        initial?.authMethod == AuthMethod.password) {
      // 改成密钥 / agent 认证后旧密码没人再用，但导出备份时会把它一起打包走。
      await dropStoredCredential(credentials, id);
    }
    if (!context.mounted) return null;
    return SshServer(
      id: id,
      // 分组下拉里只有已建好的分组，没动过就是默认分组。
      group: group ?? l10n.defaultGroupName,
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
