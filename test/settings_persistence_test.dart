import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:no_shell/app_locale.dart';
import 'package:no_shell/main.dart';
import 'package:no_shell/settings.dart';
import 'package:no_shell/settings_persistence.dart';

import 'support/credential_store_fake.dart';

/// 记录写入的内存假实现：断言「什么时候、写了什么」。
final class _RecordingPersistence implements SettingsPersistence {
  _RecordingPersistence([this.stored]);

  AppSettings? stored;
  final List<AppSettings> saves = [];

  @override
  Future<AppSettings?> load() async => stored;

  @override
  Future<void> save(AppSettings settings) async {
    saves.add(settings);
    stored = settings;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shared_preferences 实现：写入能原样读回，脏存档读成 null', () async {
    SharedPreferences.setMockInitialValues({});
    final persistence = SharedPreferencesSettingsPersistence();
    expect(await persistence.load(), isNull, reason: '从未保存过');

    const saved = AppSettings(
      themeMode: ThemeMode.dark,
      language: AppLanguage.chinese,
      uiFont: UiFont.monospace,
      terminalStyle: TerminalStylePrefs(
        preset: TerminalPreset.tokyoNight,
        font: TerminalFont.custom,
        customFontName: 'Sarasa Mono SC',
        fontSize: 17,
      ),
    );
    await persistence.save(saved);
    expect(await persistence.load(), saved, reason: '落盘再读回应完全一致');

    // 脏存档（不是 JSON）按「没有存档」处理，让下次保存覆盖成干净数据。
    SharedPreferences.setMockInitialValues({'app_settings_v1': 'not json'});
    expect(await persistence.load(), isNull);
  });

  test('偏好快照 JSON 往返；脏字段只退回该字段的默认值', () {
    const settings = AppSettings(
      themeMode: ThemeMode.dark,
      language: AppLanguage.english,
      uiFont: UiFont.monospace,
      terminalStyle: TerminalStylePrefs(
        preset: TerminalPreset.nord,
        font: TerminalFont.custom,
        customFontName: 'Fira Code',
        fontSize: 18,
      ),
    );
    expect(AppSettings.fromJson(settings.toJson()), settings);

    // 单条脏数据不该带走整份偏好：能读的照读，读不了的退回默认。
    final dirty = AppSettings.fromJson({
      'themeMode': 'noSuchMode',
      'language': 42,
      'terminalPreset': 'nord',
      'terminalFont': 'custom',
      'terminalFontSize': 999,
    });
    expect(dirty.themeMode, ThemeMode.system);
    expect(dirty.language, AppLanguage.system);
    expect(dirty.terminalStyle.preset, TerminalPreset.nord);
    expect(dirty.terminalStyle.font, TerminalFont.custom);
    expect(dirty.terminalStyle.fontSize, TerminalStylePrefs.maxFontSize);
    expect(dirty.terminalStyle.customFontName, '');

    expect(AppSettings.fromJson(const {}), const AppSettings());
  });

  testWidgets('启动即应用落盘偏好，改动在防抖后写回', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final persistence = _RecordingPersistence(
      const AppSettings(
        themeMode: ThemeMode.dark,
        language: AppLanguage.chinese,
        terminalStyle: TerminalStylePrefs(
          preset: TerminalPreset.dracula,
          fontSize: 18,
        ),
      ),
    );

    await tester.pumpWidget(
      NoShellApp(
        credentials: FakeCredentialStore(),
        settings: persistence,
        initialSettings: await persistence.load(),
      ),
    );
    await tester.pump();

    // 落盘的主题 / 语言 / 终端偏好在首帧就已生效，不闪默认值。
    expect(
      Theme.of(tester.element(find.text('设置'))).brightness,
      Brightness.dark,
    );
    final scope = TerminalStyleScope.of(tester.element(find.text('设置')));
    expect(scope.notifier.value.preset, TerminalPreset.dracula);
    expect(scope.notifier.value.fontSize, 18);
    expect(persistence.saves, isEmpty, reason: '只是启动，不该回写');

    // 打开设置改字号：防抖窗口内合并写盘。
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('终端字号'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('增大字号'));
    await tester.pump();
    expect(persistence.saves, isEmpty, reason: '防抖窗口内先不落盘');
    await tester.pump(const Duration(milliseconds: 500));
    expect(persistence.saves.last.terminalStyle.fontSize, 19);

    // 关掉弹窗（点「完成」）立即补写一次，且主题改动也在里面。
    // 「浅色」既是主题段的一项、也是终端浅色预设的名字，这里限定在主题分段里；
    // 上一步把内容滚到了终端分区，先滚回外观分区再点。
    final lightOption = find.descendant(
      of: find.byType(SegmentedButton<ThemeMode>),
      matching: find.text('浅色'),
    );
    await tester.ensureVisible(lightOption);
    await tester.pumpAndSettle();
    await tester.tap(lightOption);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('终端字号'))).brightness,
      Brightness.light,
      reason: '主题应已切到浅色',
    );
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(persistence.saves.last.themeMode, ThemeMode.light);
    expect(persistence.saves.last.terminalStyle.fontSize, 19);
  });

  testWidgets('未注入落盘通道时不写盘（测试与嵌入方默认行为）', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    await tester.pumpWidget(NoShellApp(credentials: FakeCredentialStore()));
    await tester.pump();

    expect(find.text('设置'), findsOneWidget);
    expect(Theme.of(tester.element(find.text('设置'))).brightness, isNotNull);
  });
}
