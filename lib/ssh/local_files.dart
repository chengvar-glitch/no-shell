import 'dart:async';

import 'package:file_selector/file_selector.dart';

import 'local_share.dart';
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

/// 导出落点：写到哪、写完要不要再交给系统分享面板。
///
/// 桌面端是「另存为」选中的路径，写完就完事；移动端写进应用自己的目录后
/// 必须过一道分享面板，由用户决定存到「文件」、发给别人还是存 iCloud——
/// 移动端没有「另存为」对话框（选择器返回的是 SAF / 沙盒 URL，`dart:io`
/// 写不进去），不分享的话文件就永远躺在用户找不到的地方。
final class LocalDestination {
  const LocalDestination({
    required this.path,
    required this.name,
    this.share = false,
  });

  final String path;
  final String name;
  final bool share;
}

/// 本地文件交互（选择 / 落盘）。桌面与移动端行为差异较大，
/// 且在测试中无法真的弹系统对话框，因此抽象成接口以便替换。
abstract interface class LocalFileGateway {
  /// 选择要上传的本地文件（可多选）；用户取消时返回空列表。
  Future<List<LocalUpload>> pickUploads({String? confirmLabel});

  /// 导出文件的落点。桌面端弹「另存为」（取消返回 null），
  /// 移动端给应用目录下的路径并要求写完分享。
  Future<LocalDestination?> pickExportDestination(
    String suggestedName, {
    String? confirmLabel,
  });

  /// 把刚写好的文件交给系统分享面板（移动端导出用）；
  /// 无论用户是否真的分享出去，文件都由实现方负责收拾干净。
  Future<void> shareLocalFile(String path, {String? title});

  /// 把已经落地的下载交给系统分享面板（移动端）。与 [shareLocalFile] 的
  /// 分别只有一条：文件是用户的，分享完**不能删**。
  Future<void> shareDownload(String path, {String? title});

  /// 单个文件的下载落点：桌面弹「另存为」，Android 落到系统公共下载目录
  /// （10+ 走 MediaStore，9 及以下在授权后直接写路径），其余移动端落到
  /// 应用文档目录；返回 null 表示用户取消。
  Future<LocalTarget?> pickDownloadTarget(
    String suggestedName, {
    String? confirmLabel,
  });

  /// 多个文件的下载落点：桌面弹一次目录选择，Android 落到系统公共下载
  /// 目录，其余移动端落到应用文档目录；
  /// 返回 null 表示用户取消或平台无从确定目录。
  Future<List<LocalTarget>?> pickDownloadDirectory(
    List<String> names, {
    String? confirmLabel,
  });

  /// 打开本地写入流，同名文件覆盖。异步是因为 Android 公共下载目录的落点
  /// 要先在 MediaStore 里建一条记录——系统侧的事急不得。
  /// [ownerOnly] 为 true 时把权限收到仅当前用户可读写（导出含密码的
  /// 备份文件时必须开启）；公共下载目录里的文件不适用（别的应用要读得到）。
  Future<LocalWriteHandle> openWrite(String path, {bool ownerOnly = false});

  /// 写入中的临时路径。下载先写这里，成功后再 [promote] 到目标，
  /// 免得下到一半失败把用户原有的同名文件毁掉。
  String temporaryPath(String path);

  /// 把写完的临时文件改名到目标路径（覆盖语义）。返回落点最终的显示名：
  /// Android 公共下载目录（MediaStore 那支）遇到重名会把它改成
  /// `name (1).ext`，桌面的「另存为」也可能被用户改过名字；
  /// 与请求的同名或无从得知时为 null。
  Future<String?> promote(String temporaryPath, String targetPath);

  /// 清理取消 / 失败留下的半成品文件。
  Future<void> discard(String path);

