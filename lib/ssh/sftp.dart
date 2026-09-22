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
///
/// [home] 是会话的家目录：家目录及其子目录折叠成一段（`isHome` 为 true，
/// [label] 为空，界面用本地化的「主目录」补上）——GNOME 文件管理器就是这么
/// 显示的，`/ home deploy …` 三段在窄面板里纯属浪费横向空间。
/// 家目录未知或路径不在家目录下时按根目录逐段拆开。
List<({String label, String path, bool isHome})> sftpBreadcrumbs(
  String path, {
  String? home,
}) {
  final trimmed = _trimTrailingSlash(path);
  final crumbs = <({String label, String path, bool isHome})>[];
  final homePath = home == null || home.isEmpty
      ? null
      : _trimTrailingSlash(home);
  if (homePath != null &&
      (trimmed == homePath || trimmed.startsWith('$homePath/'))) {
    crumbs.add((label: '', path: homePath, isHome: true));
    var current = homePath;
    for (final segment in trimmed.substring(homePath.length).split('/')) {
      if (segment.isEmpty) continue;
      current = '$current/$segment';
      crumbs.add((label: segment, path: current, isHome: false));
    }
    return crumbs;
  }
  crumbs.add((label: '/', path: '/', isHome: false));
  var current = '';
  for (final segment in trimmed.split('/')) {
    if (segment.isEmpty) continue;
    current = '$current/$segment';
    crumbs.add((label: segment, path: current, isHome: false));
  }
  return crumbs;
}

/// 远端 SFTP 路径是否带 Windows OpenSSH 的盘符形态。
///
/// Win32 OpenSSH 把 `C:\Users\me` 暴露成 `/C:/Users/me`；本地 Windows 盘符
/// （`C:/...` / `C:\...`）也一并认出来。`/mnt/c/...` 是 Unix 路径，不算。
bool sftpIsWindowsRemotePath(String path) {
  final trimmed = path.trim();
  return RegExp(r'^[A-Za-z]:(?:[/\\]|$)').hasMatch(trimmed) ||
      RegExp(r'^/[A-Za-z]:(?:/|$)').hasMatch(trimmed);
}

/// 地址栏下方的快捷位置：Linux 常用目录 + 当前会话家目录（`~`）。
///
/// 返回顺序就是胶囊顺序；[home] 若与某一项相同则不重复给。Windows OpenSSH
/// 的家目录带盘符（`/C:/Users/me`），那些 `/etc`、`/var` 对它没有意义，
/// 因此返回空列表——调用方一行胶囊都不画。
List<({String label, String path})> sftpQuickPaths({required String home}) {
  if (home.isEmpty || sftpIsWindowsRemotePath(home)) return const [];
  final homePath = home == '/' ? '' : home;
  const standard = [
    (label: '/etc', path: '/etc'),
    (label: '/home', path: '/home'),
    (label: '/root', path: '/root'),
    (label: '/var', path: '/var'),
    (label: '/tmp', path: '/tmp'),
    (label: '/opt', path: '/opt'),
    (label: '/usr', path: '/usr'),
    (label: '/srv', path: '/srv'),
  ];
  return [
    (label: '/', path: '/'),
    if (homePath.isNotEmpty) (label: '~', path: homePath),
    for (final target in standard)
      if (target.path != homePath) target,
  ];
}

/// 把地址栏里敲进来的一行文本规整成远端绝对路径。
///
/// - `~` / `~/…` 展开成家目录（[home] 未知时原样留下，让服务端报错而不是
///   静默跳到别处）；`~user` 不认，同样原样留下；
/// - 相对路径按 [base]（当前目录）解析；
/// - 去掉 `.` 与 `..`、合并重复的 `/`、去掉尾斜杠；
/// - 从终端里粘出来的路径常带成对引号与首尾空白，一并去掉。
///
/// 返回值一律以 `/` 开头（认不出的写法除外），空输入返回 null。
String? resolveSftpPath(String input, {String? home, String? base}) {
  var text = input.trim();
  if (text.length >= 2) {
    final first = text[0];
    final last = text[text.length - 1];
    if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
      text = text.substring(1, text.length - 1).trim();
    }
  }
  if (text.isEmpty) return null;
  final homePath = home == null || home.isEmpty
      ? null
      : _trimTrailingSlash(home);
  final String raw;
  if (text == '~') {
    if (homePath == null) return text;
    raw = homePath;
  } else if (text.startsWith('~/')) {
    if (homePath == null) return text;
    raw = '$homePath${text.substring(1)}';
  } else if (text.startsWith('~')) {
    // `~user` 需要服务端才知道家目录在哪，这里不猜。
    return text;
  } else if (text.startsWith('/')) {
    raw = text;
  } else {
    raw = sftpJoin(base ?? homePath ?? '/', text);
  }
  return _normalizeSftpPath(raw);
}

/// 地址栏补全：把「敲到一半的路径」拆成「要列出的目录 + 名称前缀」。
///
/// 末尾带 `/` 时前缀为空（列该目录的全部内容）；没有任何 `/` 时按 [base]
/// 展开。`~` / `~user` 这类认不出的写法返回 null，调用方不弹候选。
({String directory, String prefix})? sftpCompletionQuery(
  String input, {
  String? home,
  String? base,
}) {
  final text = input.trim();
  // 单独一个 `~`（以及认不出的 `~user`）不补全：GNOME 的位置栏也是敲到
  // 斜杠才开始给候选，`~` 到回车时才展开成家目录。
  if (text.startsWith('~') && !text.startsWith('~/')) return null;
  final homePath = home == null || home.isEmpty
      ? null
      : _trimTrailingSlash(home);
  if (text.startsWith('~/') && homePath == null) return null;
  final expanded = text.startsWith('~/')
      ? '$homePath${text.substring(1)}'
      : text;
  final fallback = base ?? homePath ?? '/';
  final String rawDirectory;
  final String prefix;
  if (expanded.isEmpty) {
    rawDirectory = fallback;
    prefix = '';
  } else if (expanded.endsWith('/')) {
    rawDirectory = expanded;
    prefix = '';
  } else {
    final index = expanded.lastIndexOf('/');
    if (index < 0) {
      rawDirectory = fallback;
      prefix = expanded;
    } else {
      rawDirectory = expanded.substring(0, index);
      prefix = expanded.substring(index + 1);
    }
  }
  final directory = rawDirectory.startsWith('/')
      ? _normalizeSftpPath(rawDirectory)
      : _normalizeSftpPath(sftpJoin(fallback, rawDirectory));
  return (directory: directory, prefix: prefix);
}

/// 去掉 `.` / `..` / 空段与重复斜杠，结果一律以 `/` 开头的绝对路径。
/// 根目录之上的 `..` 停在根目录（与文件管理器一致，不做符号链接解析）。
String _normalizeSftpPath(String path) {
  final segments = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (segments.isNotEmpty) segments.removeLast();
      continue;
    }
    segments.add(segment);
  }
  return '/${segments.join('/')}';
}

/// 太长的一层在面包屑里显示成「开头…结尾」：GNOME 的位置栏就是这么处理
/// 超长目录名的（中间省略）——只留开头的话，`2026-09-21` 这类靠结尾区分的
/// 名字就分不出来了。短名字原样返回。
String elideSftpName(String name, int keep) {
  if (name.length <= keep + 3) return name;
  return '${name.substring(0, keep)}…${name.substring(name.length - 2)}';
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
