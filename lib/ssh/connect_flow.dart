import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import 'credential_store.dart';
import 'credentials_dialog.dart';
import 'host_key_store.dart';
import 'session_manager.dart';
import 'ssh_credentials.dart';
import 'terminal_session.dart';

/// 把「已存凭据」和「已记录的主机指纹」随主机一起清掉。
///
/// 删除主机时两者都该走：留着的凭据会在下次导出备份时被打包带走，
/// 留着的指纹则会让同地址的新机器被判成「密钥变了」。
///
/// 全程吞异常且**不做超时以外的等待**：底层存储（钥匙串 / shared_preferences）
/// 不可用时不能把删除流程一起拖住，用户的删除动作本身必须完成。
/// 撤销删除（restore）不会把它们找回来——这是刻意的，宁可重连一次
/// 重新记录，也不留一份没人再看的旧凭据。
Future<void> dropHostSecrets({
  required CredentialStore credentials,
  required HostKeyStore? hostKeys,
  required SshServer server,
}) async {
  await dropStoredCredential(credentials, server.id);
  final store = hostKeys;
  if (store == null) return;
  try {
    await store.delete(server.host, server.port);
  } catch (_) {
    // 指纹没清掉只影响下次连接的判定，不该让删除失败。
  }
}

/// 清除某台主机已存的凭据（主机被删、或认证方式改成了不用密码）。
Future<void> dropStoredCredential(
  CredentialStore credentials,
  String serverId,
) async {
  if (!credentials.supported) return;
  try {
    await credentials.delete(serverId);
  } catch (_) {
    // 同上：清不掉凭据不是删除失败的理由。
  }
}

/// 统一的连接 / 断开入口，桌面端与移动端共用：
/// 已有活跃会话 → 直接断开；
/// 已存凭据 → 免弹窗直连，认证失败自动回退到预填弹窗；
/// 否则先弹凭据框，勾选「记住凭据」时写入安全存储（取消勾选即清除）。
Future<void> toggleSession(
  BuildContext context, {
  required SessionManager sessions,
  required SshServer server,
  required CredentialStore credentials,
}) async {
  final existing = sessions.byServerId(server.id);
  if (existing?.isActive ?? false) {
    sessions.close(server.id);
    return;
  }
  final saved = await credentials.read(server.id);
  if (!context.mounted) return;

  // 上一次直连已因认证失败告终：不再用旧凭据撞墙，直接弹预填弹窗。
  final authFailedBefore =
      existing != null &&
      existing.phase == TerminalPhase.failed &&
      existing.errorKind == TerminalErrorKind.auth;

  if (saved != null && !authFailedBefore) {
    final session = sessions.open(server, saved);
    if (await _failsWithAuth(session) &&
        context.mounted &&
        // 等待失败期间会话可能已被替换 / 移除，此时不再弹窗。
        identical(sessions.byServerId(server.id), session)) {
      await _promptAndConnect(
        context,
        sessions: sessions,
        server: server,
        credentials: credentials,
        initial: saved,
        rememberInitially: true,
      );
    }
    return;
  }

  await _promptAndConnect(
    context,
    sessions: sessions,
    server: server,
    credentials: credentials,
    initial: authFailedBefore ? saved : null,
    rememberInitially: saved != null,
  );
}

Future<void> _promptAndConnect(
  BuildContext context, {
  required SessionManager sessions,
  required SshServer server,
  required CredentialStore credentials,
  required SshCredentials? initial,
  required bool rememberInitially,
}) async {
  final submission = await showCredentialsDialog(
    context,
    server,
    initial: initial,
    allowRemember: credentials.supported,
    rememberInitially: rememberInitially,
  );
  if (submission == null || !context.mounted) return;
  if (credentials.supported) {
    if (submission.remember) {
      await credentials.write(server.id, submission.credentials);
    } else {
      await credentials.delete(server.id);
    }
  }
  if (!context.mounted) return;
  sessions.open(server, submission.credentials);
}

/// 等待会话进入首个终态；仅认证失败返回 true。
Future<bool> _failsWithAuth(TerminalSession session) async {
  bool isAuthFailure() =>
      session.phase == TerminalPhase.failed &&
      session.errorKind == TerminalErrorKind.auth;
  if (session.phase != TerminalPhase.connecting) return isAuthFailure();

  final completer = Completer<bool>();
  late final VoidCallback listener;
  listener = () {
    if (session.phase == TerminalPhase.connecting) return;
    completer.complete(isAuthFailure());
  };
  session.addListener(listener);
  try {
    return await completer.future;
  } finally {
    session.removeListener(listener);
  }
}
