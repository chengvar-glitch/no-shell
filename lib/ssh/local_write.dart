/// 本地落盘能力：桌面 / 移动端走 dart:io，web 走桩实现。
/// 做成条件导出是为了让 `lib/` 在不引入 dart:io 的前提下覆盖六个平台。
library;

export 'local_write_sink.dart';
export 'local_write_stub.dart' if (dart.library.io) 'local_write_io.dart';
