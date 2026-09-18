/// SFTP 领域模型与抽象接口：不依赖 dartssh2，便于测试替换为内存实现。
library;

/// 远端目录项。符号链接的真实类型已在适配器里解析，
/// [isSymlink] 只用于界面标记，不参与「能否进入」的判断。
final class SftpEntry {
  const SftpEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.isSymlink = false,
    this.size = 0,
    this.modifiedAt,
    this.permissions,
  });

  final String name;

  /// 绝对远端路径，便于直接传给各项操作。
  final String path;
  final bool isDirectory;
  final bool isSymlink;
  final int size;
  final DateTime? modifiedAt;

  /// 形如 `-rw-r--r--`；服务端未返回权限位时为空。
  final String? permissions;

  @override
  String toString() => 'SftpEntry($path)';
}

/// SFTP 失败原因归类，视图层据此挑选本地化文案。
enum SftpErrorKind {
  permission,
  notFound,
  unsupported,
  network,

  /// 已有结构性操作在执行（新建 / 重命名 / 删除 / 刷新），本次请求被拒。
  busy,
  other,
}

/// SFTP 操作异常：适配器负责把底层错误归类，视图层无需感知 dartssh2 类型。
final class SftpException implements Exception {
  const SftpException(this.kind, [this.detail]);

  final SftpErrorKind kind;

  /// 原始错误串，仅用于日志与兜底展示。
  final String? detail;

  @override
  String toString() => detail ?? 'SftpException(${kind.name})';
}

/// 一次 SFTP 数据流操作：在 [onProgress] 中抛出的异常会中断传输，
/// 用于取消上传时提前结束远端写入。
abstract interface class SftpFileSystem {
  /// 会话默认目录（一般是登录用户的家目录）。
  Future<String> homeDirectory();

  /// 读取目录内容；路径不存在或无权限时抛 [SftpException]。
  Future<List<SftpEntry>> list(String path);

  /// 读取远端文件内容。取消订阅即中断读取并释放远端句柄。
  Stream<List<int>> read(String path);

  /// 把字节流写入远端路径，已存在时覆盖。
  /// [onProgress] 为已写入字节数，用于进度展示。
  Future<void> write(
    String path,
    Stream<List<int>> data, {
    void Function(int bytes)? onProgress,
  });

  Future<void> createDirectory(String path);

  Future<void> rename(String from, String to);

  /// 删除文件（目录请用 [removeDirectory]）。
  Future<void> removeFile(String path);

  /// 删除空目录。
  Future<void> removeDirectory(String path);

  /// 关闭 SFTP 通道；连接本身由会话层负责。
  void dispose();
}

/// 远端路径一律以 `/` 分隔，以下工具只做字符串拼接与切分，
/// 不做符号链接 / `..` 解析（那需要服务端 realpath）。
String sftpJoin(String dir, String name) =>
    dir.endsWith('/') ? '$dir$name' : '$dir/$name';

/// 父目录；根目录的父目录仍是根目录。
String sftpParent(String path) {
  final trimmed = _trimTrailingSlash(path);
  final index = trimmed.lastIndexOf('/');
  if (index <= 0) return '/';
  return trimmed.substring(0, index);
}

/// 面包屑分段：绝对路径拆成 `(显示名, 绝对路径)` 列表，便于逐级点击。
List<({String label, String path})> sftpBreadcrumbs(String path) {
  final trimmed = _trimTrailingSlash(path);
  final crumbs = <({String label, String path})>[(label: '/', path: '/')];
  var current = '';
  for (final segment in trimmed.split('/')) {
    if (segment.isEmpty) continue;
    current = '$current/$segment';
    crumbs.add((label: segment, path: current));
  }
  return crumbs;
}

/// 校验用户新建 / 重命名时输入的名称：不允许路径分隔符与 `..`。
bool isValidEntryName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty || trimmed == '.' || trimmed == '..') return false;
  return !trimmed.contains('/') && !trimmed.contains('\\');
}

String _trimTrailingSlash(String path) {
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  return path;
}

/// 字节数展示：文件列表、传输速率与剩余量共用同一套单位。
String formatSftpSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}

/// 剩余时间展示：只保留两级单位，避免出现 `1h 2m 3s` 这种过长文案。
String formatSftpDuration(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds <= 0) return '0s';
  if (seconds < 60) return '${seconds}s';
  final minutes = duration.inMinutes;
  if (minutes < 60) {
    final rest = seconds - minutes * 60;
    return rest == 0 ? '${minutes}m' : '${minutes}m ${rest}s';
  }
  final hours = duration.inHours;
  final rest = minutes - hours * 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}
