/// 跳板机（ProxyJump）：连接目标主机前先连的一串中间主机。
library;

import '../models.dart';
import 'ssh_credentials.dart';

/// 解析结果深度上限。
///
/// 正常用户不会有 5 层跳板；设上限是为了让「A 跳 B、B 跳 C、C 又跳 A」
/// 这类环在有限步内报错，而不是把界面转死或把内存吃光。
const int kMaxJumpDepth = 8;

/// 一跳：一台主机 + 连它用的凭据。目标主机本身也是链上的最后一跳。
class SshHop {
  const SshHop({required this.server, required this.credentials});

  final SshServer server;
  final SshCredentials credentials;
}

/// 某一跳建连失败：把失败的那台主机带上，界面才能说清是哪一台。
///
/// 只包住「这一跳自己」的失败，原因原样保留在 [cause] 里，
/// 归类与文案都用 [unwrapHopError] 剥出来的真原因。
final class SshHopException implements Exception {
  const SshHopException(this.hop, this.cause);

  final SshServer hop;
  final Object cause;

  @override
  String toString() => '${hop.name}: $cause';
}

/// 跳板链路解析失败（环、深度超限、跳板机已被删除）。
///
/// 必须与「连接失败」分开：[TerminalErrorKind] 里没有一类是「配置本身不成立」，
/// 而这类错误重试多少次都一样，界面要引导用户去改配置。
final class JumpChainException implements Exception {
  const JumpChainException(this.kind, {this.hostName});

  final JumpChainErrorKind kind;

  /// 出问题的那台主机名（有的话），用于文案里指名道姓。
  final String? hostName;

  @override
  String toString() => 'JumpChainException(${kind.name}, $hostName)';
}

enum JumpChainErrorKind {
  /// 跳板机指向的主机已经不在列表里了。
  missing,

  /// 跳板机指回了链上已经出现过的主机。
  cycle,

  /// 跳板层数超过 [kMaxJumpDepth]。
  tooDeep,
}

/// 一跳失败时，真正的原因包在 [SshHopException] 里。
///
/// 归类（认证 / 网络 / 指纹）与文案都该按真正的原因走，否则「跳板机密码错了」
/// 会被报成一个笼统的失败、连重输密码的入口都给不出来。嵌套多层时一路剥到底。
Object unwrapHopError(Object error) {
  var current = error;
  // 每轮都换成 cause，成不了环；上限只是防御性写法。
  for (
    var depth = 0;
    depth < kMaxJumpDepth && current is SshHopException;
    depth++
  ) {
    current = current.cause;
  }
  return current;
}

/// 把「目标主机 → 跳板机 → 跳板机的跳板机 …」解析成由外到内的有序跳板列表。
///
/// 返回的列表不含目标主机本身：调用方按顺序依次连过去，最后一跳连目标。
/// 目标直接连时返回空列表。
///
/// [lookup] 按 id 取主机（测试传内存表，运行时传 ServerStore.byId）。
///
/// 这里只做结构解析，不碰凭据：凭据要弹窗，属于交互层的事。
List<SshServer> resolveJumpChain(
  SshServer target,
  SshServer? Function(String id) lookup,
) {
  final chain = <SshServer>[];
  final seen = <String>{target.id};
  var current = target;
  while (true) {
    final jumpId = current.jumpServerId;
    if (jumpId == null) break;
    if (!seen.add(jumpId)) {
      throw JumpChainException(
        JumpChainErrorKind.cycle,
        hostName: current.name,
      );
    }
    final jump = lookup(jumpId);
    if (jump == null) {
      throw JumpChainException(
        JumpChainErrorKind.missing,
        hostName: current.name,
      );
    }
    if (chain.length >= kMaxJumpDepth) {
      throw JumpChainException(JumpChainErrorKind.tooDeep, hostName: jump.name);
    }
    // 由内向外找到，插到最前面即得由外到内。
    chain.insert(0, jump);
    current = jump;
  }
  return chain;
}

/// 目标主机自己 + 其跳板链路，按「由外到内」排列，最后一项是目标本身。
/// 连接流程按这个顺序逐跳建连。
List<SshServer> connectionChain(
  SshServer target,
  SshServer? Function(String id) lookup,
) => [...resolveJumpChain(target, lookup), target];

/// 可以作为 [self] 的跳板机的主机：不能是自己，也不能是「已经（直接或间接）
/// 拿 self 当跳板机」的那些——否则一选下去就连成环，连接时才报错。
///
/// 表单用它过滤下拉候选，用户根本选不出坏配置。
List<SshServer> jumpHostCandidates(SshServer? self, Iterable<SshServer> all) {
  if (self == null) return List.unmodifiable(all);
  final byId = {for (final server in all) server.id: server};

  bool reachesSelf(SshServer candidate) {
    final seen = <String>{};
    var current = candidate;
    while (true) {
      if (current.id == self.id) return true;
      final jumpId = current.jumpServerId;
      if (jumpId == null || !seen.add(jumpId)) return false;
      final next = byId[jumpId];
      if (next == null) return false;
      current = next;
    }
  }

  return [
    for (final server in all)
      if (server.id != self.id && !reachesSelf(server)) server,
  ];
}
