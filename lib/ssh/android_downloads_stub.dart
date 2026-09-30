/// web 桩实现：浏览器没有公共下载目录，Android 那两支落点根本不存在。
/// 与其余平台桩同一个态度——如实回答「走不了」，不假装写成功。
library;

import 'local_write_sink.dart';

/// 只有 Android 才可能走公共下载目录；其余平台恒为 null，
/// 调用方退回应用文档目录。
Future<String?> publicDownloadTarget(String name) async => null;

bool isAndroidDownloadPath(String path) => false;

bool isMediaStoreDownloadPath(String path) => false;

String? androidDownloadRealPath(String path) => null;

String legacyDownloadPath(String realPath) =>
    throw UnsupportedError('Public downloads are not supported on web');

Future<LocalWriteHandle> openMediaStoreDownload(String path) =>
    throw UnsupportedError('MediaStore downloads are not supported on web');

Future<String?> promoteMediaStoreDownload(String path) async => null;

Future<void> discardMediaStoreDownload(String path) async {}

Future<void> shareMediaStoreDownload(String path, {String? title}) async {}

/// 与 io 版本同名：这里没有可清的探测缓存。存在的意义是让条件导出的
/// 门面在两个分支上名字一致。
void debugResetAndroidDownloadProbe() {}
