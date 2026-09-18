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
import 'widgets/confirm_dialog.dart';
import 'widgets/password_dialog.dart';

/// 「导入 / 导出主机」菜单的两个动作。用枚举而不是字符串，菜单项增删时
/// switch 会被分析器盯住。桌面端侧边栏与移动端主机页共用。
enum HostTransferAction { import, export }

/// 菜单项的图标与文案；两端只是密度不同（桌面 16/8/13、移动 20/12/默认），
/// 顺序与措辞只此一份。
List<({HostTransferAction action, IconData icon, String label})>
hostTransferMenuItems(AppLocalizations l10n) => [
  (
    action: HostTransferAction.import,
    icon: Icons.download_rounded,
    label: l10n.importHosts,
  ),
  (
    action: HostTransferAction.export,
    icon: Icons.upload_outlined,
    label: l10n.exportHosts,
  ),
];

/// 执行选中的动作；移动端主机页的菜单直接走它。
Future<void> runHostTransferAction(
  BuildContext context, {
  required HostTransferAction action,
  required ServerStore store,
  required CredentialStore credentials,
}) => switch (action) {
  HostTransferAction.import => importHostsFlow(
    context,
    store: store,
    credentials: credentials,
  ),
  HostTransferAction.export => exportHostsFlow(
    context,
    store: store,
    credentials: credentials,
  ),
};

/// 选择一个备份文件，解密后把其中的主机合并进列表。
/// 口令不对或文件无法读取时提示后原样返回，不改动现有列表。
///
/// [derive] 只给测试注入同步派生用（见 [HostBackupParams.useIsolate]）。
Future<void> importHostsFlow(
  BuildContext context, {
  required ServerStore store,
  required CredentialStore credentials,
  LocalFileGateway localFiles = const NativeLocalFileGateway(),
  DeriveRunner? derive,
}) async {
  final l10n = AppLocalizations.of(context);
  final uploads = await localFiles.pickUploads(confirmLabel: l10n.importHosts);
  if (uploads.isEmpty || !context.mounted) return;

  final contents = await utf8.decodeStream(uploads.first.openRead());
  if (!context.mounted) return;
  // 先认文件再要口令：打不开的文件直接说，别让用户白输一遍。
  if (!isHostsBackup(contents)) {
    showToast(context, l10n.backupUnreadable);
    return;
  }

  final password = await showBackupPasswordDialog(
    context,
    mode: BackupPasswordMode.open,
  );
  if (password == null || !context.mounted) return;

  final String text;
  try {
    text = await decodeHostsBackup(contents, password, derive: derive);
  } on BackupFormatException catch (error) {
    if (!context.mounted) return;
    showToast(
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
    showToast(context, l10n.importEmpty);
    return;
  }
  await _mergeDrafts(context, drafts, store: store, credentials: credentials);
}

/// 把当前主机列表（含已记住的密码）导出为备份文件：先选落点，再设口令。
///
/// [backupParams] 只给测试注入低参数用，生产路径不传。
Future<void> exportHostsFlow(
  BuildContext context, {
  required ServerStore store,
  required CredentialStore credentials,
  LocalFileGateway localFiles = const NativeLocalFileGateway(),
  HostBackupParams backupParams = HostBackupParams.standard,
}) async {
  final l10n = AppLocalizations.of(context);
  final entries = await _exportEntries(context, store, credentials);
  if (entries == null || !context.mounted) return;

  final destination = await localFiles.pickExportDestination(
    'no-shell-hosts.$backupFileExtension',
    confirmLabel: l10n.exportHosts,
  );
  if (destination == null || !context.mounted) return;

  final password = await showBackupPasswordDialog(
    context,
    mode: BackupPasswordMode.create,
  );
  if (password == null || !context.mounted) return;

  final contents = await encodeHostsBackup(
    encodeHostsText(entries),
    password,
    params: backupParams,
  );
  if (!context.mounted) return;
  await _writeExport(
    context,
    destination: destination,
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
    showToast(context, l10n.exportEmpty);
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

/// 落盘并汇报：失败时清掉半成品文件，不留一个读不出内容的残档；
/// 落点是「写完要分享」的那种（移动端）时，交给系统分享面板收尾。
Future<void> _writeExport(
  BuildContext context, {
  required LocalDestination destination,
  required String text,
  required LocalFileGateway localFiles,
  required String done,
  required String failed,
}) async {
  try {
    // ownerOnly：导出的明文里带着主机密码，落成 0644 等于同机器上
    // 任何本地账号都能读。
    final handle = localFiles.openWrite(destination.path, ownerOnly: true);
    handle.add(utf8.encode(text));
    await handle.close();
  } on Object {
    await localFiles.discard(destination.path);
    if (!context.mounted) return;
    showToast(context, failed);
    return;
  }
  if (destination.share) {
    await localFiles.shareLocalFile(destination.path, title: destination.name);
  }
  if (!context.mounted) return;
  showToast(context, done);
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
  var saveFailed = false;
  if (credentials.supported) {
    final addedSet = Set<SshServer>.of(added);
    for (var i = 0; i < drafts.length; i++) {
      final password = drafts[i].password;
      if (password == null || !addedSet.contains(candidates[i])) continue;
      final saved = await credentials.write(
        candidates[i].id,
        SshCredentials(password: password),
      );
      if (!saved) saveFailed = true;
    }
  }
  if (!context.mounted) return;

  final skipped = drafts.length - added.length;
  showToast(
    context,
    [
      if (added.isNotEmpty) l10n.importDone(added.length),
      if (skipped > 0) l10n.importSkipped(skipped),
      if (saveFailed) l10n.credentialsSaveFailedMsg,
    ].join(' '),
  );
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
