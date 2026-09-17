import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'app_locale.dart';
import 'home_page.dart';
import 'l10n/generated/app_localizations.dart';
import 'mobile/mobile_shell.dart';
import 'server_persistence.dart';
import 'settings.dart';
import 'settings_persistence.dart';
import 'ssh/credential_store.dart';
import 'ssh/host_key_store.dart';
import 'ssh/session_manager.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerBundledFontLicenses();
  await _setupDesktopWindow();
  // 启动即载入已保存的主机列表与偏好，避免先闪一帧空列表 / 默认主题
  // 再被替换；两者互不依赖，并行读盘。
  final store = ServerStore(persistence: SharedPreferencesServerPersistence());
  final settings = SharedPreferencesSettingsPersistence();
  final (_, savedSettings) = await (store.load(), settings.load()).wait;
  runApp(
    NoShellApp(
      store: store,
      settings: settings,
      initialSettings: savedSettings,
    ),
  );
}

/// 把随包内置字体的 OFL 文本注册进许可清单：SIL OFL 要求分发字体时随附许可，
/// 注册后「关于 → 查看许可」（showAboutDialog 自带入口）里就能看到。
/// 读不到 asset 时静默跳过——许可展示失败不该拦下启动。
void _registerBundledFontLicenses() {
  for (final entry in kBundledFontLicenses.entries) {
    LicenseRegistry.addLicense(() async* {
      try {
        final text = await rootBundle.loadString(entry.value);
        yield LicenseEntryWithLineBreaks([entry.key], text);
      } catch (_) {
        return;
      }
    });
  }
}

/// 桌面初始窗口尺寸：在旧版 1280x720 基础上放大 20%。
/// macOS 在 MainFlutterWindow.swift 中单独设置（旧版 1280x800，同比例放大）。
const Size kDesktopPreferredWindowSize = Size(1536, 864);

/// 最小可用尺寸，保证桌面分栏仍可完整显示。
const Size kDesktopMinimumWindowSize = Size(940, 600);

/// 窗口不贴屏幕边缘，给任务栏 / 系统面板留出的余量（逻辑像素）。
const double kDesktopWindowScreenInset = 32;

/// 把偏好尺寸收敛到屏幕可用区域内，避免低分辨率机器上窗口超出屏幕。
/// [screen] 为 null 或非正（拿不到屏幕信息）时按偏好尺寸创建，不做裁剪；
/// 窗口被压到比 [minimum] 还小时，最小尺寸同步收缩，否则窗口无法再调整。
({Size size, Size minimum}) resolveDesktopWindowSize({
  required Size preferred,
  required Size minimum,
  required Size? screen,
}) {
  var available = preferred;
  if (screen != null && screen.width > 0 && screen.height > 0) {
    available = Size(
      math.max(1, screen.width - kDesktopWindowScreenInset),
      math.max(1, screen.height - kDesktopWindowScreenInset),
    );
  }
  final size = Size(
    math.min(preferred.width, available.width),
    math.min(preferred.height, available.height),
  );
  return (
    size: size,
    minimum: Size(
      math.min(minimum.width, size.width),
      math.min(minimum.height, size.height),
    ),
  );
}

/// Windows/Linux 隐藏原生标题栏（macOS 已在 MainFlutterWindow 中原生定制，
/// 移动端与 web 无窗口概念），窗口尺寸与三端默认保持一致。
Future<void> _setupDesktopWindow() async {
  if (kIsWeb) return;
  final platform = defaultTargetPlatform;
  if (platform != TargetPlatform.windows && platform != TargetPlatform.linux) {
    return;
  }
  await windowManager.ensureInitialized();
  final bounds = resolveDesktopWindowSize(
    preferred: kDesktopPreferredWindowSize,
    minimum: kDesktopMinimumWindowSize,
    screen: await _primaryScreenSize(),
  );
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: bounds.size,
      minimumSize: bounds.minimum,
      titleBarStyle: TitleBarStyle.hidden,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
}

/// 主屏可用区域（逻辑像素，已排除任务栏 / 系统面板）；取不到时返回 null。
Future<Size?> _primaryScreenSize() async {
  try {
    final display = await screenRetriever.getPrimaryDisplay();
    return display.visibleSize ?? display.size;
  } catch (_) {
    // 平台通道不可用时退回偏好尺寸，窗口仍能正常创建。
    return null;
  }
}

class NoShellApp extends StatefulWidget {
  const NoShellApp({
    super.key,
    this.store,
    this.credentials,
    this.hostKeys,
    this.settings,
    this.initialSettings,
  });

