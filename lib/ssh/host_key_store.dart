import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 一台主机已记录的一条公钥指纹。
///
/// 一台主机可以同时持有多种算法的主机密钥（sshd 默认同时提供 ed25519 与
/// rsa），而每台机器出示哪一种取决于**双方算法协商**的结果。用「一把主机
/// 一条记录」会在协商结果变化时（服务器换了密钥种类、或客户端升级后改变了
/// 算法偏好）把同一台机器判成「密钥变了」，也就是把用户训练成见警告就点。
/// 因此按主机存一组记录。
final class HostKeyRecord {
  const HostKeyRecord({required this.keyType, required this.fingerprint});

  /// 算法名，如 `ssh-ed25519`、`rsa-sha2-512`。
  final String keyType;

  /// `SHA256:...` 形式的指纹。dartssh2 只对密钥体做哈希，不含算法名，
  /// 因此同一把密钥换算法名之后指纹不变——这正是跨算法识别同一把密钥的依据。
  final String fingerprint;

  Map<String, Object?> toJson() => {'type': keyType, 'fp': fingerprint};

  @override
  bool operator ==(Object other) =>
      other is HostKeyRecord &&
      other.keyType == keyType &&
      other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(keyType, fingerprint);
}

/// [HostKeyStore.load] 的结果。**读失败必须与「从未记录」分开**：
/// 前者按首次记录放行，等于任何能让读取失败的人都能让客户端接受自己的密钥。
sealed class HostKeyLoad {
  const HostKeyLoad();
}

/// 读取成功；该主机从未记录过任何指纹。
final class HostKeysNeverRecorded extends HostKeyLoad {
  const HostKeysNeverRecorded();
}

/// 读取成功，返回已记录的指纹（至少一条）。
final class HostKeysLoaded extends HostKeyLoad {
  const HostKeysLoaded(this.records);

  final List<HostKeyRecord> records;
}

/// 读取失败：存储层不可用，或记录内容解不出来。
/// 调用方必须拒绝连接（fail closed），而不是当成首次记录。
final class HostKeysUnavailable extends HostKeyLoad {
  const HostKeysUnavailable();
}

/// 主机公钥指纹的持久化层，支撑 TOFU（首次使用即信任）校验。
/// 指纹不是机密，与主机列表同级存 shared_preferences 即可；
/// 凭据才需要 CredentialStore 的系统安全存储。
abstract interface class HostKeyStore {
  Future<HostKeyLoad> load(String host, int port);

  /// 追加一条记录；同一 (算法, 指纹) 已存在时不重复写。
  Future<void> save(String host, int port, HostKeyRecord record);

  /// 用户确认服务器密钥变更后清除全部记录，下次连接重新走首次记录流程。
  Future<void> delete(String host, int port);
}

/// 基于 shared_preferences 的实现，六个平台均可用（web 为 localStorage）。
final class SharedPreferencesHostKeyStore implements HostKeyStore {
  static const _prefix = 'ssh_host_keys_v1/';

  String _key(String host, int port) => '$_prefix$host:$port';

  @override
  Future<HostKeyLoad> load(String host, int port) async {
    final String? raw;
    try {
      final prefs = await SharedPreferences.getInstance();
      raw = prefs.getString(_key(host, port));
    } catch (_) {
      // 读不到 ≠ 没记过。这里必须 fail closed。
      return const HostKeysUnavailable();
    }
    if (raw == null) return const HostKeysNeverRecorded();
    final records = _decode(raw);
    return records == null
        ? const HostKeysUnavailable()
        : HostKeysLoaded(records);
  }

  @override
  Future<void> save(String host, int port, HostKeyRecord record) async {
    final existing = await load(host, port);
    // 读不出来时不要盲写：那会把用户原有的记录清掉，只留当前这一条。
    final records = switch (existing) {
      HostKeysLoaded(:final records) => records,
      HostKeysNeverRecorded() => const <HostKeyRecord>[],
      HostKeysUnavailable() => null,
    };
    if (records == null) return;
    if (records.contains(record)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(host, port),
      jsonEncode([...records, record].map((r) => r.toJson()).toList()),
    );
  }

