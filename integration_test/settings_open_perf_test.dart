// 设置弹窗打开性能探针：量桌面端「点侧边栏设置 → 弹窗内容真正布局并出帧」的墙钟与
// 逐帧 build / raster 耗时，并对比首开 / 二次 / 三次，判断这笔开销是「一次性预热」
// 还是「每次都要付的树构建成本」。
//
// 另外两组微探针：
// - 字重探针：App 已经画过 w400/w500/w600/w700 之后，首次使用一个从未用过的字重
//   （w100 细体 / w300 轻体 / w900 黑体）画一个 Text，首次 vs 重复（换一组字形相同
//   字重但字符不同的文本）。验证「Linux 上首次使用新字重会去 fontconfig 命中并解析
//   另一个 16~27MB 的 CJK .ttc」这个假设——正负结果都有意义。
// - 组件探针：把设置弹窗里的真实控件（UiFontDropdown / TerminalPresetDropdown /
//   TerminalFontDropdown / TerminalFontSizeControl / AppIconMark / SegmentedButton）
//   逐个丢进浮层单独首次构建，用来定位首开那 1s 到底花在哪个控件上。
//
// SETTINGS_PERF_ORDER 控制顺序（默认 dialog）：
//   dialog     启动 → 设置弹窗 ×3 → 字重探针 → 组件探针 → 空 Dialog 对照
//   emptyfirst 启动 → 空 Dialog ×2（对照）→ 设置弹窗 ×1 → 字重探针 → 组件探针
//   compfirst  启动 → 组件探针 → 设置弹窗 ×1 → 字重探针
//
// 运行（profile，AOT，帧耗时才有参考价值）：
//   /opt/flutter/bin/flutter drive --profile -d linux \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/settings_open_perf_test.dart
// 对照（debug，JIT，数字只反映开发链路）：
//   /opt/flutter/bin/flutter test integration_test/settings_open_perf_test.dart -d linux
//
// 报告：build/settings_open_perf_{profile|debug}.json + stdout 表格。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

import 'package:no_shell/app_locale.dart';
import 'package:no_shell/home_page.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/settings.dart';
import 'package:no_shell/ssh/session_manager.dart';
import 'package:no_shell/store.dart';
import 'package:no_shell/theme.dart';
import 'package:no_shell/widgets/app_icon_mark.dart';
import 'package:no_shell/widgets/settings_controls.dart';
import 'package:no_shell/widgets/sidebar.dart';

import '../test/support/credential_store_fake.dart';
import '../test/support/sftp_fakes.dart';

double _ms(Duration d) => d.inMicroseconds / 1000;

double _maxOf(Iterable<double> values) {
  var best = 0.0;
  for (final v in values) {
    if (v > best) best = v;
  }
  return best;
}

double _sumOf(Iterable<double> values) {
  var total = 0.0;
  for (final v in values) {
    total += v;
  }
  return total;
}

double _r1(double v) => double.parse(v.toStringAsFixed(1));

/// 帧耗时收集器：累积所有 FrameTiming，并支持等待「下一批」到达
/// （FrameTiming 在光栅化完成后回传，因此它的到达本身就证明该帧已经 present）。
final class _TimingSink {
  _TimingSink(this.binding) {
    binding.addTimingsCallback(_onBatch);
  }

  final IntegrationTestWidgetsFlutterBinding binding;
  final List<FrameTiming> all = <FrameTiming>[];
  final List<Completer<void>> _waiters = <Completer<void>>[];

