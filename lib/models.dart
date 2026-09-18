/// 服务器数据模型。
library;

import 'l10n/generated/app_localizations.dart';

enum ServerStatus { connected, connecting, idle, error }

enum AuthMethod { password, privateKey, agent }

/// 认证方式的本地化展示名。
String authMethodLabel(AppLocalizations l10n, AuthMethod method) =>
    switch (method) {
      AuthMethod.password => l10n.authPassword,
      AuthMethod.privateKey => l10n.authKey,
      AuthMethod.agent => l10n.authAgent,
    };

/// 端口转发的三个方向，与 `ssh -L` / `-R` / `-D` 一一对应。
enum PortForwardMode {
  /// 本地转发（-L）：本机监听 [PortForwardRule.localHost]:[PortForwardRule.localPort]，
  /// 连接经 SSH 服务器转给 [PortForwardRule.remoteHost]:[PortForwardRule.remotePort]。
  local,

  /// 远程转发（-R）：让 SSH 服务器监听
  /// [PortForwardRule.remoteHost]:[PortForwardRule.remotePort]，
  /// 连接转回本机的 [PortForwardRule.localHost]:[PortForwardRule.localPort]。
  remote,

  /// 动态转发（-D）：本机起一个 SOCKS5 代理，目标由客户端逐次指定，
  /// 因此这条规则只用得上 [PortForwardRule.localHost] 与 [PortForwardRule.localPort]。
  dynamic,
}

/// 监听地址是否是回环：只有本机能连上。
///
/// 不是回环（`0.0.0.0`、局域网地址、公网地址）意味着同一网络里的任何人都能
/// 连上这条隧道，而 `-D` 在那种情况下就是一个**不需要认证**的 SOCKS5 代理。
/// 界面据此在保存前提示用户，别让一次手滑把本机服务暴露出去。
///
/// 判定只认字面量，不做 DNS 解析：解析结果随网络环境变化，界面上的提示
/// 必须与用户填的内容一一对应，也不能因为一次解析把别的地址放进来。
bool isLoopbackHost(String host) {
  final value = host.trim().toLowerCase();
  if (value == 'localhost') return true;
  // IPv6 回环可以写成全零省略形式，也可能带方括号或 IPv4 映射前缀。
  final bare = value.replaceAll(RegExp(r'^\[|\]$'), '');
  if (bare == '::1' || bare == '0:0:0:0:0:0:0:1') return true;
  if (bare == '::ffff:127.0.0.1') return true;
  return RegExp(r'^127(\.\d{1,3}){3}$').hasMatch(bare);
}

/// 一条端口转发规则：挂在某台主机上，随该主机的会话启停。
///
/// 规则本身是可以为空的目标地址等留白，运行前的校验交给 [isRunnable]；
/// 存进存档的是同一份结构，字段名即 JSON key。
class PortForwardRule {
  const PortForwardRule({
    required this.id,
    required this.mode,
    this.localHost = '127.0.0.1',
    this.localPort = 0,
    this.remoteHost = '127.0.0.1',
    this.remotePort = 0,
    this.autoStart = false,
  });

  final String id;
  final PortForwardMode mode;

  /// 本地侧地址：本地 / 动态转发是监听地址，远程转发是本地目标地址。
  final String localHost;

  /// 本地侧端口；0 表示端口无效（未填或越界）。
  final int localPort;

  /// 远端侧地址：本地转发是目标地址，远程转发是服务端监听地址。
  final String remoteHost;

  /// 远端侧端口；0 表示由服务端自行分配（仅远程转发允许）或未填。
  final int remotePort;

  /// 建立会话后是否自动启动这条转发。
  final bool autoStart;

  /// 规则是否填全、可以启动。
  ///
  /// 逐个模式判定，不做「统一取交集」：动态转发根本不用远端地址，
  /// 拿它的空值去卡这条规则，用户会看到一条填得挺好的规则怎么都开不了。
  /// 远程转发允许远端端口 0——那是「让服务端挑一个空闲端口」，不是没填。
  bool get isRunnable {
    if (localHost.trim().isEmpty || !_portInRange(localPort)) return false;
    return switch (mode) {
      PortForwardMode.dynamic => true,
      PortForwardMode.local =>
        remoteHost.trim().isNotEmpty && _portInRange(remotePort),
      PortForwardMode.remote =>
        remoteHost.trim().isNotEmpty && remotePort >= 0 && remotePort <= 65535,
    };
  }

