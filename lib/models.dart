/// 服务器数据模型与示例数据。
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

class ServerGroup {
  const ServerGroup({required this.name, required this.servers});

  final String name;
  final List<SshServer> servers;
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

/// 示例数据：连接状态一律从「未连接」开始，由真实 SSH 会话驱动，
/// 预置的状态只保留「最近连接」时间作展示。
final List<SshServer> mockServers = [
  SshServer(
    id: 'srv-01',
    group: '生产环境',
    name: 'web-prod-01',
    host: '10.0.1.11',
    username: 'deploy',
    tags: ['nginx', 'web'],
    lastConnectedAt: DateTime.now().subtract(const Duration(minutes: 26)),
    notes: '主站前端负载节点，变更需走审批流程。',
  ),
  SshServer(
    id: 'srv-02',
    group: '生产环境',
    name: 'web-prod-02',
    host: '10.0.1.12',
    username: 'deploy',
    tags: ['nginx', 'web'],
    lastConnectedAt: DateTime.now().subtract(const Duration(hours: 5)),
  ),
  SshServer(
    id: 'srv-03',
    group: '生产环境',
    name: 'api-gateway',
    host: '10.0.1.20',
    port: 2222,
    username: 'ops',
    authMethod: AuthMethod.password,
    tags: ['gateway', 'api'],
    lastConnectedAt: DateTime.now().subtract(const Duration(days: 2)),
  ),
  SshServer(
    id: 'srv-04',
    group: '开发 / 测试',
    name: 'db-primary',
    host: '10.0.2.31',
    username: 'root',
    tags: ['postgres'],
    lastConnectedAt: DateTime.now().subtract(const Duration(hours: 1)),
    notes: '测试库每晚 02:00 自动重建，勿存放重要数据。',
  ),
  SshServer(
    id: 'srv-05',
    group: '开发 / 测试',
    name: 'redis-cache',
    host: '10.0.2.32',
    username: 'root',
  ),
  SshServer(
    id: 'srv-06',
    group: '开发 / 测试',
    name: 'ci-runner',
    host: '10.0.2.40',
    username: 'ci',
    tags: ['jenkins'],
    lastConnectedAt: DateTime.now().subtract(const Duration(days: 9)),
  ),
  SshServer(
    id: 'srv-07',
    group: '个人服务器',
    name: 'nas-home',
    host: '192.168.1.10',
    username: 'admin',
    tags: ['nas', 'home'],
    lastConnectedAt: DateTime.now().subtract(const Duration(minutes: 3)),
  ),
  SshServer(
    id: 'srv-08',
    group: '个人服务器',
    name: 'vps-blog',
    host: '47.98.12.34',
    username: 'ubuntu',
    tags: ['blog'],
    lastConnectedAt: DateTime.now().subtract(const Duration(days: 30)),
  ),
];
