import 'package:no_shell/ssh/host_key_store.dart';

/// 内存版主机指纹存储，供测试注入。
final class FakeHostKeyStore implements HostKeyStore {
  final Map<String, String> _records = {};

  String _key(String host, int port) => '$host:$port';

  String? peek(String host, int port) => _records[_key(host, port)];

  @override
  Future<String?> load(String host, int port) async =>
      _records[_key(host, port)];

  @override
  Future<void> save(String host, int port, String record) async {
    _records[_key(host, port)] = record;
  }

  @override
  Future<void> delete(String host, int port) async {
    _records.remove(_key(host, port));
  }
}
