/// 导出文件的系统分享能力：桌面 / 移动端走原生分享面板，web 走桩实现。
/// 与 `local_write` 同样的条件导出模式，保证 `lib/` 不直接触碰平台通道。
library;

export 'local_share_stub.dart' if (dart.library.io) 'local_share_io.dart';
