/// 主机列表导入 / 导出的用户流程：桌面端侧边栏与移动端主机页共用。
///
/// 文件格式见 `host_backup.dart`：清单文本经口令加密后写入 `*.nsbak`，
/// 因此导入 / 导出都必须过一次口令弹窗。文件交互统一走 [LocalFileGateway]
/// （web 由桩兜底）；导入的密码在平台支持时写入安全存储。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import 'host_backup.dart';
import 'host_portable.dart';
import 'l10n/generated/app_localizations.dart';
import 'models.dart';
import 'ssh/credential_store.dart';
import 'ssh/local_files.dart';
import 'ssh/ssh_credentials.dart';
import 'store.dart';
import 'widgets/password_dialog.dart';

/// 选择一个备份文件，解密后把其中的主机合并进列表。
/// 口令不对或文件无法读取时提示后原样返回，不改动现有列表。
Future<void> importHostsFlow(
  BuildContext context, {
  required ServerStore store,
  required CredentialStore credentials,
  LocalFileGateway localFiles = const NativeLocalFileGateway(),
}) async {
  final l10n = AppLocalizations.of(context);
  final uploads = await localFiles.pickUploads(confirmLabel: l10n.importHosts);
  if (uploads.isEmpty || !context.mounted) return;

  final contents = await utf8.decodeStream(uploads.first.openRead());
  if (!context.mounted) return;
  // 先认文件再要口令：打不开的文件直接说，别让用户白输一遍。
  if (!isHostsBackup(contents)) {
    _showMessage(context, l10n.backupUnreadable);
    return;
  }

  final password = await _askBackupPassword(context, BackupPasswordMode.open);
  if (password == null || !context.mounted) return;

  final String text;
  try {
    text = decodeHostsBackup(contents, password);
  } on BackupFormatException catch (error) {
    if (!context.mounted) return;
    _showMessage(
      context,
      error.problem == BackupProblem.wrongPassword
          ? l10n.backupWrongPassword
          : l10n.backupUnreadable,
    );
    return;
  }

  final drafts = parseHostsText(text, defaultGroup: l10n.defaultGroupName);
  if (!context.mounted) return;
  if (drafts.isEmpty) {
    _showMessage(context, l10n.importEmpty);
    return;
  }
  await _mergeDrafts(context, drafts, store: store, credentials: credentials);
}

/// 把当前主机列表（含已记住的密码）导出为备份文件：先选落点，再设口令。
Future<void> exportHostsFlow(
  BuildContext context, {
  required ServerStore store,
  required CredentialStore credentials,
  LocalFileGateway localFiles = const NativeLocalFileGateway(),
}) async {
  final l10n = AppLocalizations.of(context);
  final entries = await _exportEntries(context, store, credentials);
  if (entries == null || !context.mounted) return;

  final target = await localFiles.pickDownloadTarget(
    'no-shell-hosts.$backupFileExtension',
    confirmLabel: l10n.exportHosts,
  );
  if (target == null || !context.mounted) return;

  final password = await _askBackupPassword(context, BackupPasswordMode.create);
  if (password == null || !context.mounted) return;

  final contents = encodeHostsBackup(encodeHostsText(entries), password);
  if (!context.mounted) return;
  await _writeTextFile(
    context,
    target: target,
    text: contents,
    localFiles: localFiles,
    done: l10n.exportDone(entries.length),
    failed: l10n.exportFailed,
  );
}

/// 收集待导出的主机；列表为空时提示并返回 null。
Future<List<HostExportEntry>?> _exportEntries(
  BuildContext context,
  ServerStore store,
  CredentialStore credentials,
) async {
  final l10n = AppLocalizations.of(context);
  final servers = store.servers;
  if (servers.isEmpty) {
    _showMessage(context, l10n.exportEmpty);
    return null;
  }
  final entries = <HostExportEntry>[];
  for (final server in servers) {
    final saved = credentials.supported
        ? await credentials.read(server.id)
        : null;
    entries.add((server: server, password: saved?.password));
  }
  return context.mounted ? entries : null;
}

/// 落盘并汇报：失败时清掉半成品文件，不留一个读不出内容的残档。
Future<void> _writeTextFile(
  BuildContext context, {
  required LocalTarget target,
  required String text,
  required LocalFileGateway localFiles,
  required String done,
  required String failed,
}) async {
  try {
    final handle = localFiles.openWrite(target.path);
    handle.add(utf8.encode(text));
    await handle.close();
  } on Object {
    await localFiles.discard(target.path);
    if (!context.mounted) return;
    _showMessage(context, failed);
    return;
  }
  if (!context.mounted) return;
  _showMessage(context, done);
}

/// 合并导入的主机：新增的落库，带密码的写进安全存储，最后汇报新增 / 跳过。
Future<void> _mergeDrafts(
  BuildContext context,
  List<HostImport> drafts, {
  required ServerStore store,
  required CredentialStore credentials,
}) async {
  final l10n = AppLocalizations.of(context);
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

Future<String?> _askBackupPassword(
  BuildContext context,
  BackupPasswordMode mode,
) => showBackupPasswordDialog(context, mode: mode);

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
