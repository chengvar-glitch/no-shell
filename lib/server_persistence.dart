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

/// 存档读取结果。刻意与「没有存档」分开：存档损坏时若按首次运行处理，
/// 紧接着的空列表落盘就把用户攒下的主机列表永久抹掉了。
sealed class ServerArchiveLoad {
  const ServerArchiveLoad();
}

/// 从未保存过（首次运行）。只有这种情况才允许写一份空基线。
final class ServerArchiveMissing extends ServerArchiveLoad {
  const ServerArchiveMissing();
}

/// 读到了完整存档。
final class ServerArchiveLoaded extends ServerArchiveLoad {
  const ServerArchiveLoaded(this.archive);

  final ServerArchive archive;
}

/// 存档存在但读不出来：要么解不开，要么两份记录只剩一份
/// （主机在、分组没了，或反过来）——都是丢过数据的信号。
///
/// 调用方必须据此停写存档：手头这份内存列表并不完整，落盘就等于
/// 拿残缺内容覆盖用户仅存的那份数据。
final class ServerArchiveUnreadable extends ServerArchiveLoad {
  const ServerArchiveUnreadable();
}

/// 主机与分组布局的落盘通道；内存中的唯一状态源仍是 ServerStore。
/// 测试可注入内存假实现。
abstract interface class ServerPersistence {
  /// 读取存档；三种结果见 [ServerArchiveLoad]。
  Future<ServerArchiveLoad> load();

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
  Future<ServerArchiveLoad> load() async {
    final String? rawServers;
    final String? rawGroups;
    try {
      final prefs = await SharedPreferences.getInstance();
      rawServers = prefs.getString(_serversKey);
      rawGroups = prefs.getString(_groupsKey);
    } catch (_) {
      // 读不到不等于没存过：钥匙串 / 存储层出问题时必须停写，
      // 否则一次瞬时故障就会把磁盘上的存档覆盖成空列表。
      return const ServerArchiveUnreadable();
    }
    if (rawServers == null) {
      // 分组布局还在、主机却没了，说明存档只丢了一半，不是首次运行。
      if (rawGroups != null) return const ServerArchiveUnreadable();
      return const ServerArchiveMissing();
    }
    try {
      final decoded = jsonDecode(rawServers);
      if (decoded is! List) return const ServerArchiveUnreadable();
      // 逐条解析：一条坏记录只跳过那一条，不再让整份主机列表清零。
      final servers = <SshServer>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          servers.add(SshServer.fromJson(item.cast<String, Object?>()));
        } on FormatException {
          continue;
        } on TypeError {
          continue;
        }
      }
      return ServerArchiveLoaded(
        ServerArchive(
          servers: servers,
          groupOrder: _readNames(rawGroups, 'order'),
          collapsedGroups: _readNames(rawGroups, 'collapsed').toSet(),
        ),
      );
    } on FormatException {
      return const ServerArchiveUnreadable();
    } on TypeError {
      return const ServerArchiveUnreadable();
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