  static bool _portInRange(int port) => port > 0 && port <= 65535;

  PortForwardRule copyWith({
    PortForwardMode? mode,
    String? localHost,
    int? localPort,
    String? remoteHost,
    int? remotePort,
    bool? autoStart,
  }) => PortForwardRule(
    id: id,
    mode: mode ?? this.mode,
    localHost: localHost ?? this.localHost,
    localPort: localPort ?? this.localPort,
    remoteHost: remoteHost ?? this.remoteHost,
    remotePort: remotePort ?? this.remotePort,
    autoStart: autoStart ?? this.autoStart,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'mode': mode.name,
    'localHost': localHost,
    'localPort': localPort,
    'remoteHost': remoteHost,
    'remotePort': remotePort,
    if (autoStart) 'autoStart': true,
  };

  factory PortForwardRule.fromJson(Map<String, Object?> json) =>
      PortForwardRule(
        id: (json['id'] as String?) ?? '',
        // 认不出的模式退回本地转发：它是三者里最保守的一个（只监听回环、
        // 只连用户在规则里写死的目标），不会因为一条脏数据开出一个代理。
        mode:
            PortForwardMode.values.asNameMap()[json['mode']] ??
            PortForwardMode.local,
        localHost: (json['localHost'] as String?) ?? '127.0.0.1',
        localPort: (json['localPort'] as num?)?.toInt() ?? 0,
        remoteHost: (json['remoteHost'] as String?) ?? '127.0.0.1',
        remotePort: (json['remotePort'] as num?)?.toInt() ?? 0,
        autoStart: json['autoStart'] == true,
      );

  @override
  bool operator ==(Object other) =>
      other is PortForwardRule &&
      other.id == id &&
      other.mode == mode &&
      other.localHost == localHost &&
      other.localPort == localPort &&
      other.remoteHost == remoteHost &&
      other.remotePort == remotePort &&
      other.autoStart == autoStart;

  @override
  int get hashCode => Object.hash(
    id,
    mode,
    localHost,
    localPort,
    remoteHost,
    remotePort,
    autoStart,
  );
}

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
    this.jumpServerId,
    this.forwards = const [],
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

  /// 跳板机：另一台已保存主机的 id，连接本机时先连它、再经它转发到本机。
  /// 存 id 而不是地址：跳板机自己也有端口、用户名与凭据，复制一份必然会走样。
  final String? jumpServerId;

  /// 挂在这台主机上的端口转发规则；规则本身是静态配置，启停状态在运行时。
  final List<PortForwardRule> forwards;

  String get account => '$username@$host';

  /// 列表副标题：默认端口 22 不写出来，非默认端口才附在账号后面。
  String get accountWithPort => port == 22 ? account : '$account:$port';

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
    String? jumpServerId,
    List<PortForwardRule>? forwards,
    // copyWith 的 `??` 无法表达「把它清掉」，而跳板机是可以取消的，
    // 因此单独给一个显式开关，避免「取消跳板机」变成无声的空操作。
    bool clearJumpServer = false,
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
      jumpServerId: clearJumpServer
          ? null
          : (jumpServerId ?? this.jumpServerId),
      forwards: forwards ?? this.forwards,
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
    if (jumpServerId != null) 'jumpServerId': jumpServerId,
    if (forwards.isNotEmpty)
      'forwards': [for (final rule in forwards) rule.toJson()],
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
    jumpServerId: switch (json['jumpServerId']) {
      final String id when id.isNotEmpty => id,
      _ => null,
    },
    // 一条坏规则只跳过那一条：转发规则是附加配置，不该带走整台主机。
    forwards: [
      for (final item in (json['forwards'] as List<Object?>? ?? const []))
        if (item is Map) PortForwardRule.fromJson(item.cast<String, Object?>()),
    ],
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
