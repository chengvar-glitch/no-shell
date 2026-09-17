import 'dart:async';

import 'package:no_shell/models.dart';
import 'package:no_shell/ssh/local_files.dart';
import 'package:no_shell/ssh/sftp.dart';
import 'package:no_shell/ssh/ssh_transport.dart';
import 'package:xterm/core.dart';

/// 内存版 SFTP 文件系统：覆盖浏览、上传 / 下载与增删改的编排逻辑，
/// 不涉及真实网络。列表按目录存放，`rmdir` 与真实服务端一致地拒绝非空目录。
final class FakeSftpFileSystem implements SftpFileSystem {
  FakeSftpFileSystem({this.home = '/home/deploy'}) {
    listings['/'] = [];
    listings[home] = [];
  }

  final String home;

  /// 目录路径 → 子条目。
  final Map<String, List<SftpEntry>> listings = {};

  /// 远端文件内容。
  final Map<String, List<int>> contents = {};

  /// list 调用记录，用于断言刷新行为。
  final List<String> listCalls = [];

  /// 非 null 时 [list] 抛出该错误。
  SftpException? listError;

  /// 非 null 时 [list] 会一直挂着，直到测试主动 complete：
  /// 用来把面板钉在「载入中」那一帧上做布局断言。
  Completer<void>? listGate;

  /// 非 null 时 [write] 抛出该错误。
  SftpException? writeError;

  /// 读取分块大小，用于让下载产生多块进度回调。
  int chunkSize = 4;

  bool disposed = false;

  SftpEntry addFile(String dir, String name, {List<int>? content}) {
    final bytes = content ?? const [65, 66, 67, 68];
    final path = sftpJoin(dir, name);
    contents[path] = bytes;
    final entry = SftpEntry(
      name: name,
      path: path,
      isDirectory: false,
      size: bytes.length,
      modifiedAt: DateTime(2026),
    );
    listings.putIfAbsent(dir, () => []).add(entry);
    return entry;
  }

  SftpEntry addDirectory(String dir, String name) {
    final path = sftpJoin(dir, name);
    listings[path] = [];
    final entry = SftpEntry(
      name: name,
      path: path,
      isDirectory: true,
      modifiedAt: DateTime(2026),
    );
    listings.putIfAbsent(dir, () => []).add(entry);
    return entry;
  }

  /// 指向 [targetPath] 的符号链接。[follow] 模拟悬空之外的解析结果：
  /// 适配器层会对链接 stat 目标并把目录链接标成 isDirectory。
  SftpEntry addSymlink(String dir, String name, String targetPath) {
    final path = sftpJoin(dir, name);
    final target = listings[targetPath];
    final entry = SftpEntry(
      name: name,
      path: path,
      isDirectory: target != null,
      isSymlink: true,
      modifiedAt: DateTime(2026),
    );
    listings.putIfAbsent(dir, () => []).add(entry);
    return entry;
  }

  @override
  Future<String> homeDirectory() async => home;

  @override
  Future<List<SftpEntry>> list(String path) async {
    listCalls.add(path);
    final gate = listGate;
    if (gate != null) await gate.future;
    final error = listError;
    if (error != null) throw error;
    final entries = listings[path];
    if (entries == null) {
      throw const SftpException(SftpErrorKind.notFound);
    }
    return List.of(entries);
  }