  void _onBatch(List<FrameTiming> batch) {
    all.addAll(batch);
    final waiters = List<Completer<void>>.of(_waiters);
    _waiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  /// 等下一批帧耗时；超时返回 false（不抛异常），避免环境问题把测试挂死。
  Future<bool> waitForBatch({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final completer = Completer<void>();
    _waiters.add(completer);
    try {
      await completer.future.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  void dispose() => binding.removeTimingsCallback(_onBatch);
}

/// 浮层探针：只画一个小控件，用来单独测「首次构建」的成本。
final class _Probe {
  const _Probe(this.child);

  final Widget child;
}

/// `/proc/loadavg` 只有 Linux 有：其它平台返回空串，不影响测量本身
/// （这份探针要能在 Linux / macOS / Windows 上跑，见 .github/workflows/perf-probe.yml）。
String loadAvgText() {
  try {
    return File('/proc/loadavg').readAsStringSync().trim();
  } catch (_) {
    return '';
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('设置弹窗打开耗时（首开 / 二次 / 三次）+ 微探针', (tester) async {
    final order = Platform.environment['SETTINGS_PERF_ORDER'] ?? 'dialog';
    // 语系 A/B：en 这一档整条链路只有拉丁文本，用来判断那 1s 是不是 CJK 字形专属。
    final localeCode = order == 'en' ? 'en' : 'zh';
    final l10n = lookupAppLocalizations(Locale(localeCode));
    tester.platformDispatcher.localesTestValue = [Locale(localeCode)];
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    // 生产窗口尺寸（1536x864），避免尺寸差异影响结论。
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1536, 864));
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // SETTINGS_PERF_STORE=empty 用来对照「空主机列表的首页从不渲染 w600/w700」这一假设。
    final storeMode = Platform.environment['SETTINGS_PERF_STORE'] ?? 'one';
    final store = ServerStore(seed: storeMode == 'empty' ? [] : [testServer()]);
    final sessions = SessionManager(store: store);
    addTearDown(sessions.dispose);
    final style = ValueNotifier<TerminalStylePrefs>(const TerminalStylePrefs());
    addTearDown(style.dispose);
    final probe = ValueNotifier<_Probe?>(null);
    addTearDown(probe.dispose);

    final sink = _TimingSink(binding);
    addTearDown(sink.dispose);

    final navigatorKey = GlobalKey<NavigatorState>();
    // 「设置」入口：侧边栏底部整行。用图标而不是文案定位，locale A/B 时都能用。
    final settingsRow = find.descendant(
      of: find.byType(Sidebar),
      matching: find.byIcon(Icons.settings_outlined),
    );
    // 设置弹窗内容已布局的判据：设置弹窗独有的分段控件。
    final dialogContent = find.byType(SegmentedButton<ThemeMode>);
    // 底部「完成」是弹窗里唯一的 FilledButton，同样不依赖文案。
    final dialogDone = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(FilledButton),
    );
    const emptyDialogMarker = '空洞探针';
    final emptyDialogContent = find.text(emptyDialogMarker);

    /// pump 一次的墙钟（live binding 下 [pump] 在 handleDrawFrame 之后返回，
    /// 因此这个数字约等于该帧 UI 线程成本，也就是 FrameTiming.buildDuration）。
    Future<int> pumpTimed() async {
      final watch = Stopwatch()..start();
      await tester.pump();
      return watch.elapsedMilliseconds;
    }

    Future<int> waitTimings(int seenBefore) async {
      if (sink.all.length > seenBefore) return 0;
      final watch = Stopwatch()..start();
      final ok = await sink.waitForBatch();
      return ok ? watch.elapsedMilliseconds : -1;
    }

    /// 等到一批「真帧」耗时回传（build+raster ≥ [minMs]），用来跳过 App 起来之前
    /// 引擎画的空帧。返回是否等到。
    Future<bool> waitForRealFrame(
      int seenBefore, {
      double minMs = 1,
      Duration timeout = const Duration(seconds: 20),
    }) async {
      final watch = Stopwatch()..start();
      while (watch.elapsed < timeout) {
        final pending = sink.all.length - seenBefore;
        if (pending > 0) {
          final fresh = sink.all.sublist(seenBefore);
          final hasReal = fresh.any(
            (f) => _ms(f.buildDuration) + _ms(f.rasterDuration) >= minMs,
          );
          if (hasReal) return true;
        }
        if (!await sink.waitForBatch(timeout: const Duration(seconds: 2))) {
          return false;
        }
      }
      return false;
    }

    // ---------------------------------------------------------------- startup
    // 从测试体开始到「第一帧含真实 UI 文本并被光栅化」。
    final startupWatch = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        locale: Locale(localeCode),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        builder: (context, child) => TerminalStyleScope(
          notifier: style,
          child: Stack(
            children: [
              child!,
              ValueListenableBuilder<_Probe?>(
                valueListenable: probe,
                builder: (context, spec, _) {
                  if (spec == null) return const SizedBox.shrink();
                  return Positioned(
                    left: 8,
                    top: 8,
                    width: 480,
                    child: Material(
                      color: const Color(0xFFFFFFFF),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [spec.child],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        home: HomePage(
          store: store,
          sessions: sessions,
          credentials: FakeCredentialStore(),
          themeMode: ThemeMode.light,
          onThemeModeChanged: (_) {},
          language: AppLanguage.system,
          onLanguageChanged: (_) {},
          uiFont: UiFont.system,
          onUiFontChanged: (_) {},
          onSettingsClosed: () {},
        ),
      ),
    );
    final startupLayoutMs = startupWatch.elapsedMilliseconds;
    final startupHasText = find.text('test-host').evaluate().isNotEmpty;
    // 首页那一帧的耗时：跳过 App 树建立之前引擎画的空帧。
    await waitForRealFrame(0);
    final startupPresentedMs = startupWatch.elapsedMilliseconds;
    final startupFrames = List<FrameTiming>.of(sink.all);
    // 让首页彻底稳定下来再开始点设置。这一段同时用来抓「首帧之后多出来的帧」——
    // 首页若在首帧后偷偷做了一次预热（Offstage 预排版），代价会落在这里。
    final settleFrom = sink.all.length;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await pumpTimed();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final settleFrames = sink.all.sublist(
      settleFrom < sink.all.length ? settleFrom : sink.all.length,
    );
    final startupSettledMs = startupWatch.elapsedMilliseconds;

    final startupJson = <String, Object?>{
      'wallToTextLayoutMs': startupLayoutMs,
      'wallToFirstRealFrameMs': startupPresentedMs,
      'wallToStartupSettledMs': startupSettledMs,
      'textLaidOutOnFirstFrame': startupHasText,
      // 无障碍语义树是否打开：a11y 桥（AT-SPI/D-Bus）嫌疑的直接判据。
      'semanticsEnabled': SemanticsBinding.instance.semanticsEnabled,
      'frames': startupFrames.length,
      'maxBuildMs': _r1(_maxOf(startupFrames.map((f) => _ms(f.buildDuration)))),
      'maxRasterMs': _r1(
        _maxOf(startupFrames.map((f) => _ms(f.rasterDuration))),
      ),
      'settleFrames': settleFrames.length,
      'settleMaxBuildMs': _r1(
        _maxOf(settleFrames.map((f) => _ms(f.buildDuration))),
      ),
      'settleFramesTotalBuildMs': _r1(
        _sumOf(settleFrames.map((f) => _ms(f.buildDuration))),
      ),
      'settleFrameDetail': [
        for (final f in settleFrames)
          {
            'buildMs': _r1(_ms(f.buildDuration)),
            'rasterMs': _r1(_ms(f.rasterDuration)),
          },
      ],
      'frameDetail': [
        for (final f in startupFrames)
          {
            'buildMs': _r1(_ms(f.buildDuration)),
            'rasterMs': _r1(_ms(f.rasterDuration)),
          },
      ],
    };

    // ------------------------------------------------------------ 打开窗口测量
    final opens = <Map<String, Object?>>[];

    /// 侧边栏实际渲染出来的文案（证明语系 A/B 真的生效了）。
    List<String> sidebarSampleTexts() => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(Sidebar),
            matching: find.byType(Text),
          ),
        )
        .map((w) => w.data)
        .whereType<String>()
        .take(6)
        .toList();

    /// 触发一次打开动作，量到「内容已布局并出帧」，再让过渡动画跑完收全窗口帧。
    Future<Map<String, Object?>> measureWindow(
      String label,
      int index,
      Future<void> Function() trigger,
      Finder ready,
    ) async {
      final seenBefore = sink.all.length;
      final watch = Stopwatch()..start();
      final epochTap = DateTime.now().millisecondsSinceEpoch;
      await trigger();
      final epochTriggered = DateTime.now().millisecondsSinceEpoch;
      var layoutMs = -1;
      final pumpWalls = <int>[];
      var epochFirstPump = 0;
      for (var i = 0; i < 120; i++) {
        pumpWalls.add(await pumpTimed());
        if (i == 0) epochFirstPump = DateTime.now().millisecondsSinceEpoch;
        if (ready.evaluate().isNotEmpty) {
          layoutMs = watch.elapsedMilliseconds;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      final epochLayout = DateTime.now().millisecondsSinceEpoch;
      final waitMs = await waitTimings(seenBefore);
      final presentedMs = watch.elapsedMilliseconds;
      final epochPresented = DateTime.now().millisecondsSinceEpoch;
      debugPrint(
        '[perf-epoch] $label#$index tap=$epochTap triggered=$epochTriggered '
        'pump0done=$epochFirstPump layout=$epochLayout presented=$epochPresented',
      );
      final presentedFrames = sink.all.length - seenBefore;
      // 让 150ms 的路由过渡动画真的跑完，收集整个打开窗口的帧。
      await Future<void>.delayed(const Duration(milliseconds: 450));
      pumpWalls.add(await pumpTimed());
      await Future<void>.delayed(const Duration(milliseconds: 250));
      watch.stop();

      final slice = sink.all.sublist(
        seenBefore < sink.all.length ? seenBefore : sink.all.length,
      );
      final builds = slice.map((f) => _ms(f.buildDuration)).toList();
      final rasters = slice.map((f) => _ms(f.rasterDuration)).toList();
      final totals = [
        for (var i = 0; i < slice.length; i++) builds[i] + rasters[i],
      ];
      var topIndex = -1;
      var topTotal = -1.0;
      for (var i = 0; i < totals.length; i++) {
        if (totals[i] > topTotal) {
          topTotal = totals[i];
          topIndex = i;
        }
      }
      final row = <String, Object?>{
        'label': label,
        'open': index,
        'wallToContentLayoutMs': layoutMs,
        'wallToContentPresentedMs': presentedMs,
        'timingsWaitMs': waitMs,
        'framesPresentedByLayout': presentedFrames,
        'pumpWallsMs': pumpWalls,
        'windowFrames': slice.length,
        'maxBuildMs': _r1(_maxOf(builds)),
        'maxRasterMs': _r1(_maxOf(rasters)),
        'maxTotalMs': _r1(_maxOf(totals)),
        'sumBuildMs': _r1(_sumOf(builds)),
        'sumRasterMs': _r1(_sumOf(rasters)),
        'topFrame': topIndex < 0
            ? null
            : {
                'index': topIndex,
                'buildMs': _r1(builds[topIndex]),
                'rasterMs': _r1(rasters[topIndex]),
                'totalMs': _r1(totals[topIndex]),
              },
        'frameDetail': [
          for (var i = 0; i < slice.length; i++)
            {'buildMs': _r1(builds[i]), 'rasterMs': _r1(rasters[i])},
        ],
      };
      opens.add(row);
      return row;
    }

    Future<void> settle() async {
      // 让退场动画与由此产生的帧彻底跑完，别污染下一次打开。
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    // 对照：一个内容极简的 Dialog，走同一套 showDialog 路由。
    Future<void> openEmptyDialog(int index) async {
      final context = navigatorKey.currentContext!;
      await measureWindow('空 Dialog(对照)', index, () async {
        unawaited(
          showDialog<void>(
            context: context,
            builder: (_) => const Dialog(
              child: SizedBox(
                width: 240,
                height: 120,
                child: Center(child: Text(emptyDialogMarker)),
              ),
            ),
          ),
        );
      }, emptyDialogContent);
      Navigator.of(context).pop();
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
      if (emptyDialogContent.evaluate().isNotEmpty) {
        throw StateError('空 Dialog 没有关掉');
      }
      await settle();
    }

    Future<void> openSettings(int index) async {
      await measureWindow(
        '设置弹窗',
        index,
        () => tester.tap(settingsRow, warnIfMissed: false),
        dialogContent,
      );
    }

    Future<void> closeSettings() async {
      await tester.tap(dialogDone);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
      if (dialogContent.evaluate().isNotEmpty) {
        throw StateError('设置弹窗没有关掉');
      }
      await settle();
    }

    // ------------------------------------------------------------ 浮层微探针
    final micro = <Map<String, Object?>>[];
    final prewarm = <Map<String, Object?>>[];

    /// 先把探针摘掉并等干净，确保下一次是全新的子树（不是复用缓存）。
    Future<void> clearProbe() async {
      probe.value = null;
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    Future<void> runProbeIn(
      List<Map<String, Object?>> into,
      String label,
      Widget child,
    ) async {
      await clearProbe();
      final seenBefore = sink.all.length;
      final watch = Stopwatch()..start();
      probe.value = _Probe(child);
      final pumpWall = await pumpTimed();
      final waitMs = await waitTimings(seenBefore);
      watch.stop();
      final slice = sink.all.sublist(
        seenBefore < sink.all.length ? seenBefore : sink.all.length,
      );
      final frame = slice.isEmpty ? null : slice.last;
      into.add(<String, Object?>{
        'case': label,
        'pumpWallMs': pumpWall,
        'timingsWaitMs': waitMs,
        'wallMs': watch.elapsedMilliseconds,
        'buildMs': frame == null ? null : _r1(_ms(frame.buildDuration)),
        'rasterMs': frame == null ? null : _r1(_ms(frame.rasterDuration)),
        'framesInWindow': slice.length,
      });
    }

    Future<void> runProbe(String label, Widget child) =>
        runProbeIn(micro, label, child);

    // 字重探针：w400 是已用过的对照，w100/w300/w900 从未用过。
    const probeTextA = '设置弹窗字重探针权限';
    const probeTextB = '主题语言配色字号缓存';
    Future<void> runWeightProbe(
      String label,
      String text, {
      required FontWeight weight,
      double size = 14,
    }) => runProbe(
      '$label [w${weight.value}@$size]',
      Text(
        text,
        style: TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: const Color(0xFF000000),
        ),
      ),
    );

    Future<void> fontProbes() async {
      const weights = <(FontWeight, String)>[
        (FontWeight.w400, 'w400 对照'),
        (FontWeight.w100, 'w100 细体'),
        (FontWeight.w300, 'w300 轻体'),
        (FontWeight.w900, 'w900 黑体'),
      ];
      for (final (weight, label) in weights) {
        await runWeightProbe('$label · 首次', probeTextA, weight: weight);
        await runWeightProbe('$label · 二次(换字形)', probeTextB, weight: weight);
        await runWeightProbe('$label · 三次(原文本)', probeTextA, weight: weight);
      }
      // 字号变了、字重没变：预期便宜（同一个 typeface，不需要新字体文件）。
      await runWeightProbe(
        'w400 · 新字号43.7 首次',
        probeTextA,
        weight: FontWeight.w400,
        size: 43.7,
      );
      await runWeightProbe(
        'w400 · 新字号43.7 二次',
        probeTextB,
        weight: FontWeight.w400,
        size: 43.7,
      );
    }

    // 组件探针：设置弹窗里的真实控件，逐个单独首建。
    List<(String, Widget Function())> componentCases() => [
      ('AppIconMark', () => const AppIconMark(size: 36)),
      (
        'SegmentedButton<ThemeMode>',
        () => SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(
              value: ThemeMode.system,
              label: const Text('跟随系统'),
              icon: const Icon(Icons.brightness_auto_outlined, size: 15),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              label: const Text('浅色'),
              icon: const Icon(Icons.light_mode_outlined, size: 15),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: const Text('深色'),
              icon: const Icon(Icons.dark_mode_outlined, size: 15),
            ),
          ],
          selected: const {ThemeMode.system},
          onSelectionChanged: (_) {},
        ),
      ),
      (
        'UiFontDropdown',
        () => UiFontDropdown(value: UiFont.system, onChanged: (_) {}),
      ),
      ('TerminalPresetDropdown', () => const TerminalPresetDropdown()),
      (
        'TerminalFontDropdown',
        () => const TerminalFontDropdown(showLabel: false),
      ),
      (
        'TerminalFontSizeControl',
        () => const TerminalFontSizeControl(showLabel: false),
      ),
      ('TextField', () => const TextField(decoration: InputDecoration())),
      (
        'Text monospace',
        () => const Text(
          'ssh deploy@10.0.0.1',
          style: TextStyle(fontFamily: 'monospace', fontSize: 14),
        ),
      ),
    ];

    Future<void> componentProbes({bool repeat = true}) async {
      for (final (label, build) in componentCases()) {
        await runProbe('$label · 首次', build());
        if (repeat) await runProbe('$label · 二次', build());
      }
    }

    // ------------------------------------------------ 预热门控（顺序实验 A）
    // 设置弹窗用到的全部文案（key 取自 settings_dialog.dart / settings_controls.dart）。
    List<String> dialogStrings() => [
      l10n.navSettings,
      l10n.appName,
      'v0.4.3',
      l10n.about,
      l10n.appearance,
      l10n.appearanceHint,
      l10n.theme,
      l10n.followSystem,
      l10n.light,
      l10n.dark,
      l10n.appFont,
      l10n.terminal,
      l10n.terminalSectionHint,
      l10n.terminalPreset,
      l10n.terminalFont,
      l10n.terminalFontCustomName,
      l10n.terminalFontCustomHint,
      l10n.terminalFontSize,
      l10n.fontSizeDecrease,
      l10n.fontSizeIncrease,
      l10n.terminalPreview,
      l10n.terminalPreviewCommand,
      l10n.language,
      l10n.languageHint,
      l10n.settingsApplyHint,
      l10n.done,
      for (final f in UiFont.values) f.label(l10n),
      for (final f in TerminalFont.values) f.label(l10n),
      for (final p in TerminalPreset.values) p.label(l10n),
    ];

    /// 门控 A：在弹窗打开之前，先把弹窗的文案以「不可见但真排版」的方式过一遍。
    /// Opacity(0) 只跳过绘制，子树的 build + layout（含文本整形 / 字形回退解析）照常发生，
    /// 因此这一步能把「文本解析」这条路径预热掉，而不会预热任何控件初始化。
    Future<void> prewarmDialogText() async {
      final strings = dialogStrings();
      const styles = <(FontWeight, double)>[
        (FontWeight.w400, 13),
        (FontWeight.w400, 11.5),
        (FontWeight.w500, 12.5),
        (FontWeight.w500, 13),
        (FontWeight.w600, 13),
        (FontWeight.w700, 15.5),
      ];
      await runProbeIn(
        prewarm,
        '门控A 弹窗文案不可见排版 ${strings.length}条×${styles.length}样式',
        Opacity(
          opacity: 0,
          child: SizedBox(
            width: 1400,
            height: 700,
            child: Wrap(
              children: [
                for (final (weight, size) in styles)
                  for (final text in strings)
                    Text(
                      text,
                      style: TextStyle(fontSize: size, fontWeight: weight),
                    ),
              ],
            ),
          ),
        ),
      );
      await clearProbe();
    }

    /// 纯 ASCII 版控件探针：只热「控件类型 / 主题分支」，不引入任何新 CJK 字形。
    List<(String, Widget Function())> asciiWidgetCases() => [
      (
        'SegmentedButton',
        () => SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'a', label: Text('AAA')),
            ButtonSegment(value: 'b', label: Text('BBB')),
            ButtonSegment(value: 'c', label: Text('CCC')),
          ],
          selected: const {'a'},
          onSelectionChanged: (_) {},
        ),
      ),
      (
        'DropdownButtonFormField',
        () => DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'AAA'),
          items: const [
            DropdownMenuItem(value: 'a', child: Text('AAA')),
            DropdownMenuItem(value: 'b', child: Text('BBB')),
          ],
          onChanged: (_) {},
        ),
      ),
      (
        'InputDecorator',
        () => const InputDecorator(
          decoration: InputDecoration(labelText: 'AAA'),
          child: Text('BBB'),
        ),
      ),
      ('TextField', () => const TextField(decoration: InputDecoration())),
      (
        'IconButton+Tooltip',
        () => IconButton(
          tooltip: 'AAA',
          icon: const Icon(Icons.add_rounded, size: 18),
          onPressed: () {},
        ),
      ),
      ('AppIconMark', () => const AppIconMark(size: 36)),
      (
        'Text monospace',
        () => const Text(
          'ssh deploy@10.0.0.1',
          style: TextStyle(fontFamily: 'monospace', fontSize: 14),
        ),
      ),
    ];

    /// 门控 B：只热控件类型 / 主题分支（文本全 ASCII），不含任何新 CJK 字形。
    Future<void> prewarmWidgetTypes() async {
      for (final (label, build) in asciiWidgetCases()) {
        await runProbeIn(prewarm, '门控B $label (ASCII)', build());
      }
      await clearProbe();
    }

    // ------------------------------------------ 字形数量线性度探针（实验 C）
    // 用「App 文案里不可能出现的生僻字」保证是进程内首次使用。
    String cjkRun(int start, int count) =>
        String.fromCharCodes([for (var i = 0; i < count; i++) start + i]);

    Future<void> glyphProbes() async {
      const style = TextStyle(fontSize: 14, color: Color(0xFF000000));
      const ascii20 = '@#\$%^&*()_+{}|<>?~`[]';
      await runProbe('N=20 CJK 首次', Text(cjkRun(0x9F00, 20), style: style));
      await runProbe('N=20 CJK 重复', Text(cjkRun(0x9F00, 20), style: style));
      await runProbe('N=60 CJK 首次', Text(cjkRun(0x9F20, 60), style: style));
      await runProbe('N=60 CJK 重复', Text(cjkRun(0x9F20, 60), style: style));
      await runProbe('N=120 CJK 首次', Text(cjkRun(0x9F80, 120), style: style));
      await runProbe('N=120 CJK 重复', Text(cjkRun(0x9F80, 120), style: style));
      await runProbe('N=20 ASCII 首次', Text(ascii20, style: style));
      await runProbe('N=20 ASCII 重复', Text(ascii20, style: style));
    }

    // ------------------------------------------------------------------ 流程
    if (order == 'prewarm_text') {
      await prewarmDialogText();
      await openSettings(1);
      await closeSettings();
      await openSettings(2);
      await closeSettings();
    } else if (order == 'prewarm_widgets') {
      await prewarmWidgetTypes();
      await openSettings(1);
      await closeSettings();
      await openSettings(2);
      await closeSettings();
    } else if (order == 'minwarm') {
      // 最小预热：只排版一条从未用过的 (字重,字号) 组合，看它能不能吸掉首开的大头。
      await runProbe(
        '最小预热 单条 w700@15.5',
        Text(
          l10n.navSettings,
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF000000),
          ),
        ),
      );
      await clearProbe();
      await openSettings(1);
      await closeSettings();
      await openSettings(2);
      await closeSettings();
    } else if (order == 'emptyfirst') {
      await openEmptyDialog(1);
      await openEmptyDialog(2);
      await openSettings(1);
      await closeSettings();
    } else if (order == 'compfirst') {
      await componentProbes();
      await clearProbe();
      await openSettings(1);
      await closeSettings();
    } else {
      for (var i = 1; i <= 3; i++) {
        await openSettings(i);
        await closeSettings();
      }
      // 三次打开之后，再补一个「首个 Dialog 路由」的对照（此时路由基础设施已热）。
      await openEmptyDialog(4);
    }

    await clearProbe();
    await fontProbes();
    await glyphProbes();
    if (order != 'compfirst') {
      await componentProbes();
    }
    probe.value = null;
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // ------------------------------------------------------------------ 输出
    // release 也要如实标注：kProfileMode 为 false 时不能再一律写 debug。
    final modeTag = kReleaseMode
        ? 'release'
        : (kProfileMode ? 'profile' : 'debug');
    final modeLabel = '$modeTag/AOT';
    String pad(Object? value, int width) => '$value'.padRight(width);
    String padL(Object? value, int width) => '$value'.padLeft(width);

    final lines = <String>[
      '',
      '===== 设置弹窗打开耗时（$modeLabel，order=$order）=====',
      '启动: 文本已布局 ${startupJson['wallToTextLayoutMs']}ms / 首个真帧 '
          '${startupJson['wallToFirstRealFrameMs']}ms；'
          '帧数 ${startupJson['frames']}，'
          'build max ${startupJson['maxBuildMs']}ms，'
          'raster max ${startupJson['maxRasterMs']}ms',
      '',
      pad('打开', 22) +
          padL('墙钟→内容', 11) +
          padL('墙钟→出帧', 11) +
          padL('帧数', 6) +
          padL('build max', 11) +
          padL('raster max', 12) +
          padL('total max', 11),
    ];
    for (final row in opens) {
      lines.add(
        pad('${row['label']} #${row['open']}', 22) +
            padL('${row['wallToContentLayoutMs']}', 11) +
            padL('${row['wallToContentPresentedMs']}', 11) +
            padL('${row['windowFrames']}', 6) +
            padL('${row['maxBuildMs']}', 11) +
            padL('${row['maxRasterMs']}', 12) +
            padL('${row['maxTotalMs']}', 11),
      );
    }
    lines
      ..add('')
      ..add('----- 浮层微探针（首次 vs 重复，ms）-----');
    void dumpRows(List<Map<String, Object?>> rows) {
      for (final row in rows) {
        final build = row['buildMs'] as double?;
        final raster = row['rasterMs'] as double?;
        lines.add(
          pad(row['case'], 44) +
              padL('${row['pumpWallMs']}', 10) +
              padL(build ?? '-', 9) +
              padL(raster ?? '-', 9) +
              padL(
                build == null || raster == null ? '-' : _r1(build + raster),
                9,
              ),
        );
      }
    }

    lines.add(
      pad('用例', 44) +
          padL('pump墙钟', 10) +
          padL('build', 9) +
          padL('raster', 9) +
          padL('total', 9),
    );
    if (prewarm.isNotEmpty) {
      lines.add('--- 预热门控 ---');
      dumpRows(prewarm);
      lines.add('--- 微探针 ---');
    }
    dumpRows(micro);
    lines.add('================================================');
    for (final line in lines) {
      debugPrint(line);
    }

    final out = File('build/settings_open_perf_$modeTag.json');
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'runTag': Platform.environment['SETTINGS_PERF_RUN'] ?? 'local',
        'order': order,
        'mode': modeTag,
        'localeCode': localeCode,
        'storeMode': storeMode,
        'loadAvg': loadAvgText(),
        'sidebarSampleTexts': sidebarSampleTexts(),
        'startup': startupJson,
        'opens': opens,
        'microProbe': micro,
        'prewarm': prewarm,
      }),
    );
    debugPrint('报告写入 ${out.path}');

    expect(opens, isNotEmpty);
    expect(
      opens
          .where((row) => row['label'] == '设置弹窗')
          .every((row) => (row['wallToContentLayoutMs'] as int) > 0),
      isTrue,
      reason: '有打开动作没测到弹窗内容布局',
    );
    expect(
      opens.every((row) => (row['windowFrames'] as int) > 0),
      isTrue,
      reason: '没有收到帧耗时',
    );

    // 报告已写盘并打印。integration_test 的 binding 默认跑完不退出，
    // 本地可以用 timeout 兜住，CI（三平台矩阵）需要它自己收尾。
    exit(0);
  });
}
