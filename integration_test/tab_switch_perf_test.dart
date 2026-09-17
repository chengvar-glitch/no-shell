// 切 Tab 性能探针：在真实引擎 / 真实光栅化下测「概览 / 终端 / SFTP」三个 Tab
// 的切换帧耗时，用来盯住「连上 SSH 后切 Tab 卡顿」这类回归。
//
// 链路不依赖外部主机：注入一个会持续输出的假传输层，模拟真实终端输出流，
// 输出分三档（关闭 / 轻载约 60 行每秒 / 重载约 2400 行每秒）。
//
// 运行（profile 模式，帧耗时才有参考价值）：
//   flutter drive --profile -d linux \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/tab_switch_perf_test.dart
// 对照（debug 模式，模拟 `flutter run` 的日常开发链路）：
//   flutter test integration_test/tab_switch_perf_test.dart -d linux
//
// 历史结论（2026-09，Linux + Impeller）：
// - TabBar 选中 / 未选中字重不同时，切一次 Tab 单帧阻塞约 1.5s，卡 15 次左右；
//   字重统一后同一路径降到 1~11ms（见 lib/theme.dart 的说明）。
// - 终端持续输出时切 Tab 只贵几毫秒，索引栈 + Visibility 保活没有重新布局问题。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xterm/core.dart';

import 'package:no_shell/app_locale.dart';
import 'package:no_shell/home_page.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/settings.dart';
import 'package:no_shell/ssh/session_manager.dart';
import 'package:no_shell/ssh/sftp.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/ssh_transport.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/store.dart';
import 'package:no_shell/theme.dart';

import '../test/support/credential_store_fake.dart';
import '../test/support/sftp_fakes.dart';

/// 输出档位。
enum StreamMode { off, light, heavy }

/// 持续输出 ANSI 彩色日志的假传输层：模拟 `tail -f` / 构建日志级别的终端流量。
final class _StreamingTransport implements SshTransport {
  _StreamingTransport({required this.fileSystem});

  /// 输出节奏：约 60 行 / 秒，接近构建日志或 tail -f 的流量。
  static const interval = Duration(milliseconds: 16);

  final SftpFileSystem fileSystem;

  Terminal? terminal;
  Timer? _timer;
  int _line = 0;
  StreamMode _mode = StreamMode.off;