  /// 落点是否已存在同名文件：下载覆盖确认用（上传链路的同名确认靠远端
  /// 列目录，下载落点在本地，只能这样问）。Android 的 MediaStore 落点永远
  /// 回答「不存在」——那里的重名由系统改成 `name (1).ext`，不会覆盖，
  /// 也就没有「要不要覆盖」可问；Android 9 及以下那支是真路径，照常回答。
  Future<bool> localFileExists(String path);
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
  Future<LocalDestination?> pickExportDestination(
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
        // 用户取消时不再退化为默认目录：导出是一次明确动作，
        // 取消就该什么都不发生。
        if (location == null) return null;
        return LocalDestination(
          path: location.path,
          name: localLeafName(location.path),
        );
      } on Object {
        // 对话框不可用（如平台未实现）时退化为默认目录。
      }
    }
    // 移动端：写进临时目录，写完交给分享面板。用临时目录而不是文档目录，
    // 是为了不留下一堆用户看不见也删不掉的旧导出。
    final directory = await defaultShareDirectory();
    if (directory == null) return null;
    return LocalDestination(
      path: _joinLocalPath(directory, suggestedName),
      name: suggestedName,
      share: true,
    );
  }

  @override
  Future<void> shareLocalFile(String path, {String? title}) =>
      shareLocalFileOnDevice(path, title: title);

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
          name: localLeafName(location.path),
        );
      } on Object {
        // 对话框不可用（如平台未实现）时退化为默认目录。
      }
    }
    // Android：落到系统公共下载目录。用户在文件管理器里随手就能找到，
    // 也不随卸载消失；应用文档目录只有 iOS 靠 Info.plist 才对用户可见，
    // Android 上那个目录用户在设备上根本进不去。
    final public = await publicDownloadTarget(suggestedName);
    if (public != null) {
      return LocalTarget(path: public, name: suggestedName);
    }
    final fallback = await defaultLocalDirectory();
    if (fallback == null) return null;
    return LocalTarget(
      path: _joinLocalPath(fallback, suggestedName),
      name: suggestedName,
    );
  }

  @override
  Future<List<LocalTarget>?> pickDownloadDirectory(
    List<String> names, {
    String? confirmLabel,
  }) async {
    if (supportsLocalFileDialogs) {
      String? directory;
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
      return [
        for (final name in names)
          LocalTarget(path: _joinLocalPath(directory, name), name: name),
      ];
    }
    // Android：整批落到公共下载目录。MediaStore 那支重名由系统改成
    // `name (1).ext`；Android 9 及以下那支是真路径，照常问覆盖。
    final public = <LocalTarget>[];
    for (final name in names) {
      final target = await publicDownloadTarget(name);
      if (target == null) {
        public.clear();
        break;
      }
      public.add(LocalTarget(path: target, name: name));
    }
    if (public.isNotEmpty) return public;
    final directory = await defaultLocalDirectory();
    if (directory == null) return null;
    return [
      for (final name in names)
        LocalTarget(path: _joinLocalPath(directory, name), name: name),
    ];
  }

  @override
  Future<LocalWriteHandle> openWrite(
    String path, {
    bool ownerOnly = false,
  }) async {
    if (isMediaStoreDownloadPath(path)) return openMediaStoreDownload(path);
    final real = androidDownloadRealPath(path);
    // 公共下载目录里的文件（含临时文件）都不收权限：它改名之后就是用户要
    // 留下的那个文件，而下载目录是共享资源，别的应用（相册、办公套件）都要
    // 读得到——收到 0600 等于下完只有本应用看得见。
    if (real != null) return openLocalWrite(real);
    return openLocalWrite(path, ownerOnly: ownerOnly);
  }

  @override
  String temporaryPath(String path) {
    final real = androidDownloadRealPath(path);
    // Android 9 及以下那支：临时文件仍落在同一个公共目录里（同目录改名才是
    // 原子操作），并带上同一个暗号——它的权限语义与目标一致。
    if (real != null) return legacyDownloadPath(localTemporaryPath(real));
    // MediaStore 那支没有「临时路径」这一说：那条记录本身就是临时态
    // （IS_PENDING=1），转正 / 删除都按同一个暗号办。
    return isMediaStoreDownloadPath(path) ? path : localTemporaryPath(path);
  }

  @override
  Future<String?> promote(String temporaryPath, String targetPath) async {
    if (isMediaStoreDownloadPath(targetPath)) {
      return promoteMediaStoreDownload(targetPath);
    }
    final real = androidDownloadRealPath(targetPath);
    // 临时路径也带同一个暗号（见 [temporaryPath]），改名两边都得先解出来。
    final from = androidDownloadRealPath(temporaryPath) ?? temporaryPath;
    await promoteLocalFile(from, real ?? targetPath);
    return null;
  }

  @override
  Future<void> discard(String path) {
    if (isMediaStoreDownloadPath(path)) return discardMediaStoreDownload(path);
    final real = androidDownloadRealPath(path);
    if (real != null) return deleteLocalFile(real);
    return deleteLocalFile(path);
  }

  @override
  Future<bool> localFileExists(String path) async {
    // MediaStore 的重名由系统改成 `name (1).ext`，没有「覆盖」可确认。
    if (isMediaStoreDownloadPath(path)) return false;
    final real = androidDownloadRealPath(path);
    if (real != null) return doesLocalFileExist(real);
    return doesLocalFileExist(path);
  }

  @override
  Future<void> shareDownload(String path, {String? title}) {
    // Android 的两支公共下载落点都认；其余落点是真路径，直接交给系统面板。
    final real = androidDownloadRealPath(path);
    if (real != null) return shareLocalPathOnDevice(real, title: title);
    if (isMediaStoreDownloadPath(path)) {
      return shareMediaStoreDownload(path, title: title);
    }
    return shareLocalPathOnDevice(path, title: title);
  }
}

/// 拼接本地路径：Windows 目录形如 `C:\Users\me`，其余平台用 `/`。
String _joinLocalPath(String directory, String name) {
  if (directory.isEmpty) return name;
  final separator = _separatorOf(directory);
  return directory.endsWith(separator)
      ? '$directory$name'
      : '$directory$separator$name';
}

/// 取本地路径的最后一段；本地路径可能同时出现 `/` 与 `\`。
String localLeafName(String path) {
  final index = path.lastIndexOf(RegExp(r'[/\\]'));
  return index < 0 ? path : path.substring(index + 1);
}

/// 把**服务端给的**条目名收成一个只能落在本地目标目录里的文件名。
///
/// 目录项名在 POSIX 里不可能含分隔符，所以名字里冒出 `/`、`\`，或者干脆就是
/// `.` / `..`，只可能是服务端在撒谎（或它根本不是 POSIX 文件系统）。把这种
/// 名字原样拼进落点，`../../x` 就写到用户选定目录之外去了——下载落点是用户
/// 自己选的，写入范围必须止步于此；覆盖确认也拦不住它（问的是逃逸后那个
/// 路径，那里当然没有文件，于是连问都不问）。
///
/// 取最后一段即可挡住全部越界写法；连最后一段都不合法时才退回 [fallback]。
String safeLocalName(String name, {String fallback = 'download'}) {
  final leaf = localLeafName(name.trim());
  if (leaf.isEmpty || leaf == '.' || leaf == '..') return fallback;
  return leaf;
}

/// Windows 路径可能写成 `C:/Users/me`，此时按 `/` 拼接仍然正确。
String _separatorOf(String path) =>
    path.contains(r'\') && !path.contains('/') ? r'\' : '/';
