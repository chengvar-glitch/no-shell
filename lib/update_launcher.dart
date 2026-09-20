/// 打开发布页的能力：原生端交给系统浏览器，web 开新标签页。
/// 与 `local_write` / `local_share` 同样的条件导出模式。
library;

export 'update_launcher_stub.dart'
    if (dart.library.io) 'update_launcher_io.dart';
