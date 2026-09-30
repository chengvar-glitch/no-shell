import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 导出前的临时落点：移动端没有「另存为」对话框，导出先落这里，
/// 再经分享面板交给用户选去处；无论用户怎么选，收尾时都会删掉。
Future<String?> defaultShareDirectory() async {
  try {
    return (await getTemporaryDirectory()).path;
  } on Object {
    return null;
  }
}

/// 把文件交给系统分享面板，文件本身留着。
///
/// `sharePositionOrigin` 传 null 时 iPad 会把弹出层锚在屏幕中心而不是抛错，
/// 这里没有具体的触发控件可锚（下载完成、导出弹窗都已关闭），因此不传。
Future<void> shareLocalPathOnDevice(
  String path, {
  String? title,
  String? mimeType,
}) async {
  final file = File(path);
  if (!await file.exists()) return;
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(path, mimeType: mimeType)],
      subject: title,
      title: title,
    ),
  );
}

/// 把临时产物交给系统分享面板，分享结束后删掉它：
/// 用户要留下的那份已经由分享面板另存了，临时目录里不该留一堆看不见的旧导出。
Future<void> shareLocalFileOnDevice(String path, {String? title}) async {
  final file = File(path);
  try {
    // 导出物是主机备份 / 会话日志这类纯文本，按 JSON 报 MIME 与 `.nsbak`
    // 声明的 UTI（conforms to public.json）一致，接收方才知道它能当文本读。
    await shareLocalPathOnDevice(
      path,
      title: title,
      mimeType: 'application/json',
    );
  } finally {
    if (await file.exists()) await file.delete();
  }
}
