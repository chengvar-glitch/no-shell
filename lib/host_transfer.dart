/// 主机列表导入 / 导出的用户流程：桌面端侧边栏与移动端主机页共用。
/// 文件交互统一走 [LocalFileGateway]（web 由桩兜底），文本格式见
/// `host_portable.dart`；导入的密码在平台支持时写入安全存储。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import 'host_portable.dart';
import 'l10n/generated/app_localizations.dart';
import 'models.dart';
import 'ssh/credential_store.dart';
import 'ssh/local_files.dart';
import 'ssh/ssh_credentials.dart';
import 'store.dart';

/// 选择一个或多个文本文件解析为主机并合并进列表；
/// 结束后以 SnackBar 汇报新增 / 跳过数量。
Future<void> importHostsFlow(
  BuildContext context, {
  required ServerStore store,
  required CredentialStore credentials,
  LocalFileGateway localFiles = const NativeLocalFileGateway(),
}) async {
  final l10n = AppLocalizations.of(context);
  final uploads = await localFiles.pickUploads(confirmLabel: l10n.importHosts);
  if (uploads.isEmpty || !context.mounted) return;

  final drafts = <HostImport>[];
  for (final upload in uploads) {
    final text = await utf8.decodeStream(upload.openRead());
    drafts.addAll(parseHostsText(text, defaultGroup: l10n.defaultGroupName));
  }
  if (!context.mounted) return;
  if (drafts.isEmpty) {
    _showMessage(context, l10n.importEmpty);
    return;
  }

  final stamp = DateTime.now().microsecondsSinceEpoch;
  final candidates = [
    for (var i = 0; i < drafts.length; i++)
      _serverOf(drafts[i], id: 'srv-$stamp-$i'),
  ];
  final added = store.importServers(candidates);
  if (credentials.supported) {
    final addedSet = Set<SshServer>.of(added);
    for (var i = 0; i < drafts.length; i++) {
      final password = drafts[i].password;
      if (password == null || !addedSet.contains(candidates[i])) continue;
      await credentials.write(
        candidates[i].id,
        SshCredentials(password: password),
      );
    }
  }
  if (!context.mounted) return;

  final skipped = drafts.length - added.length;
  _showMessage(
    context,
    [
      if (added.isNotEmpty) l10n.importDone(added.length),
      if (skipped > 0) l10n.importSkipped(skipped),
    ].join(' '),
  );
}

/// 把当前主机列表（含已记住的密码）导出为文本文件。
Future<void> exportHostsFlow(
  BuildContext context, {
  required ServerStore store,
  required CredentialStore credentials,
  LocalFileGateway localFiles = const NativeLocalFileGateway(),
}) async {
  final l10n = AppLocalizations.of(context);
  final servers = store.servers;
  if (servers.isEmpty) {
    _showMessage(context, l10n.exportEmpty);
    return;
  }
  final entries = <HostExportEntry>[];
  for (final server in servers) {
    final saved = credentials.supported
        ? await credentials.read(server.id)
        : null;
    entries.add((server: server, password: saved?.password));
  }
  if (!context.mounted) return;

  final target = await localFiles.pickDownloadTarget(
    'no-shell-hosts.txt',
    confirmLabel: l10n.exportHosts,
  );
  if (target == null || !context.mounted) return;

  final handle = localFiles.openWrite(target.path);
  try {
    handle.add(utf8.encode(encodeHostsText(entries)));
    await handle.close();
  } on Object {
    await localFiles.discard(target.path);
    if (!context.mounted) return;
    _showMessage(context, l10n.exportFailed);
    return;
  }
  if (!context.mounted) return;
  _showMessage(context, l10n.exportDone(servers.length));
}

SshServer _serverOf(HostImport draft, {required String id}) => SshServer(
  id: id,
  group: draft.group,
  name: draft.name,
  host: draft.host,
  username: draft.username,
  port: draft.port,
  // 带密码的条目按密码认证导入，其余保持默认的私钥认证。
  authMethod: draft.password == null
      ? AuthMethod.privateKey
      : AuthMethod.password,
);

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
