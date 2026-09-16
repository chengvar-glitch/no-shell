import 'dart:async';

import 'package:file_selector/file_selector.dart';

import 'local_write.dart';

/// 本地落盘能力随网关一起对外暴露，调用方只需这一个 import。
export 'local_write.dart';

/// 待上传的本地文件。只保留流式读取能力，避免把整文件读进内存。
final class LocalUpload {
  const LocalUpload({
    required this.name,
    required this.length,
    required this.openRead,
  });

  final String name;

  /// 文件字节数，用于进度计算；0 表示未知。
  final int length;

  /// 每次调用都返回一个新的字节流（重试 / 重复上传需要重新打开）。
  final Stream<List<int>> Function() openRead;
}

/// 下载落点：完整本地路径与文件显示名。
final class LocalTarget {
  const LocalTarget({required this.path, required this.name});

  final String path;
  final String name;
}

/// 本地文件交互（选择 / 落盘）。桌面与移动端行为差异较大，
/// 且在测试中无法真的弹系统对话框，因此抽象成接口以便替换。
abstract interface class LocalFileGateway {
  /// 选择要上传的本地文件（可多选）；用户取消时返回空列表。
  Future<List<LocalUpload>> pickUploads({String? confirmLabel});

  /// 单个文件的下载落点：桌面弹「另存为」，移动端落到应用文档目录；
  /// 返回 null 表示用户取消。
  Future<LocalTarget?> pickDownloadTarget(
    String suggestedName, {
    String? confirmLabel,
  });

  /// 多个文件的下载落点：桌面弹一次目录选择，移动端落到应用文档目录；
  /// 返回 null 表示用户取消或平台无从确定目录。
  Future<List<LocalTarget>?> pickDownloadDirectory(
    List<String> names, {
    String? confirmLabel,
  });

  /// 打开本地写入流，同名文件覆盖。
  LocalWriteHandle openWrite(String path);

  /// 清理取消 / 失败留下的半成品文件。
  Future<void> discard(String path);
}

/// 真实实现：file_selector 负责原生对话框，落盘走条件导出的 `local_write`。
final class NativeLocalFileGateway implements LocalFileGateway {
  const NativeLocalFileGateway();

  @override
  Future<List<LocalUpload>> pickUploads({String? confirmLabel}) async {
    final files = await openFiles(confirmButtonText: confirmLabel);
    final uploads = <LocalUpload>[];
    for (final file in files) {
      uploads.add(
        LocalUpload(
          name: file.name,
          length: await file.length(),
          openRead: file.openRead,
        ),
      );
    }
    return uploads;
  }

  @override
  Future<LocalTarget?> pickDownloadTarget(
    String suggestedName, {
    String? confirmLabel,
  }) async {
    if (supportsLocalFileDialogs) {
      try {
        final location = await getSaveLocation(
          suggestedName: suggestedName,
          initialDirectory: await defaultLocalDirectory(),
          confirmButtonText: confirmLabel,
        );
        // 用户取消时不再退化为默认目录，避免「取消」反而开始下载。
        if (location == null) return null;
        return LocalTarget(
          path: location.path,
          name: localBaseName(location.path),
        );
      } on Object {
        // 对话框不可用（如平台未实现）时退化为默认目录。
      }
    }
    final fallback = await defaultLocalDirectory();
    if (fallback == null) return null;
    return LocalTarget(
      path: joinLocalPath(fallback, suggestedName),
      name: suggestedName,
    );
  }

  @override
  Future<List<LocalTarget>?> pickDownloadDirectory(
    List<String> names, {
    String? confirmLabel,
  }) async {
    String? directory;
    if (supportsLocalFileDialogs) {
      try {
        directory = await getDirectoryPath(
          initialDirectory: await defaultLocalDirectory(),
          confirmButtonText: confirmLabel,
        );
      } on Object {
        directory = null;
      }
      // 目录选择是显式动作，取消即取消整批下载。
      if (directory == null) return null;
    } else {
      directory = await defaultLocalDirectory();
      if (directory == null) return null;
    }
    return [
      for (final name in names)
        LocalTarget(path: joinLocalPath(directory, name), name: name),
    ];
  }

  @override
  LocalWriteHandle openWrite(String path) => openLocalWrite(path);

  @override
  Future<void> discard(String path) => deleteLocalFile(path);
}

/// 拼接本地路径：Windows 目录形如 `C:\Users\me`，其余平台用 `/`。
String joinLocalPath(String directory, String name) {
  if (directory.isEmpty) return name;
  final separator = _separatorOf(directory);
  return directory.endsWith(separator)
      ? '$directory$name'
      : '$directory$separator$name';
}

/// 取本地路径的最后一段；本地路径可能同时出现 `/` 与 `\`。
String localBaseName(String path) {
  final index = path.lastIndexOf(RegExp(r'[/\\]'));
  return index < 0 ? path : path.substring(index + 1);
}

/// Windows 路径可能写成 `C:/Users/me`，此时按 `/` 拼接仍然正确。
String _separatorOf(String path) =>
    path.contains(r'\') && !path.contains('/') ? r'\' : '/';