  @override
  Stream<List<int>> read(String path) async* {
    final bytes = contents[path];
    if (bytes == null) throw const SftpException(SftpErrorKind.notFound);
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, bytes.length);
      yield bytes.sublist(offset, end);
    }
  }

  /// 指定目录当前的内容，便于断言「文件已出现在列表里」。
  List<SftpEntry> entriesOf(String dir) => List.of(listings[dir] ?? const []);

  @override
  Future<void> write(
    String path,
    Stream<List<int>> data, {
    void Function(int bytes)? onProgress,
  }) async {
    final buffer = <int>[];
    await for (final chunk in data) {
      buffer.addAll(chunk);
      onProgress?.call(buffer.length);
      final error = writeError;
      if (error != null) {
        // 模拟传输中途失败：半截文件已经落在远端。
        _store(path, buffer);
        throw error;
      }
    }
    _store(path, buffer);
  }

  @override
  Future<void> createDirectory(String path) async {
    if (listings.containsKey(path)) return;
    listings[path] = [];
    _upsert(sftpParent(path), sftpBaseName(path), 0, isDirectory: true);
  }

  @override
  Future<void> rename(String from, String to) async {
    final parent = sftpParent(from);
    final entries = listings[parent];
    final index = entries?.indexWhere((entry) => entry.path == from) ?? -1;
    if (index < 0) throw const SftpException(SftpErrorKind.notFound);
    final old = entries![index];
    final name = sftpBaseName(to);
    entries[index] = SftpEntry(
      name: name,
      path: to,
      isDirectory: old.isDirectory,
      isSymlink: old.isSymlink,
      size: old.size,
      modifiedAt: old.modifiedAt,
      permissions: old.permissions,
    );
    if (old.isDirectory) {
      _remapPrefix(from, to);
    } else if (contents.containsKey(from)) {
      contents[to] = contents.remove(from)!;
    }
  }

  @override
  Future<void> removeFile(String path) async {
    final entries = listings[sftpParent(path)];
    final index = entries?.indexWhere((entry) => entry.path == path) ?? -1;
    if (index < 0) throw const SftpException(SftpErrorKind.notFound);
    entries!.removeAt(index);
    contents.remove(path);
  }

  @override
  Future<void> removeDirectory(String path) async {
    final children = listings[path];
    if (children == null) throw const SftpException(SftpErrorKind.notFound);
    // 与真实 rmdir 一致：非空目录必须由调用方先清空。
    if (children.isNotEmpty) {
      throw const SftpException(SftpErrorKind.other, 'directory not empty');
    }
    listings.remove(path);
    listings[sftpParent(path)]?.removeWhere((entry) => entry.path == path);
  }

  @override
  void dispose() => disposed = true;

  void _store(String path, List<int> bytes) {
    contents[path] = bytes;
    _upsert(sftpParent(path), sftpBaseName(path), bytes.length);
  }

  void _upsert(
    String parent,
    String name,
    int size, {
    bool isDirectory = false,
  }) {
    final entries = listings.putIfAbsent(parent, () => []);
    final path = sftpJoin(parent, name);
    final index = entries.indexWhere((entry) => entry.path == path);
    final entry = SftpEntry(
      name: name,
      path: path,
      isDirectory: isDirectory,
      size: size,
      modifiedAt: DateTime(2026),
    );
    if (index < 0) {
      entries.add(entry);
    } else {
      entries[index] = entry;
    }
  }

  void _remapPrefix(String from, String to) {
    for (final key in listings.keys.toList()) {
      if (key == from || key.startsWith('$from/')) {
        listings[key.replaceFirst(from, to)] = listings.remove(key)!;
      }
    }
    for (final key in contents.keys.toList()) {
      if (key.startsWith('$from/')) {
        contents[key.replaceFirst(from, to)] = contents.remove(key)!;
      }
    }
  }
}

/// 假本地文件网关：上传源与下载落点都由测试直接指定，落盘内容记在内存里。
final class FakeLocalFileGateway implements LocalFileGateway {
  FakeLocalFileGateway();

  /// 下一次 [pickUploads] 返回的内容。
  List<LocalUpload> uploads = const [];

  /// 导出落点；为 null 表示用户取消。`share` 为 true 时模拟移动端
  /// 「写完要交给分享面板」那条分支。
  LocalDestination? exportDestination;

  /// 被交给分享面板的路径（按调用顺序）。
  final List<String> shared = [];

  /// 单文件下载的落点；为 null 表示用户取消。
  LocalTarget? downloadTarget;

  /// 多文件下载的落点；为 null 表示用户取消。
  List<LocalTarget>? downloadDirectory;

