/// 用 Flutter **自己**渲染移动端终端的截图——给评审看实现长什么样，
/// 不是 PIL 那张设计稿。
///
/// 生成方式（只在显式要求时跑）：
///
/// ```
/// NOSHELL_SHOT=1 flutter test --update-goldens test/mobile_terminal_shot_test.dart
/// ```
///
/// 默认跳过是刻意的：golden 对字体栅格化敏感，换个平台（macOS、另一个
/// Linux 发行版）逐像素比就会「失败」，而这里要的是「生成一张能看的图」，
/// 不是把各平台的抗锯齿差异钉进 `flutter test`。真要当回归基准用，
/// 得先在 CI 里固定镜像与字体。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/models.dart';
import 'package:no_shell/settings.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/ssh/terminal_view.dart';
import 'package:no_shell/theme.dart';
import 'package:xterm/ui.dart';

import 'support/transport_fakes.dart';

/// 是否生成截图。默认不跑，见文件头。
final bool _generate = Platform.environment['NOSHELL_SHOT'] == '1';

/// 界面文案的字形：测试环境不带系统字体，不喂就得全是方块。
///
/// **要两个**：Droid Sans Fallback 只有 CJK 字形（英文照样是方块），
/// 拉丁字母得靠 Roboto。同一个族里叠着注册，缺字形时引擎会往后找。
const String _latinFontPath =
    '/opt/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf';
const String _cjkFontPath =
    '/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf';

/// 图标字体：测试环境不带它，不喂一份工具栏那几颗按钮就是空方块。
const String _iconFontPath =
    '/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';

/// 界面文案在截图里用的族名。刻意不走「注册成 Roboto」那条路：测试环境的
/// 默认族是 FlutterTest（只有方块），这里显式把主题的字体族换掉。
const String _uiFamily = 'ShotUI';

const _server = SshServer(
  id: 'srv-shot',
  group: '生产',
  name: 'web-prod-01',
  host: '10.0.0.9',
  username: 'cheng',
);

/// 一段像样的会话输出，带 ANSI 颜色（xterm 照着上色），行宽压在 42 列内
/// ——390pt 的屏上 13.5 号等宽正好放得下，不会折行。
String _sampleOutput() => [
  '\x1b[32mcheng@web-prod-01\x1b[0m:\x1b[34m~\x1b[0m\$ ls -la',
  'total 32',
  'drwxr-xr-x  6 cheng cheng 4096 .',
  'drwxr-xr-x 12 root  root  4096 ..',
  '-rw-r--r--  1 cheng cheng  312 deploy.sh',
  'drwxr-xr-x  3 cheng cheng 4096 logs',
  '\x1b[32mcheng@web-prod-01\x1b[0m:\x1b[34m~\x1b[0m\$ docker compose ps',
  'NAME    SERVICE  STATUS   PORTS',
  'web     web      running  8080->80/tcp',
  'redis   cache    running  6379/tcp',
  '\x1b[32mcheng@web-prod-01\x1b[0m:\x1b[34m~\x1b[0m\$ tail -f logs/app.log',
  '\x1b[36m[10:09:12] INFO  listening on :8080\x1b[0m',
  '\x1b[36m[10:09:13] INFO  connected to redis\x1b[0m',
  '\x1b[33m[10:09:14] WARN  slow query 812ms\x1b[0m',
  '\x1b[31m[10:09:15] ERROR upstream timeout\x1b[0m',
  '\x1b[32mcheng@web-prod-01\x1b[0m:\x1b[34m~\x1b[0m\$ ',
].join('\r\n');

Future<void> _loadFont(String family, Future<ByteData> bytes) async {
  final loader = FontLoader(family)..addFont(bytes);
  await loader.load();
}

Future<ByteData> _fileBytes(String path) =>
    File(path).readAsBytes().then(ByteData.sublistView);

Widget _host(Widget child, ValueNotifier<TerminalStylePrefs> style) {
  final base = AppTheme.light();
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: _uiFamily),
    ),
    home: Scaffold(body: child),
    builder: (context, navigator) => TerminalStyleScope(
      notifier: style,
      child: navigator ?? const SizedBox.shrink(),
    ),
  );
}

Future<(TerminalSession, ValueNotifier<TerminalStylePrefs>)> _pump(
  WidgetTester tester,
) async {
  // 手机竖屏：390×844 逻辑像素，2 倍渲染。
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  final transport = FakeTransport(lines: [_sampleOutput()]);
  final session = TerminalSession(
    server: _server,
    credentials: const SshCredentials(password: 'pw'),
    transport: transport,
  );
  await session.start();
  addTearDown(session.dispose);

  final style = ValueNotifier(const TerminalStylePrefs());
  addTearDown(style.dispose);
  await tester.pumpWidget(
    _host(
      SshTerminalView(session: session, openLink: (uri) async => true),
      style,
    ),
  );
  await tester.pump();
  return (session, style);
}

void main() {
  setUpAll(() async {
    // 终端字体：用随包内置的那一支，族名要和 pubspec 里的声明一致。
    await _loadFont(
      'NoShell JetBrains Mono',
      rootBundle.load('assets/fonts/jetbrains_mono/JetBrainsMono-Regular.ttf'),
    );
    // 界面字体：拉丁 + CJK 叠在同一个族里。
    final ui = FontLoader(_uiFamily);
    if (File(_latinFontPath).existsSync()) {
      ui.addFont(_fileBytes(_latinFontPath));
    }
    if (File(_cjkFontPath).existsSync()) {
      ui.addFont(_fileBytes(_cjkFontPath));
    }
    await ui.load();
    // 图标字体。
    if (File(_iconFontPath).existsSync()) {
      await _loadFont('MaterialIcons', _fileBytes(_iconFontPath));
    }
  });

  testWidgets('移动端终端：快捷键条', (tester) async {
    await _pump(tester);
    await expectLater(
      find.byType(SshTerminalView),
      matchesGoldenFile('../docs/screenshots/mobile-terminal-keybar.png'),
    );
  }, skip: !_generate);

  testWidgets('移动端终端：选区手柄', (tester) async {
    final (session, _) = await _pump(tester);
    final buffer = session.terminal.buffer;
    final controller = tester
        .widget<TerminalView>(find.byType(TerminalView))
        .controller!;
    // 选中一行日志，手柄挂两头。
    controller.setSelection(
      buffer.createAnchor(0, 12),
      buffer.createAnchor(26, 12),
    );
    await tester.pump();
    await expectLater(
      find.byType(SshTerminalView),
      matchesGoldenFile('../docs/screenshots/mobile-terminal-selection.png'),
    );
  }, skip: !_generate);

  testWidgets('移动端终端：查找栏', (tester) async {
    await _pump(tester);
    // 工具栏上的放大镜就是查找入口。
    await tester.tap(find.byIcon(Icons.search_rounded).first);
    await tester.pump();
    await tester.enterText(
      find.descendant(
        of: find.byType(SshTerminalView),
        matching: find.byType(TextField),
      ),
      'INFO',
    );
    await tester.pump();
    await tester.pump();
    await expectLater(
      find.byType(SshTerminalView),
      matchesGoldenFile('../docs/screenshots/mobile-terminal-search.png'),
    );
  }, skip: !_generate);
}
