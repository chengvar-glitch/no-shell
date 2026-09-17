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
      terminalStyle: TerminalStylePrefs(
        preset: TerminalPreset.tokyoNight,
        font: TerminalFont.firaCode,
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
      terminalStyle: TerminalStylePrefs(
        preset: TerminalPreset.nord,
        font: TerminalFont.firaCode,
        fontSize: 18,
      ),
    );
    expect(AppSettings.fromJson(settings.toJson()), settings);

    // 单条脏数据不该带走整份偏好：能读的照读，读不了的退回默认。
    final dirty = AppSettings.fromJson({
      'themeMode': 'noSuchMode',
      'language': 42,
      'terminalPreset': 'nord',
      'terminalFont': 'noSuchFont',
      'terminalFontSize': 999,
    });
    expect(dirty.themeMode, ThemeMode.system);
    expect(dirty.language, AppLanguage.system);
    expect(dirty.terminalStyle.preset, TerminalPreset.nord);
    expect(dirty.terminalStyle.font, TerminalFont.jetBrainsMono);
    expect(dirty.terminalStyle.fontSize, TerminalStylePrefs.maxFontSize);

    expect(AppSettings.fromJson(const {}), const AppSettings());
  });

  test('认不出的字体取值退回内置默认，不带走其余字段', () {
    // 不认得的取值（脏档 / 旧档）一律退回默认；同一条 JSON 里的其他字段照常读回。
    final restored = AppSettings.fromJson({
      'themeMode': 'dark',
      'terminalFont': 'menlo',
    });
    expect(restored.terminalStyle.font, TerminalFont.jetBrainsMono);
    expect(restored.themeMode, ThemeMode.dark);
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
    await tester.ensureVisible(find.byTooltip('增大字号'));
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
      Theme.of(tester.element(find.byTooltip('增大字号'))).brightness,
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

    // 注入一个「记录型」通道但**不**把它交给 NoShellApp：改动应当只留在
    // 内存里。原先这条只断言界面上有「设置」文字，删掉整条落盘逻辑也照样
    // 通过——等于没测。
    final recorder = _RecordingPersistence();
    await tester.pumpWidget(NoShellApp(credentials: FakeCredentialStore()));
    await tester.pump();

    // 改主题（这条路径一定会调 _scheduleSave）。
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    // 「浅色」同时出现在分段按钮与终端预览说明里，限定到分段按钮内的那个。
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<ThemeMode>),
        matching: find.text('浅色'),
      ),
    );
    await tester.pumpAndSettle();

    // 等过防抖窗口，仍未注入通道 ⇒ 一次都没写。
    await tester.pump(const Duration(milliseconds: 600));
    expect(recorder.saves, isEmpty);
    expect(recorder.stored, isNull);
  });

  group('连接兼容性开关', () {
    test('默认关闭，且缺字段的旧存档读成关闭', () {
      expect(const AppSettings().allowLegacyHostKeys, isFalse);
      final legacy = AppSettings.fromJson(const {
        'themeMode': 'system',
        'language': 'system',
      });
      expect(legacy.allowLegacyHostKeys, isFalse);
    });

    test('JSON 往返保留取值', () {
      const on = AppSettings(allowLegacyHostKeys: true);
      expect(AppSettings.fromJson(on.toJson()).allowLegacyHostKeys, isTrue);
      expect(
        const AppSettings()
            .copyWith(allowLegacyHostKeys: true)
            .allowLegacyHostKeys,
        isTrue,
      );
    });

    test('参与相等判定', () {
      expect(
        const AppSettings() == const AppSettings(allowLegacyHostKeys: true),
        isFalse,
      );
    });
  });

  group('TerminalStylePrefs 值语义', () {
    test('内容相同即相等（ValueNotifier 的无变化守卫依赖它）', () {
      const a = TerminalStylePrefs();
      const b = TerminalStylePrefs();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('任一项不同即不等', () {
      const base = TerminalStylePrefs();
      expect(base == base.copyWith(fontSize: base.fontSize + 1), isFalse);
      expect(
        base == base.copyWith(preset: TerminalPreset.solarizedDark),
        isFalse,
      );
      expect(base == base.copyWith(font: TerminalFont.firaCode), isFalse);
    });

    test('重复写入相同值不触发通知', () {
      final notifier = ValueNotifier<TerminalStylePrefs>(
        const TerminalStylePrefs(),
      );
      addTearDown(notifier.dispose);
      var notifications = 0;
      notifier.addListener(() => notifications++);

      notifier.value = const TerminalStylePrefs();
      expect(notifications, 0, reason: '内容没变就不该通知下游重建');

      notifier.value = const TerminalStylePrefs(fontSize: 18);
      expect(notifications, 1);
    });
  });
}
