import 'package:shared_preferences/shared_preferences.dart';

/// 主机公钥指纹的持久化层，支撑 TOFU（首次使用即信任）校验。
/// 指纹不是机密，与主机列表同级存 shared_preferences 即可；
/// 凭据才需要 CredentialStore 的系统安全存储。
abstract interface class HostKeyStore {
  /// 返回该主机此前记录的「keyType:fingerprint」，从未连接过返回 null。
  Future<String?> load(String host, int port);

  Future<void> save(String host, int port, String record);

  /// 用户确认服务器密钥变更后清除旧记录，下次连接重新走首次记录流程。
  Future<void> delete(String host, int port);
}

/// 基于 shared_preferences 的实现，六个平台均可用（web 为 localStorage）。
final class SharedPreferencesHostKeyStore implements HostKeyStore {
  static const _prefix = 'ssh_host_keys_v1/';

  String _key(String host, int port) => '$_prefix$host:$port';

  @override
  Future<String?> load(String host, int port) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key(host, port));
    } catch (_) {
      // 读不到按「从未记录」处理，回落到首次记录流程。
      return null;
    }
  }

  @override
  Future<void> save(String host, int port, String record) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(host, port), record);
  }

  @override
  Future<void> delete(String host, int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(host, port));
  }
}

HostKeyStore createHostKeyStore() => SharedPreferencesHostKeyStore();

/// TOFU 决策结果：首次记录、已知一致、已知但不一致。
enum HostKeyDecision { firstUse, trusted, mismatch }

/// 比对本次出示的主机密钥与已记录指纹：
/// - 从未记录 → 记录当前指纹并放行（firstUse）；
/// - 一致 → 放行（trusted）；
/// - 不一致 → 拒绝（mismatch）。拒绝时不改写记录，必须由用户显式清除。
Future<HostKeyDecision> verifyHostKey(
  HostKeyStore store, {
  required String host,
  required int port,
  required String keyType,
  required String fingerprint,
}) async {
  final presented = '$keyType:$fingerprint';
  final recorded = await store.load(host, port);
  if (recorded == null) {
    await store.save(host, port, presented);
    return HostKeyDecision.firstUse;
  }
  return recorded == presented
      ? HostKeyDecision.trusted
      : HostKeyDecision.mismatch;
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
