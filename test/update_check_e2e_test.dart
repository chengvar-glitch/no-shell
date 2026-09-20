import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/app_version.dart';
import 'package:no_shell/main.dart';
import 'package:no_shell/update_check.dart';
import 'package:no_shell/widgets/settings_controls.dart';
import 'package:no_shell/widgets/sidebar.dart';
import 'package:package_info_plus_platform_interface/package_info_data.dart';
import 'package:package_info_plus_platform_interface/package_info_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/credential_store_fake.dart';

/// 假包信息：验证「当前版本来自宿主包信息」这条链路，
/// 而不是手写常量（手写常量的老问题就是它停在 4.0.1 不动）。
class _FakePackageInfo extends PackageInfoPlatform {
  _FakePackageInfo(this.version);

  final String version;

  @override
  Future<PackageInfoData> getAll({String? baseUrl}) async => PackageInfoData(
    appName: 'NoShell',
    packageName: 'com.noshell',
    version: version,
    buildNumber: '1',
    buildSignature: '',
  );
}

/// 假远端：本文件只验证**接线**（谁在什么时候查、查到之后界面怎么变），
/// 真实 HTTP 链路在 `update_check_client_test.dart` 里对着本地服务端跑
/// （那里是纯 test，能真开 socket；组件测试的假时钟跑不动真实网络）。
class _FakeClient implements UpdateCheckClient {
  _FakeClient(this.release);

  ReleaseInfo release;
  int calls = 0;

  @override
  Future<ReleaseInfo> fetchLatestRelease() async {
    calls++;
    return release;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('包信息是版本号的来源；读不到时才退回兜底常量', () async {
    PackageInfoPlatform.instance = _FakePackageInfo('4.1.3');
    appVersion = kFallbackAppVersion;
    await loadAppVersion();
    expect(appVersion, '4.1.3');
  });

  test('上次记录的「有新版」结论经 shared_preferences 跨重启保留', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const persistence = SharedPreferencesUpdateCheckPersistence();

    await persistence.saveAvailableVersion('v4.2.0');
    expect(await persistence.loadAvailableVersion(), 'v4.2.0');

    await persistence.saveAvailableVersion(null);
    expect(await persistence.loadAvailableVersion(), isNull);
  });

  testWidgets('端到端：启动静默查一次 → 红点 → 设置页给下载入口', (tester) async {
    PackageInfoPlatform.instance = _FakePackageInfo('4.1.3');
    appVersion = kFallbackAppVersion;
    await loadAppVersion();

    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final client = _FakeClient(
      ReleaseInfo(
        version: 'v4.2.0',
        notes: '- 修了一些东西',
        pageUrl: 'https://example.invalid/releases/tag/v4.2.0',
        publishedAt: DateTime(2026, 9, 21, 9),
      ),
    );
    Uri? opened;
    await tester.pumpWidget(
      NoShellApp(
        credentials: FakeCredentialStore(),
        updateCheckClient: client,
        updateCheckPersistence: const SharedPreferencesUpdateCheckPersistence(),
        // 不碰真实浏览器：只验证「点了要打开哪个地址」。
        openReleasePage: (uri) async {
          opened = uri;
          return true;
        },
      ),
    );
    await tester.pump();

    // 启动后静默查一次（默认延迟 4 秒）：不点任何东西也该有结论。
    expect(client.calls, 0, reason: '刚启动不该立刻联网');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(client.calls, 1, reason: '启动后应静默查一次');
    expect(
      find.descendant(
        of: find.byType(Sidebar),
        matching: find.byType(UpdateAvailableDot),
      ),
      findsOneWidget,
      reason: '有新版本时侧边栏设置入口要挂红点',
    );

    // 结论落盘：下次启动不联网也能提示。
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('update_available_version'), 'v4.2.0');

    // 打开设置：更新分区里既有行上的当前版本，也有结果块摊开的细节
    // （新版本号 + 发布日期 + 当前版本）与更新说明。
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(UpdateSettingsRow),
        matching: find.text('有新版本 v4.2.0'),
      ),
      findsOneWidget,
    );
    expect(find.text('发布于 2026-09-21 · 当前版本 v4.1.3'), findsOneWidget);

    // 更新分区排在设置弹窗最下面，窄一点的窗口里要先滚到可见位置。
    Future<void> scrollTo(Finder target) async {
      if (tester.any(target) &&
          tester.getCenter(target).dy <= tester.view.physicalSize.height) {
        return;
      }
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    await scrollTo(find.text('更新说明'));
    await tester.tap(find.text('更新说明'));
    await tester.pumpAndSettle();
    expect(find.text('· 修了一些东西'), findsOneWidget);

    // 点「前往下载」：交给系统打开正确的发布页。
    final download = find.text('前往下载');
    await scrollTo(download);
    await tester.tap(download);
    await tester.pumpAndSettle();
    expect(opened.toString(), 'https://example.invalid/releases/tag/v4.2.0');
  });

  testWidgets('启动时不查：落盘的上次结论已经够亮起红点', (tester) async {
    PackageInfoPlatform.instance = _FakePackageInfo('4.1.3');
    appVersion = kFallbackAppVersion;
    await loadAppVersion();

    // 上次会话已经查明 4.2.0 可用（落盘记录），这次启动还没到联网时间。
    SharedPreferences.setMockInitialValues(<String, Object>{
      'update_available_version': 'v4.2.0',
    });
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final client = _FakeClient(
      const ReleaseInfo(version: 'v4.2.0', notes: '', pageUrl: null),
    );
    await tester.pumpWidget(
      NoShellApp(
        credentials: FakeCredentialStore(),
        updateCheckClient: client,
        updateCheckPersistence: const SharedPreferencesUpdateCheckPersistence(),
        openReleasePage: (uri) async => true,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(client.calls, 0);
    expect(
      find.descendant(
        of: find.byType(Sidebar),
        matching: find.byType(UpdateAvailableDot),
      ),
      findsOneWidget,
    );
  });
}
