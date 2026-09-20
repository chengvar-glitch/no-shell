import 'package:url_launcher/url_launcher.dart';

/// 用系统浏览器打开发布页。打不开（没有浏览器 / 平台通道异常）返回 false，
/// 由调用方提示——「前往下载」点了没反应是最糟的结果。
///
/// 与终端里点链接（`terminal_interactions.dart` 的 `openTerminalLink`）
/// 同一套行为，只是入口挂在设置页上，不掺终端那边的链接判定逻辑。
Future<bool> openExternalUrl(Uri uri) async {
  try {
    return await launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );
  } catch (_) {
    return false;
  }
}
