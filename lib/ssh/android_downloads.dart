/// Android 公共下载目录（`Download/`）的落盘通道：按平台条件导出，web 走桩。
/// `_io` 版本内部按 `defaultTargetPlatform` 判断，非 Android 平台一律回答
/// 「走不了」，调用方随之退回应用文档目录。
library;

export 'android_downloads_stub.dart'
    if (dart.library.io) 'android_downloads_io.dart';
