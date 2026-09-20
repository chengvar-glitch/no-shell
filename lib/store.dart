import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'server_persistence.dart';

/// 主机列表与分组布局状态：桌面端与移动端共用。
/// 内存为唯一状态源；传入 [ServerPersistence] 时在增删改、分组变更与
/// 「最近连接」变化后异步落盘。连接状态由 SessionManager 按真实 SSH 会话阶段回写。
///
/// 分组以「名字」为身份：[SshServer.group] 存的就是分组名，主机序列化格式
/// 因此不变，旧存档直接可读；分组自身的顺序与折叠态由本类持有的注册表维护，
/// 空分组、重命名、排序这些能力都建立在这张表上。
class ServerStore extends ChangeNotifier {
  ServerStore({this.persistence, List<SshServer>? seed})
    : _servers = List.of(seed ?? const []) {
    _syncGroups();
  }

  /// 主机列表落盘通道；null 表示仅内存（测试或嵌入场景）。
  final ServerPersistence? persistence;

  bool _loaded = false;

  /// 存档存在但读不出来：主机列表可能只读到了一部分。
  /// 置位后停写存档，避免拿残缺列表覆盖用户仅存的那份数据。
  bool _archiveUnreadable = false;

  /// 存档不可读，界面据此给出提示；此时的改动不会被落盘。
  bool get archiveUnreadable => _archiveUnreadable;

  final List<SshServer> _servers;

  /// 分组注册表：顺序即展示顺序，空分组也留在这里。
  final List<String> _groupOrder = [];

  /// 折叠的分组名；跨重启、跨端都记住。
  final Set<String> _collapsedGroups = {};

  List<SshServer> get servers => List.unmodifiable(_servers);

  /// 仅需要数量时使用，避免 [servers] 每次拷贝整个列表。
  int get serverCount => _servers.length;

  /// 启动时载入已保存的主机；首次运行（无存档）即为空列表。
  /// 不阻塞调用方：可 await 后再 runApp，也可以先出界面再等通知。
  Future<void> load() async {
    final backend = persistence;
    if (backend == null || _loaded) return;
    _loaded = true;
    final ServerArchiveLoad result;
    try {
      result = await backend.load();
    } catch (_) {
      // 读失败一律停写：手头的空列表不是用户数据，覆盖上去就没了。
      _archiveUnreadable = true;
      return;
    }
    switch (result) {
      case ServerArchiveMissing():
        // 确认是首次运行：写入空列表存档，保证之后变更都有完整基线。
        _schedulePersist();
        return;
      case ServerArchiveUnreadable():
        _archiveUnreadable = true;
        return;
      case ServerArchiveLoaded(:final archive):
        _servers
          ..clear()
          ..addAll(archive.servers);
        _groupOrder
          ..clear()
          ..addAll(archive.groupOrder);
        _collapsedGroups
          ..clear()
          ..addAll(archive.collapsedGroups);
        // 旧存档没有分组布局，或缺了某台主机所属的分组名：按出现次序补齐。
        _syncGroups();
        notifyListeners();
    }
  }

  /// 落盘失败只降级为「本次改动未存档」，不打断 UI；下次变更会再次尝试。
  /// 写入串成一条链：连续变更时后一次必然覆盖前一次，不会因为异步完成顺序
  /// 颠倒而让旧快照最后落盘（折叠 / 排序连着改就是这种节奏）。
  void _schedulePersist() {
    final backend = persistence;
    if (backend == null) return;
    // 存档读不出来时停写：当前内存列表是残缺的（甚至就是空的），
    // 落盘等于把用户仅存的那份数据抹掉。宁可这次改动不存档。
    if (_archiveUnreadable) return;
    // 快照后再交给异步落盘：编码发生在 await 之后，不能把可变列表交出去。
    final archive = ServerArchive(
      servers: List.of(_servers),
      groupOrder: List.of(_groupOrder),
      collapsedGroups: Set.of(_collapsedGroups),
    );
    _pendingSave = _pendingSave
        .then((_) => backend.save(archive))
        .catchError((_) {});
  }

  Future<void> _pendingSave = Future<void>.value();

  /// 等待排队中的落盘全部写完。
  ///
  /// 退出前必须调一次：落盘是「链在一条 future 上」异步跑的，进程直接
  /// 退出会把最后一次改动丢掉（用户刚改完分组就关窗就是这种节奏）。
  Future<void> flush() => _pendingSave;

  SshServer? byId(String? id) {
    if (id == null) return null;
    for (final server in _servers) {
      if (server.id == id) return server;
    }
    return null;
  }

  /// 分组注册表（去重、保序），供列表渲染与表单候选使用。
  List<String> get groupNames => List.unmodifiable(_groupOrder);

