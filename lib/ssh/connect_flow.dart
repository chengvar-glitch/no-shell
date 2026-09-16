import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import 'credential_store.dart';
import 'credentials_dialog.dart';
import 'session_manager.dart';
import 'ssh_credentials.dart';
import 'terminal_session.dart';

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
