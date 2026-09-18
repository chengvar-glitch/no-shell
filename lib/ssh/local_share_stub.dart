/// web 桩实现：浏览器没有可分享的本地文件（SFTP 与本地落盘在 web 端本身
/// 就不可用），这里只需保证可编译。
library;

Future<String?> defaultShareDirectory() async => null;

Future<void> shareLocalFileOnDevice(String path, {String? title}) async {}
