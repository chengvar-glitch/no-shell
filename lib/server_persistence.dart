import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 主机列表落盘通道；内存中的唯一状态源仍是 ServerStore。
/// 测试可注入内存假实现。
abstract interface class ServerPersistence {
  /// 读取已保存的主机列表；从未保存过返回 null，由调用方播种示例数据。
  /// 存档损坏同样返回 null，让下次保存覆盖为干净数据。
  Future<List<SshServer>?> load();

  Future<void> save(List<SshServer> servers);
}

/// 基于 shared_preferences 的 JSON 实现，六个平台均可用（web 为 localStorage）。
/// 注意：只存主机元数据，凭据一律走 CredentialStore 的系统安全存储。
final class SharedPreferencesServerPersistence implements ServerPersistence {
  static const _key = 'ssh_servers_v1';

  @override
  Future<List<SshServer>?> load() async {
    final String raw;
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_key);
      if (value == null) return null;
      raw = value;
    } catch (_) {
      return null;
    }
    try {
      final list = jsonDecode(raw) as List<Object?>;
      return [
        for (final item in list)
          SshServer.fromJson(item! as Map<String, Object?>),
      ];
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Future<void> save(List<SshServer> servers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final server in servers) server.toJson()]),
    );
  }
}
