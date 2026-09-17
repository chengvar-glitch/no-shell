import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../store.dart';
import 'credential_store.dart';
import 'credentials_dialog.dart';
import 'host_key_store.dart';
import 'jump_host.dart';
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
/// 有跳板机 → 先逐跳取凭据（没存过的当场弹窗），再连目标主机；
/// 已存凭据 → 免弹窗直连，认证失败自动回退到预填弹窗；
/// 否则先弹凭据框，勾选「记住凭据」时写入安全存储（取消勾选即清除）。
Future<void> toggleSession(
  BuildContext context, {
  required SessionManager sessions,
  required SshServer server,
  required CredentialStore credentials,
  ServerStore? store,
}) async {
  final existing = sessions.byServerId(server.id);
  if (existing?.isActive ?? false) {
    sessions.close(server.id);
    return;
  }

  final List<SshHop>? resolvedJumps;
  try {
    resolvedJumps = await _resolveJumps(
      context,
      sessions: sessions,
      credentials: credentials,
      server: server,
      store: store,
    );
  } on JumpChainException catch (error) {
    // 链路配置本身不成立：重试多少次都一样，只能回配置里改。
    if (!context.mounted) return;
    _showJumpChainError(context, error);
    return;
  }
  // 用户在某一跳的凭据弹窗里取消了：整条连接取消，不留半截。
  if (resolvedJumps == null || !context.mounted) return;
  final jumps = resolvedJumps;

  final saved = await credentials.read(server.id);
  if (!context.mounted) return;

  // 上一次直连已因认证失败告终：不再用旧凭据撞墙，直接弹预填弹窗。
  final authFailedBefore =
      existing != null &&
      existing.phase == TerminalPhase.failed &&
      existing.errorKind == TerminalErrorKind.auth;

  if (saved != null && !authFailedBefore) {
    final session = sessions.open(server, saved, jumps: jumps);
    if (await _failsWithAuth(session) &&
        context.mounted &&
        // 等待失败期间会话可能已被替换 / 移除，此时不再弹窗。
        identical(sessions.byServerId(server.id), session)) {
      await _promptAndConnect(
        context,
        sessions: sessions,
        server: server,
        credentials: credentials,
        jumps: jumps,
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
    jumps: jumps,
    initial: authFailedBefore ? saved : null,
    rememberInitially: saved != null,
  );
}

/// 解析跳板机链路并逐跳取凭据。
///
/// 返回 null 表示用户在某一步取消了；链路本身有问题时抛 [JumpChainException]。
/// [store] 为 null（测试或嵌入场景）时按「没有跳板机」处理。
Future<List<SshHop>?> _resolveJumps(
  BuildContext context, {
  required SessionManager sessions,
  required CredentialStore credentials,
  required SshServer server,
  required ServerStore? store,
}) async {
  final backend = store;
  if (backend == null || server.jumpServerId == null) return const [];
  final chain = resolveJumpChain(server, backend.byId);
  final hops = <SshHop>[];
  for (final hop in chain) {
    final hopCredentials = await _hopCredentials(
      context,
      sessions: sessions,
      credentials: credentials,
      server: hop,
    );
    if (hopCredentials == null || !context.mounted) return null;
    hops.add(SshHop(server: hop, credentials: hopCredentials));
  }
  return hops;
}

/// 取一跳的凭据：存过就直接用（认证失败过则重新弹窗），没存过就弹窗。
Future<SshCredentials?> _hopCredentials(
  BuildContext context, {
  required SessionManager sessions,
  required CredentialStore credentials,
  required SshServer server,
}) async {
  final saved = await credentials.read(server.id);
  if (!context.mounted) return null;
  final previous = sessions.byServerId(server.id);
  final authFailedBefore =
      previous != null &&
      previous.phase == TerminalPhase.failed &&
      previous.errorKind == TerminalErrorKind.auth;
  if (saved != null && !authFailedBefore) return saved;

  final submission = await showCredentialsDialog(
    context,
    server,
    initial: authFailedBefore ? saved : null,
    allowRemember: credentials.supported,
    rememberInitially: saved != null,
    viaJumpHost: true,
  );
  if (submission == null || !context.mounted) return null;
  if (credentials.supported) {
    if (submission.remember) {
      await credentials.write(server.id, submission.credentials);
    } else {
      await credentials.delete(server.id);
    }
  }
  return submission.credentials;
}

Future<void> _promptAndConnect(
  BuildContext context, {
  required SessionManager sessions,
  required SshServer server,
  required CredentialStore credentials,
  required List<SshHop> jumps,
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
  sessions.open(server, submission.credentials, jumps: jumps);
}

/// 跳板机链路不成立时的提示：指名道姓说清是哪台、哪一类问题。
void _showJumpChainError(BuildContext context, JumpChainException error) {
  final l10n = AppLocalizations.of(context);
  final name = error.hostName;
  final message = switch (error.kind) {
    JumpChainErrorKind.missing => l10n.jumpHostMissing(name ?? ''),
    JumpChainErrorKind.cycle => l10n.jumpHostCycle(name ?? ''),
    JumpChainErrorKind.tooDeep => l10n.jumpHostTooDeep(kMaxJumpDepth),
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
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
    // 同一个微任务里连着两次通知（例如 failed 紧跟 closed）会重复完成，
    // 那会抛 StateError。今天的状态机走不到，但这里不该靠运气。
    if (completer.isCompleted) return;
    completer.complete(isAuthFailure());
  };
  session.addListener(listener);
  try {
    return await completer.future;
  } finally {
    session.removeListener(listener);
  }
}
