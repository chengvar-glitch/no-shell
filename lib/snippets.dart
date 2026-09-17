import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 命令片段：一段可以一键发往当前会话的常用命令（如 `tail -f /var/log/syslog`）。
/// 片段是全局的，不挂在某台主机上——常用命令跨主机通用，按主机会越分越碎。
@immutable
final class CommandSnippet {
  const CommandSnippet({
    required this.id,
    required this.name,
    required this.command,
  });

  final String id;
  final String name;
  final String command;

  CommandSnippet copyWith({String? name, String? command}) => CommandSnippet(
    id: id,
    name: name ?? this.name,
    command: command ?? this.command,
  );

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'command': command};

  factory CommandSnippet.fromJson(Map<String, Object?> json) => CommandSnippet(
    id: switch (json['id']) {
      final String value => value,
      _ => '',
    },
    name: switch (json['name']) {
      final String value => value,
      _ => '',
    },
    command: switch (json['command']) {
      final String value => value,
      _ => '',
    },
  );

  @override
  bool operator ==(Object other) =>
      other is CommandSnippet &&
      other.id == id &&
      other.name == name &&
      other.command == command;

  @override
  int get hashCode => Object.hash(id, name, command);
}

/// 片段落盘通道；测试注入内存假实现。
abstract interface class SnippetPersistence {
  /// 读取已保存的片段；从未保存过返回 null。存档损坏同样返回 null，
  /// 由调用方按空列表起步，下次保存覆盖为干净数据。
  Future<List<CommandSnippet>?> load();

  Future<void> save(List<CommandSnippet> snippets);
}

/// 基于 shared_preferences 的 JSON 实现，六个平台均可用（web 为 localStorage）。
/// 片段里只有用户自己写的名字与命令，不含任何凭据。
final class SharedPreferencesSnippetPersistence implements SnippetPersistence {
  static const _key = 'command_snippets_v1';

  @override
  Future<List<CommandSnippet>?> load() async {
    final String? raw;
    try {
      final prefs = await SharedPreferences.getInstance();
      raw = prefs.getString(_key);
    } catch (_) {
      return null;
    }
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return [
        // 一条坏数据只跳过那一条，不带走整份列表。
        for (final item in decoded)
          if (item is Map)
            CommandSnippet.fromJson(item.cast<String, Object?>()),
      ];
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Future<void> save(List<CommandSnippet> snippets) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode([for (final snippet in snippets) snippet.toJson()]),
      );
    } on FormatException {
      return;
    } on TypeError {
      return;
    } catch (_) {
      return;
    }
  }
}

/// 命令片段注册表：内存为唯一状态源，传入 [SnippetPersistence] 时
/// 在增删改后异步落盘（与 [ServerStore] 相同的链式串行写，杜绝乱序覆盖）。
final class SnippetStore extends ChangeNotifier {
  SnippetStore({this.persistence, List<CommandSnippet>? seed})
    : _snippets = List.of(seed ?? const []);

  final SnippetPersistence? persistence;

  final List<CommandSnippet> _snippets;

  List<CommandSnippet> get snippets => List.unmodifiable(_snippets);

  bool _loaded = false;

  Future<void> _pendingSave = Future<void>.value();

  /// 等待排队中的落盘全部写完；退出前补一次，保证最后的改动不丢。
  Future<void> flush() => _pendingSave;

  /// 启动时载入已保存的片段；可 await 后再 runApp，也可以先出界面再等通知。
  Future<void> load() async {
    final backend = persistence;
    if (backend == null || _loaded) return;
    _loaded = true;
    final List<CommandSnippet>? saved;
    try {
      saved = await backend.load();
    } catch (_) {
      return;
    }
    if (saved == null) return;
    if (_sameAs(saved)) return;
    _snippets
      ..clear()
      ..addAll(saved);
    notifyListeners();
  }

  /// 内容与顺序都一致时不算变化，避免启动期无谓的通知。
  bool _sameAs(List<CommandSnippet> other) {
    if (other.length != _snippets.length) return false;
    for (var i = 0; i < other.length; i++) {
      if (other[i] != _snippets[i]) return false;
    }
    return true;
  }

  /// 新增或按 id 更新；内容与位置都没变时不通知、不落盘。
  void upsert(CommandSnippet snippet) {
    final index = _snippets.indexWhere((item) => item.id == snippet.id);
    if (index == -1) {
      _snippets.add(snippet);
    } else if (_snippets[index] == snippet) {
      return;
    } else {
      _snippets[index] = snippet;
    }
    notifyListeners();
    _schedulePersist();
  }

  /// 按 id 删除；不存在时是空操作。
  void remove(String id) {
    final index = _snippets.indexWhere((item) => item.id == id);
    if (index == -1) return;
    _snippets.removeAt(index);
    notifyListeners();
    _schedulePersist();
  }

  void _schedulePersist() {
    final backend = persistence;
    if (backend == null) return;
    // 快照后再交给异步落盘：编码发生在 await 之后，不能把可变列表交出去。
    final snapshot = List.of(_snippets);
    _pendingSave = _pendingSave
        .then((_) => backend.save(snapshot))
        .catchError((_) {});
  }

  String newId() => 'snippet-${DateTime.now().microsecondsSinceEpoch}';
}

/// 命令片段作用域：包住 MaterialApp 的内容，任意层级的终端视图与弹窗
/// 都能拿到同一个 [SnippetStore]，免去逐层透传。
final class SnippetScope extends InheritedWidget {
  const SnippetScope({super.key, required this.store, required super.child});

  final SnippetStore store;

  /// 作用域不在树上（测试直接渲染局部组件）时返回 null，由调用方降级：
  /// 片段入口直接不出现，而不是让整个终端打不开。
  static SnippetStore? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SnippetScope>()?.store;

  static SnippetStore of(BuildContext context) =>
      maybeOf(context) ??
      (throw FlutterError('No SnippetScope found in context'));

  @override
  bool updateShouldNotify(SnippetScope oldWidget) => oldWidget.store != store;
}
