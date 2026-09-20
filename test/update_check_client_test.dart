import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/update_check.dart';

/// 本地一次性 HTTP 服务端：把更新检测的 IO 实现指到它上面，
/// 既覆盖真实的 HTTP 路径，又不去碰 GitHub（也不依赖网络）。
Future<HttpServer> _serve(void Function(HttpRequest request) handler) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    handler(request);
  });
  return server;
}

void _respond(
  HttpRequest request,
  Object? body, {
  int status = 200,
  String contentType = 'application/json',
}) {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.parse(contentType);
  // 显式 UTF-8：response.write 默认按 latin1 编码，发布说明里的中文会直接抛
  // 「Contains invalid characters」，而 GitHub 返回的 body 就是 UTF-8。
  request.response.add(utf8.encode(body is String ? body : jsonEncode(body)));
  request.response.close();
}

void main() {
  group('版本比较', () {
    test('按数字段逐位比较，不是按字符串', () {
      // 字符串比较会把 4.10.0 判成比 4.9.0 旧，这是最常见的翻车方式。
      expect(isNewerVersion('4.10.0', '4.9.0'), isTrue);
      expect(isNewerVersion('4.9.0', '4.10.0'), isFalse);
      expect(isNewerVersion('4.1.3', '4.1.2'), isTrue);
      expect(isNewerVersion('5.0.0', '4.99.99'), isTrue);
      expect(isNewerVersion('4.1.3', '4.1.3'), isFalse);
      expect(isNewerVersion('4.1.2', '4.1.3'), isFalse);
    });

    test('段数不同时缺的段按 0 算', () {
      expect(isNewerVersion('4.2', '4.1.9'), isTrue);
      expect(isNewerVersion('4.1', '4.1.0'), isFalse);
      expect(isNewerVersion('4.1.0.1', '4.1'), isTrue);
    });

    test('吃 v 前缀、构建号与预发布标记', () {
      expect(parseVersion('v4.1.3'), [4, 1, 3]);
      expect(parseVersion('4.1.3+1'), [4, 1, 3]);
      expect(parseVersion(' 4.1.3-beta.1 '), [4, 1, 3]);
      expect(isNewerVersion('v4.2.0', '4.1.3'), isTrue);
      expect(isNewerVersion('4.1.3+2', '4.1.3+1'), isFalse);
    });

    test('解析不出数字段时不谎报有新版本', () {
      // 读不出当前版本（dev / 打包异常）时必须保持沉默：
      // 报一个不存在的新版本比不报更糟，用户会去下载一个没有的东西。
      expect(parseVersion('dev'), isNull);
      expect(parseVersion(''), isNull);
      expect(isNewerVersion('4.2.0', 'dev'), isFalse);
      expect(isNewerVersion('latest', '4.1.3'), isFalse);
    });
  });

  group('发布日期展示', () {
    test('按本地时区显示成 yyyy-MM-dd', () {
      final date = DateTime(2026, 9, 21, 10, 30);
      expect(formatReleaseDate(date), '2026-09-21');
      // 月 / 日补零，个位数日期也要对齐。
      expect(formatReleaseDate(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });

  group('GitHub 查询（真 HTTP，指向本地假服务端）', () {
    test('正常响应：取出标签、说明与发布页', () async {
      final server = await _serve((request) {
        expect(
          request.uri.path,
          '/repos/chengvar-glitch/no-shell/releases/latest',
        );
        // GitHub 缺 User-Agent 会 403，这条别被顺手删掉。
        expect(request.headers.value(HttpHeaders.userAgentHeader), isNotNull);
        _respond(request, {
          'tag_name': 'v4.2.0',
          'body': '修了一些东西',
          'html_url': 'https://example.invalid/releases/tag/v4.2.0',
        });
      });
      addTearDown(() => server.close(force: true));
      final client = HttpUpdateCheckClient(
        endpoint: Uri.parse(
          'http://127.0.0.1:${server.port}'
          '/repos/chengvar-glitch/no-shell/releases/latest',
        ),
      );

      final release = await client.fetchLatestRelease();
      expect(release.version, 'v4.2.0');
      expect(release.notes, '修了一些东西');
      expect(release.pageUrl, 'https://example.invalid/releases/tag/v4.2.0');
    });

    test('发布日期取 published_at，缺失时退回 created_at', () async {
      for (final (field, iso) in [
        ('published_at', '2026-09-21T10:00:00Z'),
        ('created_at', '2026-09-20T10:00:00Z'),
      ]) {
        final server = await _serve(
          (request) => _respond(request, {'tag_name': 'v4.2.0', field: iso}),
        );
        addTearDown(() => server.close(force: true));
        final client = HttpUpdateCheckClient(
          endpoint: Uri.parse('http://127.0.0.1:${server.port}/latest'),
        );

        final release = await client.fetchLatestRelease();
        expect(
          release.publishedAt?.toUtc().day,
          field == 'published_at' ? 21 : 20,
        );
      }
    });

    test('日期格式不对只少一条展示信息，不算查询失败', () async {
      final server = await _serve(
        (request) => _respond(request, {
          'tag_name': 'v4.2.0',
          'published_at': 'not-a-date',
        }),
      );
      addTearDown(() => server.close(force: true));
      final client = HttpUpdateCheckClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/latest'),
      );

      final release = await client.fetchLatestRelease();
      expect(release.version, 'v4.2.0');
      expect(release.publishedAt, isNull);
    });

    test('404 归成 notFound（一个版本都没发布）', () async {
      final server = await _serve(
        (request) => _respond(request, {'message': 'Not Found'}, status: 404),
      );
      addTearDown(() => server.close(force: true));
      final client = HttpUpdateCheckClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/latest'),
      );

      await expectLater(
        client.fetchLatestRelease(),
        throwsA(
          isA<ReleaseLookupException>().having(
            (e) => e.kind,
            'kind',
            ReleaseLookupError.notFound,
          ),
        ),
      );
    });

    test('5xx 归成 server', () async {
      final server = await _serve(
        (request) => _respond(request, 'boom', status: 503),
      );
      addTearDown(() => server.close(force: true));
      final client = HttpUpdateCheckClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/latest'),
      );

      await expectLater(
        client.fetchLatestRelease(),
        throwsA(
          isA<ReleaseLookupException>().having(
            (e) => e.kind,
            'kind',
            ReleaseLookupError.server,
          ),
        ),
      );
    });

    test('HTML 或残缺 JSON 归成 malformed，不是当成没有新版本', () async {
      for (final body in <String>['<html>portal login</html>', '{"a":1}']) {
        final server = await _serve((request) => _respond(request, body));
        addTearDown(() => server.close(force: true));
        final client = HttpUpdateCheckClient(
          endpoint: Uri.parse('http://127.0.0.1:${server.port}/latest'),
        );

        await expectLater(
          client.fetchLatestRelease(),
          throwsA(
            isA<ReleaseLookupException>().having(
              (e) => e.kind,
              'kind',
              ReleaseLookupError.malformed,
            ),
          ),
          reason: '响应是 $body',
        );
      }
    });

    test('连不上归成 network（端口上没人监听）', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close(force: true);
      final client = HttpUpdateCheckClient(
        endpoint: Uri.parse('http://127.0.0.1:$port/latest'),
        timeout: const Duration(seconds: 2),
      );

      await expectLater(
        client.fetchLatestRelease(),
        throwsA(
          isA<ReleaseLookupException>().having(
            (e) => e.kind,
            'kind',
            ReleaseLookupError.network,
          ),
        ),
      );
    });

    test('预发布版不推给只装正式版的用户', () async {
      final server = await _serve(
        (request) =>
            _respond(request, {'tag_name': 'v5.0.0-rc.1', 'prerelease': true}),
      );
      addTearDown(() => server.close(force: true));
      final client = HttpUpdateCheckClient(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/latest'),
      );

      await expectLater(
        client.fetchLatestRelease(),
        throwsA(
          isA<ReleaseLookupException>().having(
            (e) => e.kind,
            'kind',
            ReleaseLookupError.notFound,
          ),
        ),
      );
    });
  });
}