  @override
  Future<void> delete(String host, int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(host, port));
  }

  /// 解析记录；内容不认识时返回 null，由调用方按「读不出来」处理。
  ///
  /// 兼容早期的单条纯文本格式 `ssh-ed25519:SHA256:xxx`。
  List<HostKeyRecord>? _decode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('[')) {
      final Object? decoded;
      try {
        decoded = jsonDecode(trimmed);
      } on FormatException {
        return null;
      }
      if (decoded is! List) return null;
      final records = <HostKeyRecord>[];
      for (final item in decoded) {
        if (item is! Map) return null;
        final type = item['type'];
        final fp = item['fp'];
        if (type is! String || fp is! String) return null;
        records.add(HostKeyRecord(keyType: type, fingerprint: fp));
      }
      return records;
    }
    // 旧格式：`type:fingerprint`（指纹本身含冒号，所以按第一个冒号切）。
    final at = trimmed.indexOf(':');
    if (at <= 0 || at == trimmed.length - 1) return null;
    return [
      HostKeyRecord(
        keyType: trimmed.substring(0, at),
        fingerprint: trimmed.substring(at + 1),
      ),
    ];
  }
}

HostKeyStore createHostKeyStore() => SharedPreferencesHostKeyStore();

/// TOFU 决策结果。
enum HostKeyDecision {
  /// 该主机从未记录过指纹：已记录本次出示的指纹并放行。
  firstUse,

  /// 与已记录的某条指纹一致：放行。
  trusted,

  /// 出示的指纹与该主机已记录的全部指纹都不一致：拒绝。
  mismatch,

  /// 读取已记录指纹失败：拒绝，且不改写任何记录。
  unavailable,
}

/// 比对本次出示的主机密钥与已记录指纹：
/// - 读取失败 → 拒绝（unavailable），不写任何东西；
/// - 从未记录 → 记录当前指纹并放行（firstUse）；
/// - 指纹命中已记录的任何一条 → 放行（trusted），若算法名是新的则补记一条；
/// - 都不命中 → 拒绝（mismatch），不改写记录，必须由用户显式清除。
///
/// 命中判据是**指纹**而非「算法名 + 指纹」：同一把密钥换算法名（服务器
/// 同时提供 ed25519 与 rsa、或客户端升级后改变了算法偏好）指纹不变，
/// 不该被误判成中间人。
Future<HostKeyDecision> verifyHostKey(
  HostKeyStore store, {
  required String host,
  required int port,
  required String keyType,
  required String fingerprint,
}) async {
  final presented = HostKeyRecord(keyType: keyType, fingerprint: fingerprint);
  final HostKeyLoad loaded;
  try {
    loaded = await store.load(host, port);
  } catch (_) {
    return HostKeyDecision.unavailable;
  }
  switch (loaded) {
    case HostKeysUnavailable():
      return HostKeyDecision.unavailable;
    case HostKeysNeverRecorded():
      await store.save(host, port, presented);
      return HostKeyDecision.firstUse;
    case HostKeysLoaded(:final records):
      final known = records.any(
        (record) => record.fingerprint == presented.fingerprint,
      );
      if (!known) return HostKeyDecision.mismatch;
      // 同一把密钥换算法名：补记这一组合，下次协商到它不必再写。
      if (!records.contains(presented)) {
        await store.save(host, port, presented);
      }
      return HostKeyDecision.trusted;
  }
}

/// 服务器出示的主机密钥与已记录指纹不一致：连接被拒绝。
/// 携带主机与指纹信息，供界面给出「确认更换 / 警惕中间人」的处置入口。
final class HostKeyChangedException implements Exception {
  const HostKeyChangedException({
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
  });

  final String host;
  final int port;
  final String keyType;
  final String fingerprint;

  @override
  String toString() =>
      'Host key changed for $host:$port ($keyType $fingerprint)';
}

/// 已记录的指纹读不出来：连接被拒绝，记录保持原样。
/// 与 [HostKeyChangedException] 分开，因为处置方式不同：这里不该让用户
/// 「清除指纹」（那会真的丢掉可信记录），而应提示存储层出了问题。
final class HostKeyUnavailableException implements Exception {
  const HostKeyUnavailableException({required this.host, required this.port});

  final String host;
  final int port;

  @override
  String toString() => 'Host key record unreadable for $host:$port';
}
