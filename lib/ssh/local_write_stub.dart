import 'local_write_sink.dart';

/// web 桩实现：浏览器没有本地文件系统，SFTP 在 web 端本身也不可用
/// （会话层的 `TerminalErrorKind.unsupported` 路径），这里只需保证可编译。
LocalWriteHandle openLocalWrite(String path, {bool ownerOnly = false}) =>
    throw UnsupportedError('Local file writing is not supported on web');

Future<void> deleteLocalFile(String path) async {}

/// web 桩实现：浏览器没有本地文件系统，SFTP 在 web 端本身也不可用。
String localTemporaryPath(String path) => path;

Future<void> promoteLocalFile(String temporaryPath, String targetPath) async {}

Future<String?> defaultLocalDirectory() async => null;

bool get supportsLocalFileDialogs => false;
