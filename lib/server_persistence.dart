import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 一次落盘的完整快照：主机列表 + 分组布局。
/// 主机条目本身仍只记分组名，分组布局（顺序 / 折叠态）另存一份，
/// 因此旧版存档（纯主机数组）可直接读上来，顺序按主机出现次序重建。
class ServerArchive {
  const ServerArchive({
    required this.servers,
    this.groupOrder = const [],
    this.collapsedGroups = const {},
  });

  final List<SshServer> servers;

  /// 分组展示顺序；存档里没记到的分组名由 ServerStore 按主机出现次序补齐。
  final List<String> groupOrder;

  /// 处于折叠态的分组名。
  final Set<String> collapsedGroups;
}

/// 主机与分组布局的落盘通道；内存中的唯一状态源仍是 ServerStore。
/// 测试可注入内存假实现。
abstract interface class ServerPersistence {
  /// 读取存档；从未保存过返回 null，由调用方播种示例数据。
  /// 存档损坏同样返回 null，让下次保存覆盖为干净数据。
  Future<ServerArchive?> load();

  Future<void> save(ServerArchive archive);
}

/// 基于 shared_preferences 的 JSON 实现，六个平台均可用（web 为 localStorage）。
/// 注意：只存主机元数据，凭据一律走 CredentialStore 的系统安全存储。
final class SharedPreferencesServerPersistence implements ServerPersistence {
  /// 主机条目沿用 v1 的纯数组格式：旧版本读得懂，降级不丢主机。
  static const _serversKey = 'ssh_servers_v1';

  /// 分组布局（顺序 / 折叠态）；缺失即按主机出现次序重建。
  static const _groupsKey = 'ssh_groups_v1';

  @override
  Future<ServerArchive?> load() async {
    final String rawServers;
    final String? rawGroups;
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_serversKey);
      if (value == null) return null;
      rawServers = value;
      rawGroups = prefs.getString(_groupsKey);
    } catch (_) {
      return null;
    }
    try {
      final list = jsonDecode(rawServers) as List<Object?>;
      // 逐条解析：一条坏记录只跳过那一条，不再让整份主机列表清零。
      final servers = <SshServer>[];
      for (final item in list) {
        if (item is! Map) continue;
        try {
          servers.add(SshServer.fromJson(item.cast<String, Object?>()));
        } on FormatException {
          continue;
        } on TypeError {
          continue;
        }
      }
      return ServerArchive(
        servers: servers,
        groupOrder: _readNames(rawGroups, 'order'),
        collapsedGroups: _readNames(rawGroups, 'collapsed').toSet(),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// 分组布局坏掉只丢布局，不影响主机本身。
  List<String> _readNames(String? raw, String field) {
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      final names = decoded[field];
      if (names is! List) return const [];
      return [
        for (final name in names)
          if (name is String) name,
      ];
    } on FormatException {
      return const [];
    }
  }

  @override
  Future<void> save(ServerArchive archive) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _serversKey,
      jsonEncode([for (final server in archive.servers) server.toJson()]),
    );
    await prefs.setString(
      _groupsKey,
      jsonEncode({
        'order': archive.groupOrder,
        'collapsed': archive.collapsedGroups.toList(),
      }),
    );
  }
}
