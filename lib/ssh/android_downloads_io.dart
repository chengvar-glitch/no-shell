/// Android 公共下载目录（`Download/`）的真实实现。
///
/// 两支落点，都在「系统下载目录」里，区别只在于怎么拿到写入权：
///
/// - `mediastore:<文件名>` —— Android 10+。公共目录只能经 MediaStore 写，
///   拿不到可写的绝对路径，所以宿主建一条 `IS_PENDING=1` 的记录，把该记录的
///   文件描述符交回来（`/proc/self/fd/N`），`dart:io` 照常往里灌数据，
///   全文件只在磁盘上存一份；收尾把 `IS_PENDING` 归零。
/// - `publicdownload:<绝对路径>` —— Android 9 及以下。那些系统上公共目录就是
///   普通文件路径，只要有 `WRITE_EXTERNAL_STORAGE` 就能直接写，临时文件与
///   改名仍走 `local_write_io` 那套（同目录 `.noshell-part`）。
///
/// 落点不是真路径这件事只影响调用方一件事：认 [isAndroidDownloadPath] 就得
/// 把写 / 收尾 / 清理 / 分享交给本模块，别自己拼路径。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'local_write_io.dart';
import 'local_write_sink.dart';

/// 与 `MainActivity` 里注册的通道同名（宿主侧见
/// `android/app/src/main/kotlin/com/noshell/DownloadsChannel.kt`）。
const _channel = MethodChannel('com.noshell/downloads');

const _mediaStorePrefix = 'mediastore:';

const _legacyPrefix = 'publicdownload:';

/// 自检用的文件名。带上应用前缀，免得撞上用户真在下发的文件。
const _probeName = '.noshell-probe';

/// MediaStore 那支的探测结果缓存：探测包含一次真实的建行 / 打开 / 删除往返，
/// 一次就够，不该每下载一个文件都重来一遍。
bool? _mediaStoreUsable;

/// Android 9 及以下被拒过一次就不再问（本次运行）：反复弹权限框比退回应用
/// 目录更烦人，而且用户已经明确说了「不给」。
bool _storageDenied = false;

/// 这台设备上的公共下载目录落点；走不了（非 Android、探测不过、权限被拒）
/// 时返回 null，调用方退回应用目录——那目录用户在系统文件管理器里看不到，
/// 所以不能默认走它。
Future<String?> publicDownloadTarget(String name) async {
  if (defaultTargetPlatform != TargetPlatform.android) return null;
  if (await _mediaStoreUsableNow()) return '$_mediaStorePrefix$name';
  return _legacyDownloadTarget(name);
}

/// Android 10+ 那支：宿主的静态检查（Android 10+、外部存储已挂载）只是必要
/// 条件——能不能真写进去还取决于 OEM 策略（Android 10 上就有一部分设备要求
/// `WRITE_EXTERNAL_STORAGE`），而 `/proc/self/fd/N` 这条路走不走得通也只有试过
/// 才知道。真建一条 pending 行、真打开一次、随即删掉；探不通就退回应用目录，
/// 不让「下载完用户找不到」这个老毛病借新代码还魂。
Future<bool> _mediaStoreUsableNow() async {
  final cached = _mediaStoreUsable;
  if (cached != null) return cached;
  try {
    if (await _channel.invokeMethod<bool>('mediaStoreAvailable') != true) {
      return _mediaStoreUsable = false;
    }
    final fdPath = await _channel.invokeMethod<String>('begin', {
      'name': _probeName,
    });
    if (fdPath == null) return _mediaStoreUsable = false;
    await openLocalWrite(fdPath).close();
    await _channel.invokeMethod<bool>('abort', {'name': _probeName});
    return _mediaStoreUsable = true;
  } on Object {
    // 探测留下的那条记录尽力清掉：清不掉也只是一条别人看不见的 pending
    // 行，系统 7 天后自己会收走。
    try {
      await _channel.invokeMethod<bool>('abort', {'name': _probeName});
    } on Object {
      // 忽略：结论已经是不可用。
    }
    return _mediaStoreUsable = false;
  }
}

