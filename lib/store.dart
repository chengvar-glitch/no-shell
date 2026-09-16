import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'server_persistence.dart';

/// 主机列表状态：桌面端与移动端共用。
/// 内存为唯一状态源；传入 [ServerPersistence] 时在增删改与「最近连接」
/// 变化后异步落盘。连接状态由 SessionManager 按真实 SSH 会话阶段回写。
class ServerStore extends ChangeNotifier {
  ServerStore({this.persistence, List<SshServer>? seed})
    : _servers = List.of(seed ?? const []);

  /// 主机列表落盘通道；null 表示仅内存（测试或嵌入场景）。
  final ServerPersistence? persistence;

  bool _loaded = false;

  final List<SshServer> _servers;

  List<SshServer> get servers => List.unmodifiable(_servers);

  /// 仅需要数量时使用，避免 [servers] 每次拷贝整个列表。
  int get serverCount => _servers.length;

  /// 启动时载入已保存的主机；首次运行（无存档）即为空列表。
  /// 不阻塞调用方：可 await 后再 runApp，也可以先出界面再等通知。
  Future<void> load() async {
    final backend = persistence;
    if (backend == null || _loaded) return;
    _loaded = true;
    final List<SshServer>? saved;
    try {
      saved = await backend.load();
    } catch (_) {
      return;
    }
    if (saved == null) {
      // 首次运行：写入空列表存档，保证之后变更都有完整基线。
      _schedulePersist();
      return;
    }
    _servers
      ..clear()
      ..addAll(saved);
    notifyListeners();
  }

  /// 落盘失败只降级为「本次改动未存档」，不打断 UI；下次变更会再次尝试。
  void _schedulePersist() {
    final backend = persistence;
    if (backend == null) return;
    unawaited(backend.save(_servers).catchError((_) {}));
  }

  SshServer? byId(String? id) {
    if (id == null) return null;
    for (final server in _servers) {
      if (server.id == id) return server;
    }
    return null;
  }

  /// 现有分组名（去重、保序），供表单下拉使用。
  List<String> get groupNames =>
      {for (final server in _servers) server.group}.toList();

  /// 按关键词过滤（名称 / 主机 / 用户名 / 分组 / 标签）并按分组归并。
  List<ServerGroup> groups({String query = ''}) {
    final q = query.trim().toLowerCase();
    final visible = q.isEmpty
        ? _servers
        : _servers
              .where(
                (s) =>
                    s.name.toLowerCase().contains(q) ||
                    s.host.toLowerCase().contains(q) ||
                    s.username.toLowerCase().contains(q) ||
                    s.group.toLowerCase().contains(q) ||
                    s.tags.any((t) => t.toLowerCase().contains(q)),
              )
              .toList();
    final map = <String, List<SshServer>>{};
    for (final server in visible) {
      map.putIfAbsent(server.group, () => []).add(server);
    }
    return [
      for (final entry in map.entries)
        ServerGroup(name: entry.key, servers: entry.value),
    ];
  }

  // ---- 会话状态回写，仅由 SessionManager 在会话阶段变化时调用 ----

  void markConnecting(String id) => _applyStatus(id, ServerStatus.connecting);

  void markConnected(String id) {
    final index = _servers.indexWhere((s) => s.id == id);
    // 已连接时直接跳过，避免重复通知下游整页重建。
    if (index == -1 || _servers[index].status == ServerStatus.connected) {
      return;
    }
    _servers[index] = _servers[index].copyWith(
      status: ServerStatus.connected,
      lastConnectedAt: DateTime.now(),
    );
    notifyListeners();
    _schedulePersist();
  }

  void markError(String id) => _applyStatus(id, ServerStatus.error);

  void markIdle(String id) => _applyStatus(id, ServerStatus.idle);

  void _applyStatus(String id, ServerStatus status) {
    final index = _servers.indexWhere((s) => s.id == id);
    if (index == -1 || _servers[index].status == status) return;
    _servers[index] = _servers[index].copyWith(status: status);
    notifyListeners();
  }

  /// 新增或按 id 更新。
  void upsert(SshServer server) {
    final index = _servers.indexWhere((s) => s.id == server.id);
    if (index == -1) {
      _servers.add(server);
    } else {
      _servers[index] = server;
    }
    notifyListeners();
    _schedulePersist();
  }

  /// 合并导入：地址+端口+用户 相同的条目视为已存在而跳过
  /// （列表内已有与导入内部重复都算），返回实际新增的实例；
  /// 无新增时不通知，避免下游整页重建。
  List<SshServer> importServers(Iterable<SshServer> candidates) {
    final known = <String>{for (final server in _servers) _importKeyOf(server)};
    final added = <SshServer>[];
    for (final server in candidates) {
      if (!known.add(_importKeyOf(server))) continue;
      _servers.add(server);
      added.add(server);
    }
    if (added.isNotEmpty) {
      notifyListeners();
      _schedulePersist();
    }
    return added;
  }

  String _importKeyOf(SshServer server) =>
      '${server.host}|${server.port}|${server.username}';

  /// 按 id 删除，返回原下标（-1 表示不存在），便于「撤销」。
  int remove(String id) {
    final index = _servers.indexWhere((s) => s.id == id);
    if (index != -1) {
      _servers.removeAt(index);
      notifyListeners();
      _schedulePersist();
    }
    return index;
  }

  void restore(SshServer server, int index) {
    _servers.insert(index.clamp(0, _servers.length), server);
    notifyListeners();
    _schedulePersist();
  }
}