  /// 测试或嵌入方可注入；缺省时主机列表不落盘，凭据走平台安全存储，
  /// 主机密钥指纹经 shared_preferences 做 TOFU 记录。
  final ServerStore? store;
  final CredentialStore? credentials;
  final HostKeyStore? hostKeys;

  /// 偏好落盘通道；为 null 时主题 / 语言 / 终端样式只留在内存（测试默认如此）。
  final SettingsPersistence? settings;

  /// 启动前已读出的偏好；为 null 表示按默认值启动。
  final AppSettings? initialSettings;

  @override
  State<NoShellApp> createState() => _NoShellAppState();
}

class _NoShellAppState extends State<NoShellApp> {
  // ThemeData 构建开销不小，AppTheme 内部已按亮度缓存。
  static final _lightTheme = AppTheme.light();
  static final _darkTheme = AppTheme.dark();

  late final ServerStore _store = widget.store ?? ServerStore();
  late final CredentialStore _credentials =
      widget.credentials ?? createCredentialStore();
  late final HostKeyStore _hostKeys = widget.hostKeys ?? createHostKeyStore();
  late final SessionManager _sessions = SessionManager(
    store: _store,
    hostKeys: _hostKeys,
  );

  /// 主题默认跟随系统；启动时以落盘偏好为准，没有存档才用默认值。
  late ThemeMode _themeMode =
      widget.initialSettings?.themeMode ?? ThemeMode.system;
  late AppLanguage _language =
      widget.initialSettings?.language ?? AppLanguage.system;

  /// 终端样式（配色预设 + 字体 + 字号）全局偏好，经作用域下发，设置处直写。
  late final ValueNotifier<TerminalStylePrefs> _terminalStyle = ValueNotifier(
    widget.initialSettings?.terminalStyle ?? const TerminalStylePrefs(),
  );

  /// 落盘节流：设置面板里连点配色 / 字号、逐字输入字体名都会频繁通知，
  /// 合并成一次写盘；退出前再补一次，保证「点完成 → 值一定落盘」。
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _terminalStyle.addListener(_scheduleSave);
  }

  AppSettings get _currentSettings => AppSettings(
    themeMode: _themeMode,
    language: _language,
    terminalStyle: _terminalStyle.value,
  );

  void _scheduleSave() {
    if (widget.settings == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _saveNow);
  }

  void _saveNow() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final persistence = widget.settings;
    if (persistence == null) return;
    unawaited(persistence.save(_currentSettings));
  }

  @override
  void dispose() {
    _terminalStyle.removeListener(_scheduleSave);
    // 先补写这次会话最后的改动，再拆状态；写盘失败不影响退出。
    _saveNow();
    _sessions.dispose();
    _store.dispose();
    _terminalStyle.dispose();
    super.dispose();
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    _scheduleSave();
  }

  void _setLanguage(AppLanguage language) {
    setState(() => _language = language);
    _scheduleSave();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // title 为静态字符串无法本地化，改用 onGenerateTitle 随界面语言生成。
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // null 表示跟随系统；zh 系统命中 zh，其余回退到首个支持语言 en。
      locale: _language.locale,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: _themeMode,
      // 主题切换由 MaterialApp 内置的 AnimatedTheme 逐帧插值：语义色走
      // AppColors 扩展的 lerp（见 theme.dart），浅深色才能整体同时过渡。
      // 曲线取线性（Flutter 对主题的默认曲线），让色值匀速扫过而不是前后急停。
      themeAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 240),
        curve: Curves.linear,
      ),
      // 作用域必须包住 Navigator，全屏路由与对话框才能读取终端样式。
      builder: (context, child) => TerminalStyleScope(
        notifier: _terminalStyle,
        child: child ?? const SizedBox.shrink(),
      ),
      home: LayoutBuilder(
        builder: (context, constraints) {
          // 窄屏走移动端底部导航骨架，宽屏保持桌面左右分栏。
          final isMobile = constraints.maxWidth < 640;
          return isMobile
              ? MobileShell(
                  store: _store,
                  sessions: _sessions,
                  credentials: _credentials,
                  themeMode: _themeMode,
                  onThemeModeChanged: _setThemeMode,
                  language: _language,
                  onLanguageChanged: _setLanguage,
                )
              : HomePage(
                  store: _store,
                  sessions: _sessions,
                  credentials: _credentials,
                  themeMode: _themeMode,
                  onThemeModeChanged: _setThemeMode,
                  language: _language,
                  onLanguageChanged: _setLanguage,
                  onSettingsClosed: _saveNow,
                );
        },
      ),
    );
  }
}
