/// 服务器数据模型。
library;

import 'l10n/generated/app_localizations.dart';

enum ServerStatus { connected, connecting, idle, error }

enum AuthMethod { password, privateKey }

/// 认证方式的本地化展示名。
String authMethodLabel(AppLocalizations l10n, AuthMethod method) =>
    method == AuthMethod.password ? l10n.authPassword : l10n.authKey;

class SshServer {
  const SshServer({
    required this.id,
    required this.group,
    required this.name,
    required this.host,
    required this.username,
    this.port = 22,
    this.authMethod = AuthMethod.privateKey,
    this.status = ServerStatus.idle,
    this.tags = const [],
    this.notes,
    this.lastConnectedAt,
  });

  final String id;
  final String group;
  final String name;
  final String host;
  final String username;
  final int port;
  final AuthMethod authMethod;
  final ServerStatus status;
  final List<String> tags;
  final String? notes;
  final DateTime? lastConnectedAt;

  String get account => '$username@$host';

  SshServer copyWith({
    String? group,
    String? name,
    String? host,
    String? username,
    int? port,
    AuthMethod? authMethod,
    ServerStatus? status,
    String? notes,
    DateTime? lastConnectedAt,
  }) {
    return SshServer(
      id: id,
      group: group ?? this.group,
      name: name ?? this.name,
      host: host ?? this.host,
      username: username ?? this.username,
      port: port ?? this.port,
      authMethod: authMethod ?? this.authMethod,
      status: status ?? this.status,
      tags: tags,
      notes: notes ?? this.notes,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }

  /// 持久化用序列化；status 是运行时状态，不入档，载入后统一回到 idle。
  Map<String, Object?> toJson() => {
    'id': id,
    'group': group,
    'name': name,
    'host': host,
    'username': username,
    'port': port,
    'authMethod': authMethod.name,
    'tags': tags,
    if (notes != null) 'notes': notes,
    if (lastConnectedAt != null)
      'lastConnectedAt': lastConnectedAt!.toIso8601String(),
  };

  factory SshServer.fromJson(Map<String, Object?> json) => SshServer(
    id: json['id'] as String,
    group: (json['group'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    host: (json['host'] as String?) ?? '',
    username: (json['username'] as String?) ?? '',
    port: (json['port'] as num?)?.toInt() ?? 22,
    authMethod:
        AuthMethod.values.asNameMap()[json['authMethod']] ??
        AuthMethod.privateKey,
    tags: [
      for (final tag in (json['tags'] as List<Object?>? ?? const []))
        tag as String,
    ],
    notes: json['notes'] as String?,
    lastConnectedAt: switch (json['lastConnectedAt']) {
      final String iso => DateTime.tryParse(iso),
      _ => null,
    },
  );
}

/// 渲染用的分组视图：名字 + 成员 + 折叠态。
/// 名字是分组的身份（[SshServer.group] 存的就是它），顺序与折叠态由 ServerStore 持有。
class ServerGroup {
  const ServerGroup({
    required this.name,
    required this.servers,
    this.collapsed = false,
  });

  final String name;
  final List<SshServer> servers;
  final bool collapsed;
}

/// 相对时间展示：主机「最近连接」与 SFTP「修改时间」共用。
String formatRelativeTime(AppLocalizations l10n, DateTime? time) {
  if (time == null) return l10n.neverConnected;
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return l10n.justNow;
  if (diff.inMinutes < 60) return l10n.minutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.hoursAgo(diff.inHours);
  if (diff.inDays < 7) return l10n.daysAgo(diff.inDays);
  final y = time.year.toString().padLeft(4, '0');
  final m = time.month.toString().padLeft(2, '0');
  final d = time.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
