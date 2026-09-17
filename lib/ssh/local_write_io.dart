import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'local_chmod.dart';
import 'local_write_sink.dart';

/// 打开本地文件写入流；同名文件会被覆盖。
///
/// [ownerOnly] 为 true 时把新建文件的权限收到 0600（仅当前用户可读写）。
/// 导出主机备份时必开：备份的明文里带着密码，按 umask 默认落成 0644
/// 就等于同机器上任何本地账号都能读到。
LocalWriteHandle openLocalWrite(String path, {bool ownerOnly = false}) {
  final file = File(path);
  if (ownerOnly) restrictFileToOwner(file);
  return _IoWriteHandle(file.openWrite());
}

/// 删除本地文件；不存在时静默返回，用于清理取消 / 失败留下的半成品。
Future<void> deleteLocalFile(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}

/// 写入中的临时路径：新建文件都先落在这里，成功后再改名到目标。
/// 与目标同目录，改名才是同卷操作（跨卷 rename 会失败）。
String localTemporaryPath(String path) => '$path.part';

/// 把写完的临时文件改名到目标路径，实现「要么是旧文件、要么是新文件」。
///
/// 覆盖写入如果直接落在目标上，写一半失败就把用户原有的文件毁了；
/// 先写 `.part` 再改名则失败时目标原封不动。POSIX 下改名能覆盖已存在的
/// 目标；Windows 不允许，先删一次再试。
Future<void> promoteLocalFile(String temporaryPath, String targetPath) async {
  final temporary = File(temporaryPath);
  try {
    await temporary.rename(targetPath);
  } on FileSystemException {
    await deleteLocalFile(targetPath);
    await temporary.rename(targetPath);
  }
}

/// 默认下载目录：桌面取系统下载目录，移动端取应用文档目录。
/// 取不到时返回 null，由调用方退化为「不指定初始目录」。
Future<String?> defaultLocalDirectory() async {
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      return (await getApplicationDocumentsDirectory()).path;
    }
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads.path;
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    return (home == null || home.isEmpty) ? null : home;
  } on Object {
    return null;
  }
}

/// 移动端的目录选择器返回的是 SAF / 沙盒 URL，dart:io 无法直接写入，
/// 因此仅在桌面端启用原生「另存为 / 选目录」对话框。
bool get supportsLocalFileDialogs =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

final class _IoWriteHandle implements LocalWriteHandle {
  _IoWriteHandle(this._sink);

  final IOSink _sink;

  @override
  void add(List<int> chunk) => _sink.add(chunk);

  @override
  Future<void> flush() => _sink.flush();

  @override
  Future<void> close() => _sink.close();
}
