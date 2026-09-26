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

/// 落点是否已存在同名文件：下载覆盖确认用。
Future<bool> doesLocalFileExist(String path) => File(path).exists();

/// 写入中的临时路径：新建文件都先落在这里，成功后再改名到目标。
/// 与目标同目录，改名才是同卷操作（跨卷 rename 会失败）。
///
/// 后缀与远端那份（[SftpTransferQueue] 的 `.noshell-part`）保持一致：
/// 失败与取消都会清掉它，但进程被强杀时可能留下一个半成品，
/// 带上应用名才看得出是谁留下的、也才敢在别处认领。
String localTemporaryPath(String path) => '$path.noshell-part';

/// 把写完的临时文件改名到目标路径，实现「要么是旧文件、要么是新文件」。
///
/// 覆盖写入如果直接落在目标上，写一半失败就把用户原有的文件毁了；
/// 先写 `.part` 再改名则失败时目标原封不动。POSIX 下改名能覆盖已存在的
/// 目标；Windows 不允许，需要先把旧目标挪开——绝不能直接删：挪开后的
/// 第二次改名若再失败（目标被杀软 / 其他进程锁定等），必须把旧文件
/// 滚回来，否则用户两头皆空。
Future<void> promoteLocalFile(String temporaryPath, String targetPath) async {
  final temporary = File(temporaryPath);
  try {
    await temporary.rename(targetPath);
    return;
  } on FileSystemException {
    // POSIX 走不到这里；Windows 落到下面的挪开-换入-回滚流程。
  }
  final backupPath = '$targetPath.noshell-old';
  File? backup;
  try {
    backup = await File(targetPath).rename(backupPath);
  } on FileSystemException {
    // 目标本来就不存在（或挪不动）：前者直接换入即可，后者下面会重抛。
    backup = null;
  }
  try {
    await temporary.rename(targetPath);
  } on FileSystemException {
    // 换入失败：把旧目标滚回原位，用户原有的文件不能丢。
    if (backup != null) {
      try {
        await backup.rename(targetPath);
      } on FileSystemException {
        // 滚不回去时至少文件还在 .noshell-old，不能静默删掉它。
      }
    }
    rethrow;
  }
  // 换入成功，旧的那份才真正不需要了。
  if (backup != null) {
    try {
      await backup.delete();
    } on FileSystemException {
      // 删不掉就留着，别让收尾失败毁掉已经完成的下载。
    }
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
