import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'update_check_client.dart';

/// 原始实现：用 `dart:io` 的 [HttpClient] 直连 GitHub Releases API。
///
/// 不引 http 包：只要一个 GET，`HttpClient` 就够。web 没有 `dart:io`，
/// 由 `update_check_stub.dart` 顶上（那是**不支持**，不是「当作已是最新」）。
class HttpUpdateCheckClient implements UpdateCheckClient {
  HttpUpdateCheckClient({
    this.timeout = const Duration(seconds: 8),
    Uri? endpoint,
  }) : endpoint =
           endpoint ??
           Uri.parse(
             'https://api.github.com/repos/$kRepositoryPath/releases/latest',
           );

  /// 仓库坐标；只此一处，改仓库名只改这里。
  static const String kRepositoryPath = 'chengvar-glitch/no-shell';

  /// 单次查询的总时限：超时就当网络失败，不能让「检查更新」把界面吊着。
  final Duration timeout;

  final Uri endpoint;

  @override
  Future<ReleaseInfo> fetchLatestRelease() async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(endpoint).timeout(timeout);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      // GitHub 要求带 User-Agent，缺失会被 403 挡掉。
      request.headers.set(HttpHeaders.userAgentHeader, 'NoShell');
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      return _parse(response.statusCode, body);
    } on ReleaseLookupException {
      rethrow;
    } on TimeoutException catch (error) {
      throw ReleaseLookupException(ReleaseLookupError.network, '$error');
    } on SocketException catch (error) {
      throw ReleaseLookupException(ReleaseLookupError.network, '$error');
    } on HttpException catch (error) {
      throw ReleaseLookupException(ReleaseLookupError.network, '$error');
    } on HandshakeException catch (error) {
      // TLS 失败（证书过期、中间人、公司代理）同属「连不上」，
      // 不要落到下面的兜底里被当成响应格式错。
      throw ReleaseLookupException(ReleaseLookupError.network, '$error');
    } on FormatException catch (error) {
      throw ReleaseLookupException(ReleaseLookupError.malformed, '$error');
    } finally {
      client.close(force: true);
    }
  }

  ReleaseInfo _parse(int statusCode, String body) {
    if (statusCode == HttpStatus.notFound) {
      throw const ReleaseLookupException(ReleaseLookupError.notFound);
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw ReleaseLookupException(
        ReleaseLookupError.server,
        'HTTP $statusCode',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (error) {
      throw ReleaseLookupException(ReleaseLookupError.malformed, '$error');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ReleaseLookupException(
        ReleaseLookupError.malformed,
        'response is not a JSON object',
      );
    }
    // draft 不会出现在 latest 接口里，但判一次不吃亏；prerelease 同样跳过：
    // 预览版不该推给只装正式版的用户。
    if (decoded['draft'] == true || decoded['prerelease'] == true) {
      throw const ReleaseLookupException(ReleaseLookupError.notFound);
    }
    final tag = decoded['tag_name'];
    if (tag is! String || tag.trim().isEmpty) {
      throw const ReleaseLookupException(
        ReleaseLookupError.malformed,
        'tag_name is missing',
      );
    }
    final notes = decoded['body'];
    final pageUrl = decoded['html_url'];
    // published_at 优先，退回 created_at：草稿发布后两者通常一致，
    // 但改过发布时间的 release 只有前者准。
    final publishedAt =
        _parseDate(decoded['published_at']) ??
        _parseDate(decoded['created_at']);
    return ReleaseInfo(
      version: tag,
      notes: notes is String ? notes : '',
      pageUrl: pageUrl is String && pageUrl.isNotEmpty ? pageUrl : null,
      publishedAt: publishedAt,
    );
  }

  /// 解析 GitHub 的 ISO8601 时间戳；缺失或格式不对返回 null（只影响展示，
  /// 不能让一个日期把整次查询判成失败）。
  DateTime? _parseDate(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
