import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'sftp.dart';

/// dartssh2 实现：把 [SftpClient] 的接口翻译成领域层的 [SftpFileSystem]，
/// 并把底层错误统一归类为 [SftpException]，视图层无需感知具体异常类型。
final class DartSsh2SftpFileSystem implements SftpFileSystem {
  DartSsh2SftpFileSystem(this._client);

  final SftpClient _client;
  bool _disposed = false;

  @override
  Future<String> homeDirectory() => _guard(() => _client.absolute('.'));

  @override
  Future<List<SftpEntry>> list(String path) => _guard(() async {
    final names = await _client.listdir(path);
    final entries = await Future.wait(
      names
          // readdir 会把 `.` / `..` 一并返回，由界面提供「上级目录」入口。
          .where((name) => name.filename != '.' && name.filename != '..')
          .map((name) => _toEntry(path, name)),
    );
    entries.sort((a, b) => a.name.compareTo(b.name));
    return entries;
  });

  @override
  Stream<List<int>> read(String path) async* {
    final SftpFile file;
    try {
      file = await _client.open(path);
    } catch (error) {
      throw sftpErrorFrom(error);
    }
    try {
      await for (final chunk in file.read()) {
        yield chunk;
      }
    } catch (error) {
      throw sftpErrorFrom(error);
    } finally {
      // 取消订阅（用户取消下载）时同样走到这里，句柄必须归还。
      await file.close();
    }
  }

  @override
  Future<void> write(
    String path,
    Stream<List<int>> data, {
    void Function(int bytes)? onProgress,
  }) => _guard(() async {
    final file = await _client.open(
      path,
      mode:
          SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );
    try {
      // 源流报错（取消上传）会沿 done future 抛出，写入随即停止。
      final writer = file.write(
        data.map(
          (chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
        ),
        onProgress: onProgress,
      );
      await writer.done;
    } finally {
      await file.close();
    }
  });

  @override
  Future<void> createDirectory(String path) =>
      _guard(() => _client.mkdir(path));

  @override
  Future<void> rename(String from, String to) =>
      _guard(() => _client.rename(from, to));

  @override
  Future<void> removeFile(String path) => _guard(() => _client.remove(path));

  @override
  Future<void> removeDirectory(String path) =>
      _guard(() => _client.rmdir(path));

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // 只关 SFTP 通道，SSH 连接仍由会话 / 传输层持有。
    unawaited(_client.close());
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (error) {
      throw sftpErrorFrom(error);
    }
  }

  Future<SftpEntry> _toEntry(String dir, SftpName name) async {
    final mode = name.attr.mode;
    var isDirectory = mode?.type == SftpFileType.directory;
    final isSymlink = mode?.type == SftpFileType.symbolicLink;
    if (isSymlink) {
      // 符号链接按目标类型决定能否进入（如 /etc/nginx/sites-enabled）。
      try {
        final target = await _client.stat(
          sftpJoin(dir, name.filename),
          followLink: true,
        );
        isDirectory = target.mode?.type == SftpFileType.directory;
      } on Object {
        isDirectory = false; // 悬空链接按普通文件展示。
      }
    }
    final modified = name.attr.modifyTime;
    return SftpEntry(
      name: name.filename,
      path: sftpJoin(dir, name.filename),
      isDirectory: isDirectory,
      isSymlink: isSymlink,
      size: name.attr.size ?? 0,
      modifiedAt: modified == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(modified * 1000),
      permissions: formatSftpPermissions(mode),
    );
  }
}

/// 权限位的 `ls -l` 风格展示，例如 `-rw-r--r--`；服务端未返回时为 null。
String? formatSftpPermissions(SftpFileMode? mode) {
  if (mode == null) return null;
  final type = switch (mode.type) {
    SftpFileType.directory => 'd',
    SftpFileType.symbolicLink => 'l',
    SftpFileType.blockDevice => 'b',
    SftpFileType.characterDevice => 'c',
    SftpFileType.pipe => 'p',
    SftpFileType.socket => 's',
    _ => '-',
  };
  final buffer = StringBuffer(type);
  for (final (read, write, execute) in [
    (mode.userRead, mode.userWrite, mode.userExecute),
    (mode.groupRead, mode.groupWrite, mode.groupExecute),
    (mode.otherRead, mode.otherWrite, mode.otherExecute),
  ]) {
    buffer
      ..write(read ? 'r' : '-')
      ..write(write ? 'w' : '-')
      ..write(execute ? 'x' : '-');
  }
  return buffer.toString();
}

/// 底层错误 → [SftpException]。SFTP 状态码优先，其次网络 / 平台能力。
SftpException sftpErrorFrom(Object error) {
  if (error is SftpException) return error;
  if (error is SftpStatusError) {
    return SftpException(switch (error.code) {
      SftpStatusCode.permissionDenied => SftpErrorKind.permission,
      SftpStatusCode.noSuchFile => SftpErrorKind.notFound,
      SftpStatusCode.opUnsupported => SftpErrorKind.unsupported,
      SftpStatusCode.noConnection ||
      SftpStatusCode.connectionLost => SftpErrorKind.network,
      _ => SftpErrorKind.other,
    }, error.message);
  }
  if (error is UnsupportedError) {
    return SftpException(SftpErrorKind.unsupported);
  }
  if (error is TimeoutException ||
      error is SSHSocketError ||
      error is SSHDisconnectError ||
      error is SftpAbortError) {
    return SftpException(SftpErrorKind.network, error.toString());
  }
  return SftpException(SftpErrorKind.other, error.toString());
}