  /// 把主机上出现、注册表里还没有的分组名按出现次序补进来。
  /// 没有任何分组名被落下时是空操作，因此可以在渲染前无条件调用。
  void _syncGroups() {
    for (final server in _servers) {
      _register(server.group);
    }
  }

  void _register(String name) {
    if (name.isEmpty || _groupOrder.contains(name)) return;
    _groupOrder.add(name);
  }

  /// 新建（可以是空的）分组；空名或重名返回 false。
  bool createGroup(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _groupOrder.contains(trimmed)) return false;
    _groupOrder.add(trimmed);
    _changed();
    return true;
  }

  /// 重命名分组，成员主机一并改到新名下；空名或与其它分组重名返回 false。
  bool renameGroup(String from, String to) {
    final index = _groupOrder.indexOf(from);
    if (index == -1) return false;
    final trimmed = to.trim();
    if (trimmed == from) return true;
    if (trimmed.isEmpty || _groupOrder.contains(trimmed)) return false;
    _groupOrder[index] = trimmed;
    for (var i = 0; i < _servers.length; i++) {
      if (_servers[i].group == from) {
        _servers[i] = _servers[i].copyWith(group: trimmed);
      }
    }
    if (_collapsedGroups.remove(from)) _collapsedGroups.add(trimmed);
    _changed();
    return true;
  }

  /// 删除分组。组内还有主机时必须给出 [moveTo]（另一个已存在的分组名），
  /// 主机整体迁过去；给不出目的地就返回 false，避免主机变成孤儿。
  bool deleteGroup(String name, {String? moveTo}) {
    final index = _groupOrder.indexOf(name);
    if (index == -1) return false;
    final target = moveTo?.trim() ?? '';
    if (_servers.any((server) => server.group == name)) {
      if (target.isEmpty || target == name || !_groupOrder.contains(target)) {
        return false;
      }
      for (var i = 0; i < _servers.length; i++) {
        if (_servers[i].group == name) {
          _servers[i] = _servers[i].copyWith(group: target);
        }
      }
    }
    _groupOrder.removeAt(index);
    _collapsedGroups.remove(name);
    _changed();
    return true;
  }

  /// 分组排序：把 [name] 上移 / 下移一位（[delta] 为 ±1），到头返回 false。
  bool moveGroup(String name, int delta) {
    final index = _groupOrder.indexOf(name);
    final target = index + delta;
    if (index == -1 || target < 0 || target >= _groupOrder.length) {
      return false;
    }
    _groupOrder
      ..removeAt(index)
      ..insert(target, name);
    _changed();
    return true;
  }

  /// 折叠 / 展开分组；状态落盘，重启与另一端都记得。
  void setGroupCollapsed(String name, bool collapsed) {
    final changed = collapsed
        ? _collapsedGroups.add(name)
        : _collapsedGroups.remove(name);
    if (!changed) return;
    _changed();
  }

  void _changed() {
    notifyListeners();
    _schedulePersist();
  }

  /// 按关键词过滤（名称 / 主机 / 用户名 / 分组 / 标签），按注册表顺序输出分组。
  /// 分组为空时平时照样显示（用户刚建的分组看得见），搜索时只留有命中的分组。
  List<ServerGroup> groups({String query = ''}) {
    // 渲染前补一次注册表：无论如何都不让某台主机因为分组名没入册而消失。
    _syncGroups();
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
    final groups = <ServerGroup>[];
    for (final name in _groupOrder) {
      final members = map[name] ?? const <SshServer>[];
      if (members.isEmpty && q.isNotEmpty) continue;
      groups.add(
        ServerGroup(
          name: name,
          servers: members,
          collapsed: _collapsedGroups.contains(name),
        ),
      );
    }
    return groups;
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
    _register(server.group);
    final index = _servers.indexWhere((s) => s.id == server.id);
    if (index == -1) {
      _servers.add(server);
    } else {
      // status 是会话层维护的运行时状态，编辑表单从零拼的实例不带它，更新时沿用原值，
      // 否则改个备注就把已连接的主机打回「未连接」。
      _servers[index] = server.copyWith(status: _servers[index].status);
    }
    _changed();
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
      // 导入文本自带分组：新分组名一并入册，导入后立刻能在列表里看到。
      _register(server.group);
    }
    if (added.isNotEmpty) _changed();
    return added;
  }

  String _importKeyOf(SshServer server) =>
      '${server.host}|${server.port}|${server.username}';

  /// 按 id 删除，返回原下标（-1 表示不存在），便于「撤销」。
  /// 不顺手删掉空分组：分组是用户显式建的，留着他自己决定。
  int remove(String id) {
    final index = _servers.indexWhere((s) => s.id == id);
    if (index != -1) {
      _servers.removeAt(index);
      _changed();
    }
    return index;
  }

  void restore(SshServer server, int index) {
    _servers.insert(index.clamp(0, _servers.length), server);
    _register(server.group);
    _changed();
  }
}
