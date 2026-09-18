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

/// 把文件交给系统分享面板。分享结束后删掉文件：
/// 它是我们自己生成的临时产物，用户要留下的那份已经由分享面板另存了。
///
/// `sharePositionOrigin` 传 null 时 iPad 会把弹出层锚在屏幕中心而不是抛错，
/// 这里没有具体的触发控件可锚（导出由菜单触发、弹窗早已关闭），因此不传。
Future<void> shareLocalFileOnDevice(String path, {String? title}) async {
  final file = File(path);
  try {
    if (!await file.exists()) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'application/json')],
        subject: title,
        title: title,
      ),
    );
  } finally {
    if (await file.exists()) await file.delete();
  }
}
