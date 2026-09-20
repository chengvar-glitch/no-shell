import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/app_version.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/theme.dart';
import 'package:no_shell/update_check.dart';
import 'package:no_shell/widgets/settings_controls.dart';

/// 假查询通道：按用例给定的结果或错误作答，一次调用一次应答。
class _FakeClient implements UpdateCheckClient {
  _FakeClient({this.release, this.error});

  ReleaseInfo? release;
  ReleaseLookupException? error;
  int calls = 0;

  @override
  Future<ReleaseInfo> fetchLatestRelease() async {
    calls++;
    final error = this.error;
    if (error != null) throw error;
    return release!;
  }
}

/// 假落盘通道：只记最后一次写入。
class _FakePersistence implements UpdateCheckPersistence {
  _FakePersistence([this.saved]);

  String? saved;
  int saves = 0;

  @override
  Future<String?> loadAvailableVersion() async => saved;

  @override
  Future<void> saveAvailableVersion(String? version) async {
    saves++;
    saved = version;
  }
}

ReleaseInfo _release(String version, {String? pageUrl}) =>
    ReleaseInfo(version: version, notes: '', pageUrl: pageUrl);

void main() {
  // 测试期间当前版本固定，免得跟着 pubspec 走（版本比较的用例才有确定性）。
  final originalVersion = appVersion;
  setUp(() => appVersion = '4.1.3');
  tearDown(() => appVersion = originalVersion);

  UpdateCheckService service({
    required UpdateCheckClient client,
    UpdateCheckPersistence? persistence,
  }) => UpdateCheckService(
    client: client,
    persistence: persistence,
    // 不排启动计时器：测试关心的是手动检查与已有结论，挂着的计时器
    // 只会让 pumpAndSettle 等到它到期。
    startupDelay: null,
  );

  group('读取上次结论', () {
    test('上次记录的新版本号比当前新：不联网就先挂上提示', () async {
      final client = _FakeClient();
      final check = service(
        client: client,
        persistence: _FakePersistence('4.2.0'),
      );

      await check.load();

      expect(check.updateAvailable, isTrue);
      expect(check.latestVersion, '4.2.0');
      expect(client.calls, 0, reason: '读落盘结论不该联网');
    });

    test('上次记录的版本已经不新了（用户装上了）：不提示', () async {
      final check = service(
        client: _FakeClient(),
        persistence: _FakePersistence('4.1.3'),
      );

      await check.load();

      expect(check.updateAvailable, isFalse);
      expect(check.latestVersion, isNull);
    });

    test('没有落盘通道时不炸：只是没有跨重启的记忆', () async {
      final check = service(client: _FakeClient());

      await check.load();

      expect(check.updateAvailable, isFalse);
    });
  });

  group('启动静默检查', () {
    test('延迟到点才查，且只排一次', () {
      fakeAsync((async) {
        final client = _FakeClient(release: _release('v4.2.0'));
        final check = UpdateCheckService(
          client: client,
          startupDelay: const Duration(seconds: 4),
        );

        check.scheduleStartupCheck();
        check.scheduleStartupCheck();
        async.elapse(const Duration(seconds: 3));
        expect(client.calls, 0, reason: '3 秒时还不该联网');

        async.elapse(const Duration(seconds: 2));
        expect(client.calls, 1, reason: '到点只查一次，重复调度无副作用');
        expect(check.updateAvailable, isTrue);
        check.dispose();
      });
    });

    test('已经知道有新版时跳过，省一次请求', () {
      fakeAsync((async) {
        final client = _FakeClient(release: _release('v4.2.0'));
        final check = UpdateCheckService(
          client: client,
          persistence: _FakePersistence('4.2.0'),
          startupDelay: const Duration(seconds: 4),
        );
        check.load();
        async.flushMicrotasks();

        check.scheduleStartupCheck();
        async.elapse(const Duration(seconds: 10));

        expect(client.calls, 0);
        check.dispose();
      });
    });

    test('dispose 后计时器不再触发（关窗后不留下悬挂的联网）', () {
      fakeAsync((async) {
        final client = _FakeClient(release: _release('v4.2.0'));
        final check = UpdateCheckService(
          client: client,
          startupDelay: const Duration(seconds: 4),
        );

        check.scheduleStartupCheck();
        check.dispose();
        async.elapse(const Duration(seconds: 30));

        expect(client.calls, 0);
      });
    });
  });

  group('检查结果', () {
    test('查到更新的版本：置结论、落盘、通知一次', () async {
      final client = _FakeClient(
        release: _release('v4.2.0', pageUrl: 'https://example.invalid/v4.2.0'),
      );
      final persistence = _FakePersistence();
      final check = service(client: client, persistence: persistence);
      var notifications = 0;
      check.addListener(() => notifications++);

      final available = await check.check();

      expect(available, isTrue);
      expect(check.status, UpdateCheckStatus.done);
      expect(check.latestVersion, 'v4.2.0');
      expect(check.releasePageUrl, 'https://example.invalid/v4.2.0');
      expect(persistence.saved, 'v4.2.0');
      expect(notifications, greaterThan(0));
    });

    test('已是最新：不发提示，并把上次的落盘记录撤掉', () async {
      final persistence = _FakePersistence('4.2.0');
      final check = service(
        client: _FakeClient(release: _release('v4.1.3')),
        persistence: persistence,
      );

      final available = await check.check();

      expect(available, isFalse);
      expect(check.updateAvailable, isFalse);
      expect(check.latestVersion, isNull);
      expect(persistence.saved, isNull, reason: '追上版本后旧记录必须撤掉');
    });

    test('解析不到发布页地址时落到发布页总入口', () async {
      final check = service(client: _FakeClient(release: _release('v4.2.0')));

      await check.check();

      expect(check.releasePageUrl, kReleasesPageUrl);
    });

    test('查询失败：归类落下，且不吞掉上次「有新版」的结论', () async {
      final client = _FakeClient(release: _release('v4.2.0'));
      final check = service(client: client, persistence: _FakePersistence());
      await check.check();
      expect(check.updateAvailable, isTrue);

      client.error = const ReleaseLookupException(ReleaseLookupError.network);
      final available = await check.check();

      expect(available, isFalse);
      expect(check.status, UpdateCheckStatus.failed);
      expect(check.failure, UpdateCheckFailure.network);
      expect(check.updateAvailable, isTrue, reason: '一次网络抖动不该把已经查明的新版提示抹掉');
    });

    test('各类失败各归各类', () async {
      final cases = {
        ReleaseLookupError.network: UpdateCheckFailure.network,
        ReleaseLookupError.notFound: UpdateCheckFailure.notFound,
        ReleaseLookupError.server: UpdateCheckFailure.server,
        ReleaseLookupError.malformed: UpdateCheckFailure.malformed,
      };
      for (final entry in cases.entries) {
        final check = service(
          client: _FakeClient(error: ReleaseLookupException(entry.key)),
        );

        await check.check();

        expect(check.failure, entry.value, reason: '${entry.key} 的归类');
      }
    });

    test('未归类的异常兜底成 network，不让一次检查把界面打崩', () async {
      final check = service(client: _ThrowingClient());

      await check.check();

      expect(check.status, UpdateCheckStatus.failed);
      expect(check.failure, UpdateCheckFailure.network);
    });

    test('平台不支持（web 桩）与查询失败分开归类', () async {
      final check = service(client: _UnsupportedClient());

      await check.check();

      expect(check.failure, UpdateCheckFailure.unsupported);
    });
  });

  // 纯判定要文案与配色，测试里固定用中文 + 浅色主题，断言才有确定性。
  final zh = lookupAppLocalizations(const Locale('zh'));
  final light = AppTheme.light();

  UpdateResultView? viewOf(UpdateCheckService check) =>
      updateResultViewOf(check, l10n: zh, theme: light);

  group('结果该怎么显示（纯判定）', () {
    test('没查过就不接管那一行', () {
      // 启动时那次静默查询之外的「空闲」态不该让设置页凭空多出结论文案。
      expect(viewOf(service(client: _FakeClient())), isNull);
    });

    test('查到新版 → 标题换成「有新版本」，带上说明与发布日期', () async {
      final check = service(
        client: _FakeClient(
          release: ReleaseInfo(
            version: 'v4.2.0',
            notes: '修了一些东西',
            pageUrl: null,
            publishedAt: DateTime(2026, 9, 21),
          ),
        ),
      );
      await check.check();

      final view = viewOf(check)!;
      expect(view.title, '有新版本 v4.2.0');
      expect(view.detail, '发布于 2026-09-21 · 当前版本 v4.1.3');
      expect(view.newer?.notes, '修了一些东西');
      // 有新版本用主题主色（不是状态色），与红点的语义一致。
      expect(view.color, light.colorScheme.primary);
    });

    test('已是最新 → 标题就是「已是最新版本」，用已连接绿', () async {
      final check = service(client: _FakeClient(release: _release('v4.1.3')));
      await check.check();

      final view = viewOf(check)!;
      expect(view.title, '已是最新版本');
      expect(view.detail, '当前版本 v4.1.3');
      expect(view.color, light.statusColor(ServerStatus.connected));
      expect(view.newer, isNull, reason: '没有新版就不该有更新说明');
    });

    test('查失败 → 标题写原因、用红色，绝不说成「已是最新」', () async {
      // 这一条是这个功能最容易翻车的地方：查失败被显示成「已是最新」，
      // 用户会以为自己已经是最新版而不再检查。
      final client = _FakeClient(release: _release('v4.2.0'));
      final check = service(client: client);
      await check.check();

      client.error = const ReleaseLookupException(ReleaseLookupError.network);
      await check.check();

      final view = viewOf(check)!;
      expect(view.title, '连不上发布服务器，请检查网络后重试');
      expect(view.title, isNot('已是最新版本'));
      expect(view.color, light.statusColor(ServerStatus.error));
    });

    test('查询进行中 → 标题是「检查中…」', () {
      final check = service(client: _FakeClient(release: _release('v4.2.0')));
      // 不 await：就是要看 in-flight 的那一瞬。
      check.check();
      expect(viewOf(check)!.title, '检查中…');
    });

    test('结论来自上次会话（无发布日期）时不编一个日期出来', () async {
      final check = service(
        client: _FakeClient(),
        persistence: _FakePersistence('4.2.0'),
      );
      await check.load();

      final view = viewOf(check)!;
      expect(view.title, '有新版本 4.2.0');
      expect(view.detail, '当前版本 v4.1.3');
    });
  });

  // 标题只有 13px，按 WCAG AA 小字门槛要求 4.5:1。结果标题是状态色，
  // 得在分组卡片的底色上量（不是页面底色）——那里才是它实际压着的颜色。
  group('结果标题的对比度', () {
    double luminance(Color color) {
      double linear(double channel) => channel <= 0.03928
          ? channel / 12.92
          : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * linear(color.r) +
          0.7152 * linear(color.g) +
          0.0722 * linear(color.b);
    }

    double contrast(Color a, Color b) {
      final la = luminance(a);
      final lb = luminance(b);
      final hi = math.max(la, lb);
      final lo = math.min(la, lb);
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final entry in {
      '浅色': AppTheme.light(),
      '深色': AppTheme.dark(),
    }.entries) {
      final theme = entry.value;
      for (final (label, color) in [
        ('已是最新（绿）', theme.statusColor(ServerStatus.connected)),
        ('有新版本（主色）', theme.colorScheme.primary),
        ('查询失败（红）', theme.statusColor(ServerStatus.error)),
      ]) {
        test('${entry.key}主题 · $label ≥ 4.5:1', () {
          expect(
            contrast(color, theme.panelBackground),
            greaterThanOrEqualTo(4.5),
          );
        });
      }
    }
  });

  group('设置面板里的更新分区', () {
    Future<void> pumpRow(
      WidgetTester tester,
      UpdateCheckService check, {
      Future<bool> Function(Uri uri)? open,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: light,
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(
            children: [
              UpdateSettingsRow(updateCheck: check, openReleasePage: open),
            ],
          ),
        ),
      ),
    );

    testWidgets('初始状态：标题是「检查更新」，副标题是当前版本', (tester) async {
      await pumpRow(tester, service(client: _FakeClient()));

      expect(find.text('更新'), findsOneWidget);
      expect(find.text('检查更新'), findsOneWidget);
      expect(find.text('当前版本 v4.1.3'), findsOneWidget);
      expect(find.text('检查'), findsOneWidget);
    });

    testWidgets('已是最新：那一行的标题被结果顶掉，不再显示「检查更新」', (tester) async {
      final check = service(client: _FakeClient(release: _release('v4.1.3')));
      await pumpRow(tester, check);

      await tester.tap(find.text('检查'));
      await tester.pumpAndSettle();

      expect(find.text('已是最新版本'), findsOneWidget);
      expect(find.text('检查更新'), findsNothing, reason: '结果要顶掉原来的标题');
      expect(find.text('当前版本 v4.1.3'), findsOneWidget);
      // 已是最新：没有下载可点，但保留「检查」——用户想再确认一次
      // （比如刚看到新版本发布了）得有地方点。
      expect(find.text('前往下载'), findsNothing);
      expect(find.text('检查'), findsOneWidget);
      // 标题用的是已连接绿。
      final title = tester.widget<Text>(find.text('已是最新版本'));
      expect(title.style?.color, light.statusColor(ServerStatus.connected));
    });

    testWidgets('查到新版：标题换成新版本号与发布日期，更新说明可就地展开', (tester) async {
      final check = service(
        client: _FakeClient(
          release: ReleaseInfo(
            version: 'v4.2.0',
            notes: '## 修复\n- 状态胶囊不再误报\n- 更快的重连',
            pageUrl: 'https://example.invalid/dl',
            publishedAt: DateTime(2026, 9, 21, 10, 30),
          ),
        ),
      );
      Uri? opened;
      await pumpRow(
        tester,
        check,
        open: (uri) async {
          opened = uri;
          return true;
        },
      );

      await tester.tap(find.text('检查'));
      await tester.pumpAndSettle();

      expect(find.text('有新版本 v4.2.0'), findsOneWidget);
      expect(find.text('发布于 2026-09-21 · 当前版本 v4.1.3'), findsOneWidget);
      expect(find.text('检查更新'), findsNothing);

      // 更新说明默认收起，点开才显示，且 Markdown 记号已经收拾干净。
      expect(find.text('更新说明'), findsOneWidget);
      expect(find.textContaining('状态胶囊不再误报'), findsNothing);
      await tester.tap(find.text('更新说明'));
      await tester.pumpAndSettle();
      expect(find.text('修复\n· 状态胶囊不再误报\n· 更快的重连'), findsOneWidget);

      await tester.tap(find.text('前往下载'));
      await tester.pumpAndSettle();
      expect(opened.toString(), 'https://example.invalid/dl');
    });

    testWidgets('没有更新说明时不给「更新说明」按钮', (tester) async {
      final check = service(client: _FakeClient(release: _release('v4.2.0')));
      await pumpRow(tester, check);

      await tester.tap(find.text('检查'));
      await tester.pumpAndSettle();

      expect(find.text('有新版本 v4.2.0'), findsOneWidget);
      expect(find.text('更新说明'), findsNothing);
    });

    testWidgets('打不开浏览器时给出提示，而不是点了没反应', (tester) async {
      final check = service(client: _FakeClient(release: _release('v4.2.0')));
      await pumpRow(tester, check, open: (uri) async => false);

      await tester.tap(find.text('检查'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('前往下载'));
      await tester.pumpAndSettle();

      expect(find.text('无法打开发布页'), findsOneWidget);
    });

    testWidgets('查询失败：那一行写明原因并换成「重试」，重试成功后翻成新版', (tester) async {
      final client = _FakeClient(
        error: const ReleaseLookupException(ReleaseLookupError.network),
      );
      final check = service(client: client);
      await pumpRow(tester, check);

      await tester.tap(find.text('检查'));
      await tester.pumpAndSettle();

      expect(find.text('连不上发布服务器，请检查网络后重试'), findsOneWidget);
      expect(find.text('检查更新'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);

      client.error = null;
      client.release = _release('v4.2.0');
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(find.text('连不上发布服务器，请检查网络后重试'), findsNothing);
      expect(find.text('有新版本 v4.2.0'), findsOneWidget);
    });

    testWidgets('平台不支持：说明原因但不给「重试」', (tester) async {
      final check = service(client: _UnsupportedClient());
      await pumpRow(tester, check);

      await tester.tap(find.text('检查'));
      await tester.pumpAndSettle();

      expect(find.text('当前平台不支持检测更新'), findsOneWidget);
      // 重试点了也是同样结果，所以不给；但「检查」留着，
      // 免得这个平台上的用户觉得按钮凭空消失了。
      expect(find.text('重试'), findsNothing);
      expect(find.text('检查'), findsOneWidget);
    });

    testWidgets('未注入检测服务时整块不显示', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: light,
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(
              children: const [UpdateSettingsRow(updateCheck: null)],
            ),
          ),
        ),
      );

      expect(find.text('检查更新'), findsNothing);
    });
  });
}

class _ThrowingClient implements UpdateCheckClient {
  @override
  Future<ReleaseInfo> fetchLatestRelease() async => throw StateError('boom');
}

class _UnsupportedClient implements UpdateCheckClient {
  @override
  Future<ReleaseInfo> fetchLatestRelease() async =>
      throw UnsupportedError('nope');
}
