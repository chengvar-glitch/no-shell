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
import '../widgets/confirm_dialog.dart';

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

/// 删除一台主机的公共流程：危险确认 → 结束它的会话 → 清凭据与指纹（不 await）
/// → 从列表移除。桌面端与移动端两处入口共用，步骤顺序只此一份。
///
/// 返回被移除的下标；用户取消、或列表里已经没有这条时返回 null。调用方拿这个
/// 下标做后续动作（桌面端的「撤销」条要把主机插回原位），并负责给出提示。
Future<int?> confirmAndDeleteHost(
  BuildContext context, {
  required ServerStore store,
  required SessionManager sessions,
  required CredentialStore credentials,
  required HostKeyStore? hostKeys,
  required SshServer server,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showConfirmDialog(
    context,
    title: l10n.deleteConfirmTitle(server.name),
    body: l10n.deleteConfirmBody,
    confirmLabel: l10n.delete,
  );
  if (!confirmed || !context.mounted) return null;
  // 先结束该主机的会话（可能是多开的几条），避免悬挂连接。
  sessions.closeAll(server.id);
  // 凭据与指纹的清理不 await，理由见 [dropHostSecrets]。
  unawaited(
    dropHostSecrets(
      credentials: credentials,
      hostKeys: hostKeys,
      server: server,
    ),
  );
  final index = store.remove(server.id);
  return index == -1 ? null : index;
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
/// 该主机还有活跃会话 → 断开它的**全部**会话（多开时一次收干净）；
/// 有跳板机 → 先逐跳取凭据（没存过的先静默试本机 agent，再不行当场弹窗），
/// 再连目标主机；
/// 已存凭据 → 免弹窗直连，认证失败自动回退到预填弹窗；
/// 没存凭据 → 先静默试一把本机 agent 的钥匙（无感连接，见 [tryAgentConnect]），
/// 不行再弹凭据框，勾选「记住凭据」时写入安全存储（取消勾选即清除）。
Future<void> toggleSession(
  BuildContext context, {
  required SessionManager sessions,
  required SshServer server,
  required CredentialStore credentials,
  ServerStore? store,
}) async {
  if (sessions.sessionsOf(server.id).any((session) => session.isActive)) {
    sessions.closeAll(server.id);
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

  // 这台主机的某条会话刚因认证失败告终：不再用旧凭据撞墙，直接弹预填弹窗。
  final authFailedBefore = sessions.hasAuthFailure(server.id);

  if (saved != null && !authFailedBefore) {
    final session = sessions.open(server, saved, jumps: jumps);
    if (await _failsWithAuth(session) &&
        context.mounted &&
        // 等待失败期间会话可能已被替换 / 移除，此时不再弹窗。
        identical(sessions.activeOf(server.id), session)) {
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

  // 无感 agent：没有存档凭据时，先静默试一把本机 agent 的钥匙——和 ssh
  // 命令行的体感一致，「agent 里有能用的钥匙就直接进」。钥匙不被服务器认
  // 就悄悄收掉探测会话、回常规凭据框；网络 / 主机密钥之类的失败与 agent
  // 无关，保留错误现场让用户看到真实原因，不拿密码框掩盖。
  // agentKeysProbe 先做纯本地检查（agent 在不在、有没有钥匙），没有就
  // 直接走弹窗，不发探测连接。
  if (!authFailedBefore) {
    if (await sessions.agentKeysProbe()) {
      final outcome = await tryAgentConnect(sessions, server, jumps);
      if (outcome != AgentProbeOutcome.fallback) return;
    }
    if (!context.mounted) return;
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
      upstream: List.of(hops),
    );
    if (hopCredentials == null || !context.mounted) return null;
    hops.add(SshHop(server: hop, credentials: hopCredentials));
  }
  return hops;
}

/// 取一跳的凭据：存过就直接用（认证失败过则重新弹窗）；没存过先静默试
/// 本机 agent 的钥匙（逐跳都有份），不行再弹窗。
Future<SshCredentials?> _hopCredentials(
  BuildContext context, {
  required SessionManager sessions,
  required CredentialStore credentials,
  required SshServer server,
  required List<SshHop> upstream,
}) async {
  final saved = await credentials.read(server.id);
  if (!context.mounted) return null;
  // 这一跳刚因认证失败告终：不再静默复用旧凭据 / agent 的钥匙。
  final authFailedBefore = sessions.hasAuthFailure(server.id);
  if (saved != null && !authFailedBefore) return saved;

  // 无感 agent：这一跳没存过凭据时，先静默试本机 agent 的钥匙（逐跳都有份）；
  // 上一次认证刚失败过就不再试，直接弹窗。
  // 指纹不符 / 指纹存档读不出来不是「没有凭据」：拿密码框掩盖等于让用户
  // 先白输一遍密码、安全警示推迟到正式连接才出现。保留错误现场，终止连接。
  SshCredentials? hopAgentCredentials;
  if (!authFailedBefore) {
    try {
      hopAgentCredentials = await sessions.hopAgentProbe(server, upstream);
    } on HostKeyChangedException catch (error) {
      if (!context.mounted) return null;
      final l10n = AppLocalizations.of(context);
      final reason = l10n.hostKeyChangedMsgWithFingerprint(
        error.keyType,
        error.fingerprint,
      );
      await showInfoDialog(
        context,
        title: l10n.jumpHopFailure(server.name, reason),
        body: l10n.hostKeyForgetConfirmBody(error.host),
      );
      return null;
    } on HostKeyUnavailableException {
      if (!context.mounted) return null;
      final l10n = AppLocalizations.of(context);
      await showInfoDialog(
        context,
        title: l10n.jumpHopFailure(server.name, l10n.hostKeyChangedMsg),
        body: l10n.hostKeyUnavailableMsg,
      );
      return null;
    }
  }
  if (hopAgentCredentials != null) return hopAgentCredentials;
  if (!context.mounted) return null;

  final submission = await showCredentialsDialog(
    context,
    server,
    initial: authFailedBefore ? saved : null,
    allowRemember: credentials.supported,
    rememberInitially: saved != null,
    viaJumpHost: true,
  );
  if (submission == null || !context.mounted) return null;
  await _persistSubmission(
    context,
    credentials: credentials,
    serverId: server.id,
    submission: submission,
  );
  return submission.credentials;
}

/// 把凭据弹窗的提交结果落盘：勾了「记住凭据」就写进安全存储，没勾就清掉旧存档。
/// 平台不支持安全存储时什么都不做（弹窗已按 `credentials.supported` 隐藏该选项）。
///
/// 写入失败必须提示：钥匙串不可用时静默失败会让「记住凭据」形同虚设。
Future<void> _persistSubmission(
  BuildContext context, {
  required CredentialStore credentials,
  required String serverId,
  required CredentialsSubmission submission,
}) async {
  if (!credentials.supported) return;
  if (!submission.remember) {
    await credentials.delete(serverId);
    return;
  }
  final stored = await credentials.write(serverId, submission.credentials);
  if (!stored && context.mounted) {
    showToast(context, AppLocalizations.of(context).credentialsSaveFailedMsg);
  }
}

/// 无感 agent 的三种结局。
enum AgentProbeOutcome {
  /// agent 钥匙认证成功：会话已连上并留在注册表里，流程到此为止。
  connected,

  /// 失败与 agent 无关（网络不通、主机密钥不匹配等）：
  /// 会话留着展示真实错误，不要拿密码框去掩盖。
  keepError,

  /// 服务器不认 agent 的钥匙（或 agent 中途失联、连接被中断）：
  /// 探测会话已悄悄收掉，调用方应回退到常规凭据框。
  fallback,
}

/// 静默地用本机 agent 的钥匙连一次 [server]（无感连接）。
///
/// 成功时会话留在 [SessionManager] 里，宿主界面照常展示终端；只有「认证
/// 被拒」和「连接中断」才收掉会话并返回 [AgentProbeOutcome.fallback]。
/// 前置条件是调用方已通过 `sessions.agentKeysProbe()` 确认本机 agent 有钥匙，
/// 本函数不再重复检查。
Future<AgentProbeOutcome> tryAgentConnect(
  SessionManager sessions,
  SshServer server,
  List<SshHop> jumps,
) async {
  const credentials = SshCredentials(useAgent: true);
  final session = sessions.open(server, credentials, jumps: jumps);
  final (phase, kind) = await _awaitTerminal(session);
  switch (phase) {
    case TerminalPhase.connected:
      return AgentProbeOutcome.connected;
    case TerminalPhase.failed:
      final agentRelated =
          kind == TerminalErrorKind.auth || kind == TerminalErrorKind.agent;
      if (!agentRelated) return AgentProbeOutcome.keepError;
    case TerminalPhase.closed:
    case TerminalPhase.connecting:
      break;
  }
  // 认证被拒或连接中断：探测到此为止，收掉探测会话回常规流程。
  if (identical(sessions.activeOf(server.id), session)) {
    sessions.closeSession(session);
  }
  return AgentProbeOutcome.fallback;
}

/// 在同一台主机上**再开一条会话**（同一台服务器多开会话）。
/// 桌面端的「新建会话」入口与 ⌘T 走它；该主机还没有会话时它等价于连接。
///
/// 凭据优先级：① 现有会话手头的凭据——用户没勾「记住凭据」时密码只在内存
/// 里，再开一条不该重新问一遍 ② 安全存储里的存档凭据 ③ 本机 agent 的钥匙
/// （无感，本机没 agent 就跳过）④ 凭据弹窗。只有认证被拒才回退到弹窗；
/// 网络 / 指纹 / 跳板链路这类与凭据无关的失败保留错误现场，不拿密码框掩盖。
Future<void> newSessionFlow(
  BuildContext context, {
  required SessionManager sessions,
  required SshServer server,
  required CredentialStore credentials,
  ServerStore? store,
}) async {
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
    if (!context.mounted) return;
    _showJumpChainError(context, error);
    return;
  }
  if (resolvedJumps == null || !context.mounted) return;
  final jumps = resolvedJumps;

  // 存档凭据照旧读出来（弹窗要预填它），但下面会不会拿它去静默撞墙，
  // 取决于这台主机是不是刚撞过认证失败。
  final saved = await credentials.read(server.id);
  if (!context.mounted) return;
  final authFailedBefore = sessions.hasAuthFailure(server.id);
  final sibling = authFailedBefore
      ? null
      : sessions.activeOf(server.id)?.credentials;

  final candidates = <({SshCredentials credentials, bool remembered})>[
    // 现有会话手头的凭据：没落过盘，弹窗回退时也就不预勾「记住凭据」。
    if (sibling != null) (credentials: sibling, remembered: false),
    if (saved != null && !authFailedBefore)
      (credentials: saved, remembered: true),
  ];

  for (final candidate in candidates) {
    final outcome = await _tryNewSession(
      sessions,
      server,
      candidate.credentials,
      jumps,
    );
    if (outcome == _AttemptOutcome.connected) return;
    if (outcome == _AttemptOutcome.keepError) return;
    if (!context.mounted) return;
    await _promptAndConnect(
      context,
      sessions: sessions,
      server: server,
      credentials: credentials,
      jumps: jumps,
      initial: candidate.credentials,
      rememberInitially: candidate.remembered,
      spawnNew: true,
    );
    return;
  }

  if (!authFailedBefore && await sessions.agentKeysProbe()) {
    if (!context.mounted) return;
    final outcome = await _tryNewSession(
      sessions,
      server,
      const SshCredentials(useAgent: true),
      jumps,
    );
    if (outcome != _AttemptOutcome.fallback) return;
    if (!context.mounted) return;
  }

  if (!context.mounted) return;
  await _promptAndConnect(
    context,
    sessions: sessions,
    server: server,
    credentials: credentials,
    jumps: jumps,
    // 上一次就栽在认证上：把存档的那份预填出来让人改，但不再拿它静默重试。
    initial: authFailedBefore ? saved : null,
    rememberInitially: saved != null,
    spawnNew: true,
  );
}

/// 一次「再开一条会话」的尝试的三种结局。
enum _AttemptOutcome {
  /// 连上了：会话留在管理器里，流程到此为止。
  connected,

  /// 与凭据无关的失败（网络 / 指纹 / 链路）：会话留着展示真实错误。
  keepError,

  /// 凭据不被接受：探测出来的这条会话已收掉，调用方回退到凭据弹窗。
  fallback,
}

/// 用一份凭据试着新开一条会话。
///
/// 失败与凭据无关时保留这条会话（用户看得到真实原因）；认证被拒则把它收掉——
/// 菜单里不该留下一条用户没要过、也没法用的失败会话。
Future<_AttemptOutcome> _tryNewSession(
  SessionManager sessions,
  SshServer server,
  SshCredentials credentials,
  List<SshHop> jumps,
) async {
  final session = sessions.openNew(server, credentials, jumps: jumps);
  final (phase, kind) = await _awaitTerminal(session);
  if (phase == TerminalPhase.connected) return _AttemptOutcome.connected;
  if (phase == TerminalPhase.failed &&
      (kind == TerminalErrorKind.auth || kind == TerminalErrorKind.agent)) {
    sessions.closeSession(session);
    return _AttemptOutcome.fallback;
  }
  return _AttemptOutcome.keepError;
}

Future<void> _promptAndConnect(
  BuildContext context, {
  required SessionManager sessions,
  required SshServer server,
  required CredentialStore credentials,
  required List<SshHop> jumps,
  required SshCredentials? initial,
  required bool rememberInitially,
  bool spawnNew = false,
}) async {
  final submission = await showCredentialsDialog(
    context,
    server,
    initial: initial,
    allowRemember: credentials.supported,
    rememberInitially: rememberInitially,
  );
  if (submission == null || !context.mounted) return;
  await _persistSubmission(
    context,
    credentials: credentials,
    serverId: server.id,
    submission: submission,
  );
  if (!context.mounted) return;
  // spawnNew：这是「再开一条会话」，不是让主机连上——已经在跑的会话不许被顶掉。
  if (spawnNew) {
    sessions.openNew(server, submission.credentials, jumps: jumps);
  } else {
    sessions.open(server, submission.credentials, jumps: jumps);
  }
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
  showToast(context, message);
}

/// 等待会话进入首个终态，返回 (终态, 失败归类)。
/// 同一个微任务里连着两次通知（例如 failed 紧跟 closed）会重复完成，
/// 那会抛 StateError——今天的状态机走不到，但这里不该靠运气。
Future<(TerminalPhase, TerminalErrorKind)> _awaitTerminal(
  TerminalSession session,
) async {
  if (session.phase != TerminalPhase.connecting) {
    return (session.phase, session.errorKind);
  }
  final completer = Completer<void>();
  late final VoidCallback listener;
  listener = () {
    if (session.phase == TerminalPhase.connecting) return;
    if (completer.isCompleted) return;
    completer.complete();
  };
  session.addListener(listener);
  try {
    await completer.future;
  } finally {
    session.removeListener(listener);
  }
  return (session.phase, session.errorKind);
}

/// 等待会话进入首个终态；仅认证失败返回 true。
Future<bool> _failsWithAuth(TerminalSession session) async {
  final (phase, kind) = await _awaitTerminal(session);
  return phase == TerminalPhase.failed && kind == TerminalErrorKind.auth;
}
