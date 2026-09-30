import 'package:no_shell/ssh/host_key_store.dart';

/// 内存版主机指纹存储，供测试注入。
final class FakeHostKeyStore implements HostKeyStore {
  final Map<String, List<HostKeyRecord>> _records = {};

  /// 非 null 时 [load] 返回 [HostKeysUnavailable]，模拟存储层故障。
  bool unavailable = false;

  /// 非 null 时 [load] 直接抛出，模拟底层抛异常。
  Object? loadError;

  /// true 时 [save] 写不进去（返回 false，且不留记录），模拟存储写失败。
  bool saveFails = false;

  /// 非 null 时 [save] 直接抛出，模拟底层写操作抛异常。
  Object? saveError;

  String _key(String host, int port) => '$host:$port';

  List<HostKeyRecord> records(String host, int port) =>
      List.unmodifiable(_records[_key(host, port)] ?? const []);

  @override
  Future<HostKeyLoad> load(String host, int port) async {
    final error = loadError;
    if (error != null) throw error;
    if (unavailable) return const HostKeysUnavailable();
    final stored = _records[_key(host, port)];
    return stored == null
        ? const HostKeysNeverRecorded()
        : HostKeysLoaded(List.unmodifiable(stored));
  }

  @override
  Future<bool> save(String host, int port, HostKeyRecord record) async {
    final error = saveError;
    if (error != null) throw error;
    if (saveFails) return false;
    final stored = _records.putIfAbsent(_key(host, port), () => []);
    if (!stored.contains(record)) stored.add(record);
    return true;
  }

  @override
  Future<void> delete(String host, int port) async {
    _records.remove(_key(host, port));
  }
}
