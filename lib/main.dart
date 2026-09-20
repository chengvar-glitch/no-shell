import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'app_locale.dart';
import 'app_version.dart';
import 'fps_hud.dart';
import 'home_page.dart';
import 'l10n/generated/app_localizations.dart';
import 'mobile/mobile_shell.dart';
import 'server_persistence.dart';
import 'settings.dart';
import 'shell_layout.dart';
import 'settings_persistence.dart';
import 'snippets.dart';
import 'ssh/credential_store.dart';
import 'ssh/host_key_store.dart';
import 'ssh/session_manager.dart';
import 'store.dart';
import 'theme.dart';
import 'update_check.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerBundledFontLicenses();
  await _setupDesktopWindow();
  // 启动即载入已保存的主机列表与偏好，避免先闪一帧空列表 / 默认主题
  // 再被替换；三者互不依赖，并行读盘。版本号顺带一起读，界面里随即
  // 显示的是真实版本，而不是编译期常量。
  final store = ServerStore(persistence: SharedPreferencesServerPersistence());
  final settings = SharedPreferencesSettingsPersistence();
  final snippets = SnippetStore(
    persistence: SharedPreferencesSnippetPersistence(),
  );
  final (_, savedSettings, _, _) = await (
    store.load(),
    settings.load(),
    snippets.load(),
    loadAppVersion(),
  ).wait;
  runApp(
    NoShellApp(
      store: store,
      settings: settings,
      initialSettings: savedSettings,
      snippetStore: snippets,
      // 版本检测只在真机进入：组件测试不注入这条通道，也就不会联网。
      updateCheckClient: HttpUpdateCheckClient(),
      updateCheckPersistence: const SharedPreferencesUpdateCheckPersistence(),
    ),
  );
}

/// 没有注入查询通道时的替身：**不联网**，如实报「查不到发布版」。
///
/// 组件测试默认走这里，所以测试里不会有真实的网络请求；用户在设置页
/// 点「检查」也只会看到一句查不到，而不是一个静默失败的按钮。
///
/// 认的是 [ReleaseLookupException.notFound] 而不是新造一种错误：对用户
/// 来说这两种情况的可操作性完全一样（去发布页看看），文案不必分叉。
class _NoUpdateCheckClient implements UpdateCheckClient {
  const _NoUpdateCheckClient();

  @override
  Future<ReleaseInfo> fetchLatestRelease() =>
      Future.error(const ReleaseLookupException(ReleaseLookupError.notFound));
}

/// 把随包内置字体的 OFL 文本注册进许可清单：SIL OFL 要求分发字体时随附许可，
/// 注册后「关于 → 查看许可」（showAppAboutDialog 自带入口）里就能看到。
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
    this.agentKeysProbe,
    this.snippetStore,
    this.autoReconnect = true,
    this.updateCheckClient,
    this.updateCheckPersistence,
    this.openReleasePage,
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

  /// 「本机 agent 是否可用且有钥匙」的探针；测试注入假探针，
  /// 缺省连真实的 SSH_AUTH_SOCK。
  final AgentKeysProbe? agentKeysProbe;

  /// 命令片段注册表；为 null 时用内存注册表（测试或嵌入场景）。
  final SnippetStore? snippetStore;

  /// 会话意外断开后是否自动重连（指数退避）。默认打开；测试可关闭，
  /// 免得假传输的「连接后立即断开」凭空长出重连会话。
  final bool autoReconnect;

  /// 版本检测的查询通道；为 null 时**不联网**（测试与嵌入方的默认）。
  /// 真机由 `main()` 注入真实实现，组件测试注入假实现。
  final UpdateCheckClient? updateCheckClient;

  /// 「有新版本」的落盘通道；为 null 时只在内存里记（测试默认如此）。
  final UpdateCheckPersistence? updateCheckPersistence;

  /// 打开发布页的能力；不传时走系统实现（web 桩返回打不开）。
  final Future<bool> Function(Uri uri)? openReleasePage;

  @override
  State<NoShellApp> createState() => _NoShellAppState();
}