  /// 非 null 时 [pickUploads] 抛出该错误，模拟选择器不可用。
  Object? pickError;

  /// 非 null 时写入句柄在 close 时抛出该错误，模拟落盘失败。
  Object? writeError;

  /// 写入成功的本地文件内容。
  final Map<String, List<int>> written = {};

  /// 被丢弃的半成品路径。
  final List<String> discarded = [];

  /// 临时文件被改名到目标 (from → to) 的记录。
  final List<({String from, String to})> promoted = [];

  @override
  Future<List<LocalUpload>> pickUploads({String? confirmLabel}) async {
    final error = pickError;
    if (error != null) throw error;
    return uploads;
  }

  @override
  Future<LocalDestination?> pickExportDestination(
    String suggestedName, {
    String? confirmLabel,
  }) async => exportDestination;

  @override
  Future<void> shareLocalFile(String path, {String? title}) async {
    shared.add(path);
  }

  @override
  Future<LocalTarget?> pickDownloadTarget(
    String suggestedName, {
    String? confirmLabel,
  }) async => downloadTarget;

  @override
  Future<List<LocalTarget>?> pickDownloadDirectory(
    List<String> names, {
    String? confirmLabel,
  }) async => downloadDirectory;

  /// 收到过 ownerOnly 请求的路径（导出备份必须走这条）。
  final List<String> ownerOnlyWrites = [];

  @override
  LocalWriteHandle openWrite(String path, {bool ownerOnly = false}) {
    if (ownerOnly) ownerOnlyWrites.add(path);
    return _MemoryWriteHandle(
      (bytes) => written[path] = bytes,
      error: writeError,
    );
  }

  @override
  String temporaryPath(String path) => '$path.part';

  @override
  Future<void> promote(String temporaryPath, String targetPath) async {
    promoted.add((from: temporaryPath, to: targetPath));
    final bytes = written.remove(temporaryPath);
    if (bytes != null) written[targetPath] = bytes;
  }

  @override
  Future<void> discard(String path) async {
    discarded.add(path);
    written.remove(path);
  }

  /// 用内存句柄写出的字节（close 之后可读）。
  List<int> bytesOf(String path) => written[path] ?? const [];
}

/// 读取可手动放行的文件系统：把下载钉在「读到一半」那一帧上，
/// 好在传输中途取消 / 销毁队列。其余行为全部委托给 [FakeSftpFileSystem]。
final class GatedReadFileSystem implements SftpFileSystem {
  GatedReadFileSystem() : _inner = FakeSftpFileSystem();

  final FakeSftpFileSystem _inner;

  /// 首次拿到数据块时完成。
  final readStarted = Completer<void>();

  final _gate = Completer<void>();

  /// 放行被挂住的读取。
  void releaseRead() {
    if (!_gate.isCompleted) _gate.complete();
  }

  /// 通道是否已被关闭。
  bool get disposed => _inner.disposed;

  /// 委托给内部假文件系统：内容与目录都由它维护。
  SftpEntry addFile(String dir, String name, {List<int>? content}) =>
      _inner.addFile(dir, name, content: content);

  /// 按名字取一个已登记的文件条目。
  SftpEntry entryNamed(String name) => _inner.listings.values
      .expand((entries) => entries)
      .firstWhere((entry) => entry.name == name);

  @override
  Future<String> homeDirectory() => _inner.homeDirectory();

  @override
  Future<List<SftpEntry>> list(String path) => _inner.list(path);

  @override
  Stream<List<int>> read(String path) async* {
    await for (final chunk in _inner.read(path)) {
      if (!readStarted.isCompleted) readStarted.complete();
      await _gate.future;
      yield chunk;
    }
  }

  @override
  Future<void> write(
    String path,
    Stream<List<int>> data, {
    void Function(int bytes)? onProgress,
  }) => _inner.write(path, data, onProgress: onProgress);

  @override
  Future<void> createDirectory(String path) => _inner.createDirectory(path);

