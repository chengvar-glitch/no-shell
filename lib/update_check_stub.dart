import 'update_check_client.dart';

/// web 桩实现：浏览器里没有 `dart:io`。
///
/// 这里刻意**抛不支持**而不是返回「已是最新」：后者会让 web 用户看到
/// 一句凭空的「已是最新版本」，把「查不了」谎报成「查过了」。
/// 调用方据此显示「当前平台不支持检测」，与 SFTP / 转发在 web 上的
/// `TerminalErrorKind.unsupported` 路径同一个态度。
class HttpUpdateCheckClient implements UpdateCheckClient {
  HttpUpdateCheckClient({Duration? timeout, Uri? endpoint});

  @override
  Future<ReleaseInfo> fetchLatestRelease() =>
      throw UnsupportedError('Update check is not supported on web');
}
