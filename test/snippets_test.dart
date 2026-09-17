import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/snippets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 内存落盘通道：记录每次保存的快照，可配置读出损坏数据。
final class _MemorySnippetPersistence implements SnippetPersistence {
  _MemorySnippetPersistence();

  /// load() 返回的原始 JSON 串；null 表示从未保存过。
  String? savedRaw;

  /// save() 落下的最后一串。
  String? lastWrite;

  int writeCount = 0;

  @override
  Future<List<CommandSnippet>?> load() async {
    final raw = savedRaw;
    if (raw == null) return null;
    final decoded = jsonDecode(raw) as List<Object?>;
    return [
      for (final item in decoded)
        CommandSnippet.fromJson((item! as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<void> save(List<CommandSnippet> snippets) async {
    writeCount++;
    lastWrite = jsonEncode([for (final s in snippets) s.toJson()]);
    savedRaw = lastWrite;
  }
}

CommandSnippet _snippet(String name, [String command = 'echo hi']) =>
    CommandSnippet(id: 'snippet-$name', name: name, command: command);

void main() {
  group('SnippetStore', () {
    test('upsert 新增与更新，remove 删除，均按 id 判定', () {
      final store = SnippetStore();
      var notifications = 0;
      store.addListener(() => notifications++);

      store.upsert(_snippet('a', 'ls'));
      store.upsert(_snippet('b', 'pwd'));
      expect(store.snippets.map((s) => s.name), ['a', 'b']);

      store.upsert(_snippet('a', 'ls -la'));
      expect(store.snippets.first.command, 'ls -la');
      expect(store.snippets.length, 2);

      store.remove('snippet-b');
      expect(store.snippets.map((s) => s.name), ['a']);
      store.remove('missing');
      expect(store.snippets.length, 1);

      // 新增、更新、删除各通知一次；删不存在的条目不通知。
      expect(notifications, 3 + 1);
    });

    test('内容未变化时不通知', () {
      final store = SnippetStore(seed: [_snippet('a')]);
      var notifications = 0;
      store.addListener(() => notifications++);
      store.upsert(_snippet('a'));
      store.remove('missing');
      expect(notifications, 0);
    });

    test('load 载入已存片段；与当前一致时通知不多发', () async {
      final backend = _MemorySnippetPersistence()
        ..savedRaw = jsonEncode([_snippet('kept').toJson()]);
      final store = SnippetStore(
        persistence: backend,
        seed: [_snippet('kept')],
      );
      var notifications = 0;
      store.addListener(() => notifications++);
      await store.load();
      expect(store.snippets.map((s) => s.name), ['kept']);
      expect(notifications, 0);
    });

    test('load 出不同列表时替换内存并通知', () async {
      final backend = _MemorySnippetPersistence()
        ..savedRaw = jsonEncode([
          _snippet('x', 'uptime').toJson(),
          _snippet('y', 'df -h').toJson(),
        ]);
      final store = SnippetStore(persistence: backend, seed: [_snippet('old')]);
      await store.load();
      expect(store.snippets.map((s) => s.name), ['x', 'y']);
    });

    test('从未保存过时保持现状', () async {
      final store = SnippetStore(
        persistence: _MemorySnippetPersistence(),
        seed: [_snippet('seed')],
      );
      await store.load();
      expect(store.snippets.map((s) => s.name), ['seed']);
    });

    test('增删改后异步落盘，flush 等齐最后一次写入', () async {
      final backend = _MemorySnippetPersistence();
      final store = SnippetStore(persistence: backend);
      store.upsert(_snippet('a'));
      store.upsert(_snippet('b'));
      store.remove('snippet-a');
      await store.flush();
      expect(backend.writeCount, 3);
      expect(backend.lastWrite, contains('"b"'));
      expect(backend.lastWrite, isNot(contains('"a"')));
    });

    test('无落盘通道时 flush 直接完成', () async {
      final store = SnippetStore();
      store.upsert(_snippet('a'));
      await store.flush();
      expect(store.snippets, isNotEmpty);
    });
  });

  group('CommandSnippet 序列化', () {
    test('toJson / fromJson 往返', () {
      final snippet = _snippet('logs', 'tail -f /var/log/syslog');
      final restored = CommandSnippet.fromJson(
        (snippet.toJson()).cast<String, Object?>(),
      );
      expect(restored, snippet);
    });

    test('坏字段退回空串，不抛异常', () {
      final restored = CommandSnippet.fromJson(const {
        'id': 1,
        'name': null,
        'command': true,
      });
      expect(restored.id, '');
      expect(restored.name, '');
      expect(restored.command, '');
    });
  });

  group('SharedPreferencesSnippetPersistence', () {
    test('保存后可读回同一份列表', () async {
      SharedPreferences.setMockInitialValues(const {});
      final backend = SharedPreferencesSnippetPersistence();
      await backend.save([_snippet('a', 'ls'), _snippet('b', 'pwd')]);
      final loaded = await backend.load();
      expect(loaded, [_snippet('a', 'ls'), _snippet('b', 'pwd')]);
    });

    test('从未保存时返回 null', () async {
      SharedPreferences.setMockInitialValues(const {});
      final backend = SharedPreferencesSnippetPersistence();
      expect(await backend.load(), isNull);
    });

    test('坏 JSON 返回 null，坏条目被跳过', () async {
      SharedPreferences.setMockInitialValues(const {
        'command_snippets_v1': '{not json',
      });
      final backend = SharedPreferencesSnippetPersistence();
      expect(await backend.load(), isNull);

      // 实际存取的是 JSON 字符串，坏条目在解码后逐条跳过。
      SharedPreferences.setMockInitialValues({
        'command_snippets_v1': jsonEncode([
          {'id': 'ok', 'name': 'ok', 'command': 'ls'},
          'garbage',
          {'id': 'ok2', 'name': 'ok2', 'command': 'pwd'},
        ]),
      });
      final loaded = await SharedPreferencesSnippetPersistence().load();
      expect(loaded?.map((s) => s.id), ['ok', 'ok2']);
    });
  });

  group('SnippetScope', () {
    testWidgets('树上有作用域时取到同一个注册表', (tester) async {
      late SnippetStore resolved;
      SnippetStore? fallback;
      final store = SnippetStore();
      await tester.pumpWidget(
        SnippetScope(
          store: store,
          child: Builder(
            builder: (context) {
              resolved = SnippetScope.of(context);
              fallback = SnippetScope.maybeOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(identical(resolved, store), isTrue);
      expect(identical(fallback, store), isTrue);
    });
  });

  test('newId 不重复', () {
    final store = SnippetStore();
    final ids = {store.newId(), store.newId(), store.newId()};
    expect(ids.length, 3);
  });
}