/// Android 9 及以下那支：公共目录就是普通路径，缺的只有存储权限。
/// 权限申请就地发起——用户刚点完「下载」，此刻弹框他知道是在问什么。
Future<String?> _legacyDownloadTarget(String name) async {
  if (_storageDenied) return null;
  try {
    final directory = await _channel.invokeMethod<String>('legacyPath');
    // 宿主的回答是 null：系统不是 Android 9 及以下，或外部存储没挂载。
    if (directory == null) return null;
    if (await _channel.invokeMethod<bool>('hasStoragePermission') != true) {
      final granted =
          await _channel.invokeMethod<bool>('requestStoragePermission') ??
          false;
      if (!granted) {
        _storageDenied = true;
        return null;
      }
    }
    // 权限到手了还进不去：那是真没有这个目录（存储异常），别把落点定在过去。
    if (!Directory(directory).existsSync()) return null;
    return legacyDownloadPath(_joinPath(directory, name));
  } on Object {
    return null;
  }
}

/// 落点是不是 Android 公共下载目录（两支都算）。
bool isAndroidDownloadPath(String path) =>
    path.startsWith(_mediaStorePrefix) || path.startsWith(_legacyPrefix);

/// 落点是不是 MediaStore 那一支（没有真路径、收尾要经通道）。
bool isMediaStoreDownloadPath(String path) =>
    path.startsWith(_mediaStorePrefix);

/// Android 9 及以下那支落点背后的真路径；MediaStore 那支返回 null。
String? androidDownloadRealPath(String path) => path.startsWith(_legacyPrefix)
    ? path.substring(_legacyPrefix.length)
    : null;

/// 把公共下载目录里的真路径包成那一支的暗号。临时文件也走它：同一个暗号
/// 意味着同一套权限语义（公共目录里的文件不收 0600），网关少一个分支。
String legacyDownloadPath(String realPath) => '$_legacyPrefix$realPath';

String _mediaStoreName(String path) => path.substring(_mediaStorePrefix.length);

/// 建一条 pending 行并打开写入句柄。行在写完前对别的应用不可见
/// （`IS_PENDING=1`），收尾时由 [promoteMediaStoreDownload] 转正，
/// 失败 / 取消则由 [discardMediaStoreDownload] 连行带文件删掉——
/// 与落盘那套「先写临时、成功再改名」是同一个目的，只是这里由系统记账。
Future<LocalWriteHandle> openMediaStoreDownload(String path) async {
  final fdPath = await _channel.invokeMethod<String>('begin', {
    'name': _mediaStoreName(path),
  });
  if (fdPath == null) {
    throw PlatformException(
      code: 'downloads_begin',
      message: 'MediaStore 没有交回可写的文件描述符',
    );
  }
  try {
    // ownerOnly 在这里刻意不生效：文件落在共享的下载集合里，权限位由
    // MediaStore 建行时按该集合的组与模式定好，收到 0600 反而会让别的应用
    // 经 MediaProvider 读不到用户自己下的文件。
    return openLocalWrite(fdPath);
  } on Object {
    // 拿不到可写的句柄就不能留下一条空记录。
    await discardMediaStoreDownload(path);
    rethrow;
  }
}

/// 收尾：把 pending 行转正。返回该行最终的显示名——重名时 MediaStore 会
/// 把它改成 `name (1).ext`，界面提示必须照实说，否则用户按提示去找会扑空。
Future<String?> promoteMediaStoreDownload(String path) =>
    _channel.invokeMethod<String>('finish', {'name': _mediaStoreName(path)});

/// 清理：删掉 pending 行与半成品文件。没建过行时是空操作。
Future<void> discardMediaStoreDownload(String path) async {
  await _channel.invokeMethod<bool>('abort', {'name': _mediaStoreName(path)});
}

/// 把已落地的下载交给系统分享面板。走宿主是为了**不再拷一份**：文件在共享
/// 的下载集合里，直接以 MediaStore 的 `content://` 地址发给接收方（带上读
/// 授权），比先读出来再写进临时目录省事得多，大文件也不怕。
Future<void> shareMediaStoreDownload(String path, {String? title}) async {
  await _channel.invokeMethod<bool>('share', {
    'name': _mediaStoreName(path),
    'title': title,
  });
}

/// 测试用：清掉探测 / 权限结果缓存，让下一次 [publicDownloadTarget]
/// 重新走一遍。生产代码不需要它——一台设备能不能写不会中途变卦。
@visibleForTesting
void debugResetAndroidDownloadProbe() {
  _mediaStoreUsable = null;
  _storageDenied = false;
}

/// 拼接目录与文件名。这里只处理 Android 的 `/`，不学 `local_files.dart`
/// 那套 Windows 分隔符。
String _joinPath(String directory, String name) =>
    directory.endsWith('/') ? '$directory$name' : '$directory/$name';
