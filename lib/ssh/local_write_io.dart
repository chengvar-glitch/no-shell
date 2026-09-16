import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'local_write_sink.dart';

/// 打开本地文件写入流；同名文件会被覆盖。
LocalWriteHandle openLocalWrite(String path) =>
    _IoWriteHandle(File(path).openWrite());

/// 删除本地文件；不存在时静默返回，用于清理取消 / 失败留下的半成品。
Future<void> deleteLocalFile(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
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