class _NoShellAppState extends State<NoShellApp> with WindowListener {
  // ThemeData 构建开销不小，AppTheme 内部已按亮度缓存，所以这里即使每个
  // 实例各取一次也只在首次真正构建。刻意不做 static：组件测试里一个进程会
  // 挂载多个 App，static 会把第一个用例的平台相关取值（visualDensity 等）
  // 固化给后面的用例，几何断言于是随用例顺序漂移。
  late final ThemeData _lightTheme = AppTheme.light();
  late final ThemeData _darkTheme = AppTheme.dark();

  late final ServerStore _store = widget.store ?? ServerStore();
  late final CredentialStore _credentials =
      widget.credentials ?? createCredentialStore();
  late final HostKeyStore _hostKeys = widget.hostKeys ?? createHostKeyStore();

  /// 连接老设备时是否允许 ssh-rsa（SHA-1）主机密钥；改动即时下发给会话层。
  late bool _allowLegacyHostKeys =
      widget.initialSettings?.allowLegacyHostKeys ?? false;

  late final SessionManager _sessions = SessionManager(
    store: _store,
    hostKeys: _hostKeys,
    allowLegacyHostKeys: _allowLegacyHostKeys,
    agentKeysProbe: widget.agentKeysProbe,
    autoReconnect: widget.autoReconnect,
  );

  /// 命令片段注册表；经由 [SnippetScope] 下发，终端工具条直接取用。
  late final SnippetStore _snippets = widget.snippetStore ?? SnippetStore();

  /// 主题默认跟随系统；启动时以落盘偏好为准，没有存档才用默认值。
  late ThemeMode _themeMode =
      widget.initialSettings?.themeMode ?? ThemeMode.system;
  late AppLanguage _language =
      widget.initialSettings?.language ?? AppLanguage.system;

  /// 终端样式（配色预设 + 字体 + 字号）全局偏好，经作用域下发，设置处直写。
  late final ValueNotifier<TerminalStylePrefs> _terminalStyle = ValueNotifier(
    widget.initialSettings?.terminalStyle ?? const TerminalStylePrefs(),
  );

  /// 落盘节流：设置面板里连点配色、连按字号步进都会频繁通知，
  /// 合并成一次写盘；退出前再补一次，保证「点完成 → 值一定落盘」。
  Timer? _saveTimer;

  /// 跨骨架保留的界面状态：窗口宽度跨过 640px 时两套骨架整棵互换，
  /// 选中项 / 侧边栏折叠 / 当前 Tab 只有放在这里才不会被重置。
  final ShellLayoutState _layout = ShellLayoutState();

  /// 版本检测：查到「有新版」时在设置入口挂一个红点，设置页里给出
  /// 「前往下载」。没注入查询通道（测试默认）时走「不联网」实现。
  late final UpdateCheckService _updateCheck = UpdateCheckService(
    client: widget.updateCheckClient ?? const _NoUpdateCheckClient(),
    persistence: widget.updateCheckPersistence,
  );

  @override
  void initState() {
    super.initState();
    _terminalStyle.addListener(_scheduleSave);
    // 启动后静默查一次：先读上次记录的「有新版」结论（不联网就有提示），
    // 再排一次联网查询。两者都不阻塞启动，失败也只是不提示。
    unawaited(_updateCheck.load());
    _updateCheck.scheduleStartupCheck();
    if (kFpsHudEnabled) {
      // 无头取证探针：宿主拿不到屏幕录制权限时，靠 stdout 判断点击是否
      // 命中（选中了哪台主机、会话建没建、走到哪个阶段）。release 无此代码。
      Timer.periodic(const Duration(seconds: 2), (_) {
        final phases = [for (final s in _sessions.sessions) s.phase.name];
        debugPrint(
          'STATE ts=${DateTime.now().millisecondsSinceEpoch} '
          'sel=${_layout.selectedId ?? '-'} '
          'sessions=${_sessions.sessionCount} phases=$phases',
        );
      });
    }
    // 关窗时先把排队中的落盘写完再真的退出：主机的增删改是异步链式写盘，
    // 直接退出会把最后一次改动丢掉（刚改完分组就关窗正是这种节奏）。
    // 注册失败（平台通道不可用，如组件测试环境）就算了，不影响界面。
    try {
      windowManager.addListener(this);
      _windowHooked = true;
    } catch (_) {
      _windowHooked = false;
    }
  }