  void setMode(StreamMode mode) {
    _mode = mode;
    final shouldRun = mode != StreamMode.off;
    if (shouldRun && _timer == null) {
      _timer = Timer.periodic(interval, (_) => _emit());
    } else if (!shouldRun) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _emit() {
    final terminal = this.terminal;
    if (terminal == null) return;
    // 重载档每帧灌 40 行，约 2400 行 / 秒，接近高吞吐日志。
    final burst = _mode == StreamMode.heavy ? 40 : 1;
    final buffer = StringBuffer();
    for (var i = 0; i < burst; i++) {
      final n = _line++;
      buffer.write(
        '$n  \x1b[32mINFO\x1b[0m  worker-3  '
        'batch #$n done  elapsed=${n % 40}ms  rss=${400 + n % 90}MB  '
        '\x1b[33mqueue=${8 + n % 5}\x1b[0m\r\n',
      );
    }
    terminal.write(buffer.toString());
  }

  @override
  Future<void> attach(
    Terminal terminal, {
    required void Function() onConnected,
    required void Function() onClosed,
  }) async {
    this.terminal = terminal;
    onConnected();
    // 先灌满一屏 + 若干回滚行，让终端缓冲区接近真实使用状态。
    for (var i = 0; i < 200; i++) {
      terminal.write('boot line $i: starting service unit ${i % 12}\r\n');
    }
  }

  @override
  Future<SftpFileSystem> openSftp() async => fileSystem;

  @override
  void dispose() {
    setMode(StreamMode.off);
    terminal = null;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('三个 Tab 切换帧耗时', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    // 用生产窗口尺寸（1536x864）测量，避免尺寸差异影响结论。
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1536, 864));
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // 造一个「目录里有几百个文件」的远端，模拟真实 SFTP 列表。
    final fs = FakeSftpFileSystem();
    for (var i = 0; i < 300; i++) {
      fs.addFile(fs.home, 'app-${i.toString().padLeft(3, '0')}.log');
      if (i % 20 == 0) fs.addDirectory(fs.home, 'dir-$i');
    }
    final transport = _StreamingTransport(fileSystem: fs);
    final store = ServerStore(seed: [testServer()]);
    final sessions = SessionManager(
      store: store,
      sessionFactory: (server, credentials) => TerminalSession(
        server: server,
        credentials: credentials,
        transport: transport,
        localFiles: FakeLocalFileGateway(),
      ),
    );
    addTearDown(sessions.dispose);
    final style = ValueNotifier<TerminalStylePrefs>(const TerminalStylePrefs());
    addTearDown(style.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        builder: (context, child) =>
            TerminalStyleScope(notifier: style, child: child!),
        home: HomePage(
          store: store,
          sessions: sessions,
          credentials: FakeCredentialStore(),
          themeMode: ThemeMode.light,
          onThemeModeChanged: (_) {},
          language: AppLanguage.system,
          onLanguageChanged: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> batch) => timings.addAll(batch);
    binding.addTimingsCallback(collect);
    addTearDown(() => binding.removeTimingsCallback(collect));

    /// 每次点击的「墙钟 + 该窗口内的帧耗时」，卡顿会直接体现在 max 上。
    final rows = <({String label, int wallMs, int frames, double maxTotal})>[];

    Future<void> tapTab(String label, {String? note}) async {
      final before = timings.length;
      final watch = Stopwatch()..start();
      await tester.tap(
        find.descendant(of: find.byType(TabBar), matching: find.text(label)),
        warnIfMissed: false,
      );
      await tester.pump();
      // fullyLive：真实 vsync 持续出帧，这里让切换动画真的跑完。
      await Future<void>.delayed(const Duration(milliseconds: 420));
      await tester.pump();
      // 等帧耗时批次回传，避免把这一跳的成本算到下一跳。
      await Future<void>.delayed(const Duration(milliseconds: 150));
      watch.stop();
      final slice = timings.sublist(before);
      final maxTotal = slice.isEmpty
          ? 0.0
          : slice
                .map(
                  (t) =>
                      (t.buildDuration + t.rasterDuration).inMicroseconds /
                      1000,
                )
                .reduce((a, b) => a > b ? a : b);
      rows.add((
        label: note ?? label,
        wallMs: watch.elapsedMilliseconds,
        frames: slice.length,
        maxTotal: maxTotal,
      ));
    }

    Future<void> measure(String phase, List<String> sequence) async {
      debugPrint('---- $phase');
      for (final label in sequence) {
        await tapTab(label);
      }
    }

    // 选中主机，让详情面板出现三个 Tab（此时还没有会话）。
    await tester.tap(find.text('test-host'));
    await tester.pump(const Duration(milliseconds: 200));

    await measure('未连接 · 三 Tab 全量切换', const [
      '终端',
      'SFTP',
      '概览',
      '终端',
      'SFTP',
      '概览',
    ]);

    // 连接（假传输层）：终端 Tab 变成真实 xterm 视图。
    sessions.open(store.byId('srv-01')!, const SshCredentials(password: 'pw'));
    await tester.pump(const Duration(milliseconds: 600));
    transport.setMode(StreamMode.light);
    await measure('已连接 + 轻载输出', const ['终端', 'SFTP', '概览', '终端', 'SFTP', '概览']);

    transport.setMode(StreamMode.heavy);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await measure('已连接 + 重载输出', const ['终端', 'SFTP', '概览', '终端', 'SFTP', '概览']);

    transport.setMode(StreamMode.off);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await measure('已连接 + 停止输出', const ['终端', 'SFTP', '概览', '终端', 'SFTP', '概览']);

    final lines = <String>[
      '',
      '========= 每次 Tab 点击的帧耗时（ms，${kProfileMode ? 'profile/AOT' : 'debug/JIT'}）=========',
      '点击'.padRight(26) +
          '墙钟'.padLeft(8) +
          '帧数'.padLeft(6) +
          '单帧最大'.padLeft(10),
    ];
    for (final row in rows) {
      lines.add(
        row.label.padRight(26) +
            '${row.wallMs}'.padLeft(8) +
            '${row.frames}'.padLeft(6) +
            row.maxTotal.toStringAsFixed(1).padLeft(10),
      );
    }
    lines.add(
      '================================================================',
    );
    for (final line in lines) {
      debugPrint(line);
    }

    final out = File(
      'build/tab_switch_perf_${kProfileMode ? 'profile' : 'debug'}.json',
    );
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert([
        for (final row in rows)
          {
            'tap': row.label,
            'wallMs': row.wallMs,
            'frames': row.frames,
            'maxFrameMs': double.parse(row.maxTotal.toStringAsFixed(1)),
          },
      ]),
    );
    debugPrint('报告写入 ${out.path}');

    expect(rows.every((row) => row.frames > 0), isTrue, reason: '没有收到帧耗时');
  });
}