  @override
  Future<void> rename(String from, String to) => _inner.rename(from, to);

  @override
  Future<void> removeFile(String path) => _inner.removeFile(path);

  @override
  Future<void> removeDirectory(String path) => _inner.removeDirectory(path);

  @override
  void dispose() => _inner.dispose();
}

/// 目录载入可手动放行的文件系统：把控制器钉在 `isMutating` 那一帧上，
/// 用来验证「已有结构性操作在执行」时并发请求的行为。
final class GatedListFileSystem implements SftpFileSystem {
  GatedListFileSystem() : _inner = FakeSftpFileSystem();

  final FakeSftpFileSystem _inner;

  /// 首次进入 [list] 时完成（含 ensureReady 的那次，因此用后要 reset）。
  final listStarted = Completer<void>();

  final _gate = Completer<void>();

  /// 让 [list] 在下次调用时重新挂住。
  void arm() {
    _armed = true;
  }

  bool _armed = true;

  /// 放行被挂住的目录载入。
  void releaseList() {
    if (!_gate.isCompleted) _gate.complete();
  }

  SftpEntry addFile(String dir, String name, {List<int>? content}) =>
      _inner.addFile(dir, name, content: content);

  @override
  Future<String> homeDirectory() => _inner.homeDirectory();

  @override
  Future<List<SftpEntry>> list(String path) async {
    if (_armed) {
      _armed = false;
      if (!listStarted.isCompleted) listStarted.complete();
      await _gate.future;
    }
    return _inner.list(path);
  }

  @override
  Stream<List<int>> read(String path) => _inner.read(path);

  @override
  Future<void> write(
    String path,
    Stream<List<int>> data, {
    void Function(int bytes)? onProgress,
  }) => _inner.write(path, data, onProgress: onProgress);

  @override
  Future<void> createDirectory(String path) => _inner.createDirectory(path);

  @override
  Future<void> rename(String from, String to) => _inner.rename(from, to);

  @override
  Future<void> removeFile(String path) => _inner.removeFile(path);

  @override
  Future<void> removeDirectory(String path) => _inner.removeDirectory(path);

  @override
  void dispose() => _inner.dispose();
}

/// 收集写入字节、close 时回吐，模拟本地落盘。
final class _MemoryWriteHandle implements LocalWriteHandle {
  _MemoryWriteHandle(this._onClose, {this.error});

  final void Function(List<int> bytes) _onClose;

  /// 非 null 时 close 抛出该错误：对应「磁盘写满 / 无权限」这类落盘失败。
  final Object? error;

  final List<int> _bytes = [];

  @override
  void add(List<int> chunk) => _bytes.addAll(chunk);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    final failure = error;
    if (failure != null) throw failure;
    _onClose(_bytes);
  }
}

/// 假传输层：直接给出 [openSftp] 的结果，便于会话层与面板层测试。
final class FakeSftpTransport implements SshTransport {
  FakeSftpTransport({this.fileSystem, this.sftpError});

  final SftpFileSystem? fileSystem;

  /// 非 null 时 [openSftp] 抛出该错误（如服务端未启用 sftp 子系统）。
  final Object? sftpError;

  Terminal? attachedTerminal;
  bool disposed = false;
  int openSftpCalls = 0;

  @override
  Future<void> attach(
    Terminal terminal, {
    required void Function() onConnected,
    required void Function() onClosed,
  }) async {
    attachedTerminal = terminal;
    onConnected();
  }

  @override
  Future<SftpFileSystem> openSftp() async {
    openSftpCalls++;
    final error = sftpError;
    if (error != null) throw error;
    return fileSystem!;
  }

  @override
  void dispose() => disposed = true;
}

/// 测试用主机：id 必须在示例数据里，会话状态才能回写。
SshServer testServer({String id = 'srv-01'}) => SshServer(
  id: id,
  group: '生产环境',
  name: 'test-host',
  host: '10.0.0.1',
  username: 'root',
);