  /// 是否成功挂上了窗口监听；没挂上时 [_flushAndClose] 不碰窗口管理器。
  bool _windowHooked = false;

  /// 关窗：拦住默认关闭，落盘与偏好补写完成后再真的退出。
  @override
  void onWindowClose() {
    unawaited(_flushAndClose());
  }

  Future<void> _flushAndClose() async {
    _saveNow();
    await (_store.flush(), _snippets.flush()).wait;
    if (!_windowHooked) return;
    await windowManager.destroy();
  }

  AppSettings get _currentSettings => AppSettings(
    themeMode: _themeMode,
    language: _language,
    terminalStyle: _terminalStyle.value,
    allowLegacyHostKeys: _allowLegacyHostKeys,
  );

  void _setAllowLegacyHostKeys(bool value) {
    if (_allowLegacyHostKeys == value) return;
    setState(() => _allowLegacyHostKeys = value);
    // 会话层持有的是可变字段，新建会话才读它；已建连接不受影响。
    _sessions.allowLegacyHostKeys = value;
    _scheduleSave();
  }

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
    if (_windowHooked) windowManager.removeListener(this);
    _terminalStyle.removeListener(_scheduleSave);
    // 先补写这次会话最后的改动，再拆状态；写盘失败不影响退出。
    _saveNow();
    _sessions.dispose();
    _store.dispose();
    _snippets.dispose();
    _terminalStyle.dispose();
    _updateCheck.dispose();
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
      // 作用域必须包住 Navigator，全屏路由与对话框才能读取终端样式；
      // 命令片段的作用域同理，终端工具条与片段弹窗都从树上取同一个注册表。
      builder: (context, child) => TerminalStyleScope(
        notifier: _terminalStyle,
        child: SnippetScope(
          store: _snippets,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      // 开发自测的 FPS 悬浮表：kFpsHudEnabled 在 release 里是编译期 false，
      // 整个 Stack 分支连同 FpsHud 一起被 tree-shake，用户包零残留。
      home: kFpsHudEnabled
          ? Stack(children: [_buildShell(), const FpsHud()])
          : _buildShell(),
    );
  }

  Widget _buildShell() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 窄屏走移动端底部导航骨架，宽屏保持桌面左右分栏。
        // 两个骨架共用一份 _layout：跨断点时整棵树会被换掉，选中项 /
        // 侧边栏折叠 / 当前 Tab 只有放在骨架外面才留得住。
        final isMobile = constraints.maxWidth < 640;
        return isMobile
            ? MobileShell(
                store: _store,
                sessions: _sessions,
                credentials: _credentials,
                hostKeys: _hostKeys,
                themeMode: _themeMode,
                onThemeModeChanged: _setThemeMode,
                language: _language,
                onLanguageChanged: _setLanguage,
                allowLegacyHostKeys: _allowLegacyHostKeys,
                onAllowLegacyHostKeysChanged: _setAllowLegacyHostKeys,
                layout: _layout,
                updateCheck: _updateCheck,
                openReleasePage: widget.openReleasePage,
              )
            : HomePage(
                store: _store,
                sessions: _sessions,
                credentials: _credentials,
                hostKeys: _hostKeys,
                themeMode: _themeMode,
                onThemeModeChanged: _setThemeMode,
                language: _language,
                onLanguageChanged: _setLanguage,
                onSettingsClosed: _saveNow,
                allowLegacyHostKeys: _allowLegacyHostKeys,
                onAllowLegacyHostKeysChanged: _setAllowLegacyHostKeys,
                layout: _layout,
                updateCheck: _updateCheck,
                openReleasePage: widget.openReleasePage,
              );
      },
    );
  }
}
