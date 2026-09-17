import 'package:flutter/material.dart';
import 'package:xterm/ui.dart';

import 'l10n/generated/app_localizations.dart';

/// 终端字体：只提供「随包内置」与「系统等宽」两类，不提供自由填写字体名的入口。
///
/// 内置族名刻意带 `NoShell ` 前缀：它与系统里任何字体都不同名，文本引擎因此
/// 必定命中随包的那份文件。反过来，写一个系统里可能存在的名字（如
/// `JetBrains Mono`）在 Linux 上会被 fontconfig 直接顶替——fontconfig 对任何
/// 请求名都返回一个替代品，替代品可能是比例字体；而终端是按固定格子绘字的
/// （格子宽度由 `mmmmmmmmmm` 量出），比例字形落进格子就会散成一堆缝。
/// 更糟的是这种情况下 `fontFamilyFallback` 不会启用：主族名既然「命中」了替代品，
/// 回退链就永远轮不到。所以「能被用户选中的字体」必须是我们自带的。
enum TerminalFont {
  jetBrainsMono('NoShell JetBrains Mono'),
  firaCode('NoShell Fira Code'),
  systemMonospace('monospace');

  const TerminalFont(this.family);

  /// 交给文本引擎的族名：内置项与 `pubspec.yaml` 的 `fonts:` 声明一一对应。
  final String family;

  /// 缺字形回退链：只在内置字体没有该字形时逐项尝试（中文、emoji、Nerd 图标）。
  /// 取自 xterm 自带的默认链，但末尾不收 `sans-serif` —— 比例字形落进终端
  /// 网格比缺字更难看。注意回退链管的是「缺字形」，管不了「缺字体」。
  static const List<String> _glyphFallback = [
    'Menlo',
    'Monaco',
    'Consolas',
    'Liberation Mono',
    'Courier New',
    'Noto Sans Mono CJK SC',
    'Noto Sans Mono CJK TC',
    'Noto Sans Mono CJK KR',
    'Noto Sans Mono CJK JP',
    'Noto Sans Mono CJK HK',
    'Noto Color Emoji',
    'Noto Sans Symbols',
    'monospace',
  ];

  List<String> get fallback => _glyphFallback;

  /// 字体名是品牌名，不进 l10n；只有「系统等宽」这类描述性文案才翻译。
  String label(AppLocalizations l10n) => switch (this) {
    TerminalFont.jetBrainsMono => 'JetBrains Mono',
    TerminalFont.firaCode => 'Fira Code',
    TerminalFont.systemMonospace => l10n.fontSystemMonospace,
  };
}

/// 内置字体的许可文本（显示名 → asset 路径），启动时注册进 [LicenseRegistry]。
/// 每个内置字体族都必须在这里有一条：OFL 要求分发字体时随附许可。
const Map<String, String> kBundledFontLicenses = {
  'JetBrains Mono': 'assets/fonts/jetbrains_mono/OFL.txt',
  'Fira Code': 'assets/fonts/fira_code/OFL.txt',
};

/// 终端配色预设：绝对配色表，不随应用明暗主题翻转；默认深色。
enum TerminalPreset {
  githubDark,
  dracula,
  oneDark,
  nord,
  tokyoNight,
  gruvboxDark,
  monokai,
  solarizedDark,
  githubLight;

  /// 参考各官方 / 社区终端配色的常用取值。
  TerminalTheme get theme => switch (this) {
    TerminalPreset.githubDark => const TerminalTheme(
      cursor: Color(0xFF3FB950),
      selection: Color(0x264C8DFF),
      foreground: Color(0xFFD6DEE7),
      background: Color(0xFF0A0C0F),
      black: Color(0xFF484F58),
      red: Color(0xFFF85149),
      green: Color(0xFF3FB950),
      yellow: Color(0xFFD29922),
      blue: Color(0xFF58A6FF),
      magenta: Color(0xFFBC8CFF),
      cyan: Color(0xFF39C5CF),
      white: Color(0xFFB9C4CF),
      brightBlack: Color(0xFF6E7681),
      brightRed: Color(0xFFFF7B72),
      brightGreen: Color(0xFF7EE787),
      brightYellow: Color(0xFFFFEA7F),
      brightBlue: Color(0xFF79C0FF),
      brightMagenta: Color(0xFFD2A8FF),
      brightCyan: Color(0xFF67E8F9),
      brightWhite: Color(0xFFF0F6FC),
      searchHitBackground: Color(0xFFFFFF2B),
      searchHitBackgroundCurrent: Color(0xFF31FF26),
      searchHitForeground: Color(0xFF000000),
    ),
    TerminalPreset.githubLight => const TerminalTheme(
      cursor: Color(0xFF24292F),
      selection: Color(0x260550AE),
      foreground: Color(0xFF24292F),
      background: Color(0xFFFFFFFF),
      black: Color(0xFF24292F),
      red: Color(0xFFCF222E),
      green: Color(0xFF116329),
      yellow: Color(0xFF9A6700),
      blue: Color(0xFF0550AE),
      magenta: Color(0xFF8250DF),
      cyan: Color(0xFF1B7C83),
      white: Color(0xFFD0D7DE),
      brightBlack: Color(0xFF57606A),
      brightRed: Color(0xFFA40E26),
      brightGreen: Color(0xFF1A7F37),
      brightYellow: Color(0xFFBF8700),
      brightBlue: Color(0xFF0969DA),
      brightMagenta: Color(0xFFA475F9),
      brightCyan: Color(0xFF3192AA),
      brightWhite: Color(0xFFF6F8FA),
      searchHitBackground: Color(0x33FFD33D),
      searchHitBackgroundCurrent: Color(0xFF31FF26),
      searchHitForeground: Color(0xFF000000),
    ),
    TerminalPreset.dracula => const TerminalTheme(
      cursor: Color(0xFFF8F8F0),
      selection: Color(0xFF44475A),
      foreground: Color(0xFFF8F8F2),
      background: Color(0xFF282A36),
      black: Color(0xFF21222C),
      red: Color(0xFFFF5555),
      green: Color(0xFF50FA7B),
      yellow: Color(0xFFF1FA8C),
      blue: Color(0xFFBD93F9),
      magenta: Color(0xFFFF79C6),
      cyan: Color(0xFF8BE9FD),
      white: Color(0xFFF8F8F2),
      brightBlack: Color(0xFF6272A4),
      brightRed: Color(0xFFFF6E6E),
      brightGreen: Color(0xFF69FF94),
      brightYellow: Color(0xFFFFFFA5),
      brightBlue: Color(0xFFD6ACFF),
      brightMagenta: Color(0xFFFF92DF),
      brightCyan: Color(0xFFA4FFFF),
      brightWhite: Color(0xFFFFFFFF),
      searchHitBackground: Color(0xFFFFFF2B),
      searchHitBackgroundCurrent: Color(0xFF31FF26),
      searchHitForeground: Color(0xFF000000),
    ),
    TerminalPreset.oneDark => const TerminalTheme(
      cursor: Color(0xFF61AFEF),
      selection: Color(0xFF3E4451),
      foreground: Color(0xFFABB2BF),
      background: Color(0xFF282C34),
      black: Color(0xFF282C34),
      red: Color(0xFFE06C75),
      green: Color(0xFF98C379),
      yellow: Color(0xFFE5C07B),
      blue: Color(0xFF61AFEF),
      magenta: Color(0xFFC678DD),
      cyan: Color(0xFF56B6C2),
      white: Color(0xFFDCDFE4),
      brightBlack: Color(0xFF5C6370),
      brightRed: Color(0xFFE06C75),
      brightGreen: Color(0xFF98C379),
      brightYellow: Color(0xFFE5C07B),
      brightBlue: Color(0xFF61AFEF),
      brightMagenta: Color(0xFFC678DD),
      brightCyan: Color(0xFF56B6C2),
      brightWhite: Color(0xFFFFFFFF),
      searchHitBackground: Color(0xFFFFFF2B),
      searchHitBackgroundCurrent: Color(0xFF31FF26),
      searchHitForeground: Color(0xFF000000),
    ),
    TerminalPreset.nord => const TerminalTheme(
      cursor: Color(0xFFD8DEE9),
      selection: Color(0xFF434C5E),
      foreground: Color(0xFFD8DEE9),
      background: Color(0xFF2E3440),
      black: Color(0xFF3B4252),
      red: Color(0xFFBF616A),
      green: Color(0xFFA3BE8C),
      yellow: Color(0xFFEBCB8B),
      blue: Color(0xFF81A1C1),
      magenta: Color(0xFFB48EAD),
      cyan: Color(0xFF88C0D0),
      white: Color(0xFFE5E9F0),
      brightBlack: Color(0xFF4C566A),
      brightRed: Color(0xFFBF616A),
      brightGreen: Color(0xFFA3BE8C),
      brightYellow: Color(0xFFEBCB8B),
      brightBlue: Color(0xFF81A1C1),
      brightMagenta: Color(0xFFB48EAD),
      brightCyan: Color(0xFF8FBCBB),
      brightWhite: Color(0xFFECEFF4),
      searchHitBackground: Color(0xFFFFFF2B),
      searchHitBackgroundCurrent: Color(0xFF31FF26),
      searchHitForeground: Color(0xFF000000),
    ),
    TerminalPreset.tokyoNight => const TerminalTheme(
      cursor: Color(0xFFC0CAF5),
      selection: Color(0xFF33467C),
      foreground: Color(0xFFC0CAF5),
      background: Color(0xFF1A1B26),
      black: Color(0xFF15161E),
      red: Color(0xFFF7768E),
      green: Color(0xFF9ECE6A),
      yellow: Color(0xFFE0AF68),
      blue: Color(0xFF7AA2F7),
      magenta: Color(0xFFBB9AF7),
      cyan: Color(0xFF7DCFFF),
      white: Color(0xFFA9B1D6),
      brightBlack: Color(0xFF414868),
      brightRed: Color(0xFFF7768E),
      brightGreen: Color(0xFF9ECE6A),
      brightYellow: Color(0xFFE0AF68),
      brightBlue: Color(0xFF7AA2F7),
      brightMagenta: Color(0xFFBB9AF7),
      brightCyan: Color(0xFF7DCFFF),
      brightWhite: Color(0xFFC0CAF5),
      searchHitBackground: Color(0xFFFFFF2B),
      searchHitBackgroundCurrent: Color(0xFF31FF26),
      searchHitForeground: Color(0xFF000000),
    ),
    TerminalPreset.gruvboxDark => const TerminalTheme(
      cursor: Color(0xFFEBDBB2),
      selection: Color(0xFF504945),
      foreground: Color(0xFFEBDBB2),
      background: Color(0xFF282828),
      black: Color(0xFF282828),
      red: Color(0xFFCC241D),
      green: Color(0xFF98971A),
      yellow: Color(0xFFD79921),
      blue: Color(0xFF458588),
      magenta: Color(0xFFB16286),
      cyan: Color(0xFF689D6A),
      white: Color(0xFFA89984),
      brightBlack: Color(0xFF928374),
      brightRed: Color(0xFFFB4934),
      brightGreen: Color(0xFFB8BB26),
      brightYellow: Color(0xFFFABD2F),
      brightBlue: Color(0xFF83A598),
      brightMagenta: Color(0xFFD3869B),
      brightCyan: Color(0xFF8EC07C),
      brightWhite: Color(0xFFFBF1C7),
      searchHitBackground: Color(0xFFFFFF2B),
      searchHitBackgroundCurrent: Color(0xFF31FF26),
      searchHitForeground: Color(0xFF000000),
    ),
    TerminalPreset.monokai => const TerminalTheme(
      cursor: Color(0xFFF8F8F0),
      selection: Color(0xFF49483E),
      foreground: Color(0xFFF8F8F2),
      background: Color(0xFF272822),
      black: Color(0xFF272822),
      red: Color(0xFFF92672),
      green: Color(0xFFA6E22E),
      yellow: Color(0xFFF4BF75),
      blue: Color(0xFF66D9EF),
      magenta: Color(0xFFAE81FF),
      cyan: Color(0xFFA1EFE4),
      white: Color(0xFFF8F8F2),
      brightBlack: Color(0xFF75715E),
      brightRed: Color(0xFFF92672),
      brightGreen: Color(0xFFA6E22E),
      brightYellow: Color(0xFFF4BF75),
      brightBlue: Color(0xFF66D9EF),
      brightMagenta: Color(0xFFAE81FF),
      brightCyan: Color(0xFFA1EFE4),
      brightWhite: Color(0xFFF9F8F5),
      searchHitBackground: Color(0xFFFFFF2B),
      searchHitBackgroundCurrent: Color(0xFF31FF26),
      searchHitForeground: Color(0xFF000000),
    ),
    TerminalPreset.solarizedDark => const TerminalTheme(
      cursor: Color(0xFF93A1A1),
      selection: Color(0xFF274642),
      foreground: Color(0xFF839496),
      background: Color(0xFF002B36),
      black: Color(0xFF073642),
      red: Color(0xFFDC322F),
      green: Color(0xFF859900),
      yellow: Color(0xFFB58900),
      blue: Color(0xFF268BD2),
      magenta: Color(0xFFD33682),
      cyan: Color(0xFF2AA198),
      white: Color(0xFFEEE8D5),
      brightBlack: Color(0xFF586E75),
      brightRed: Color(0xFFCB4B16),
      brightGreen: Color(0xFF93A72D),
      brightYellow: Color(0xFFE0B000),
      brightBlue: Color(0xFF40A3D8),
      brightMagenta: Color(0xFFE06CA0),
      brightCyan: Color(0xFF3FC5D4),
      brightWhite: Color(0xFFFDF6E3),
      searchHitBackground: Color(0xFFFFFF2B),
      searchHitBackgroundCurrent: Color(0xFF31FF26),
      searchHitForeground: Color(0xFF000000),
    ),
  };

  String label(AppLocalizations l10n) => switch (this) {
    TerminalPreset.githubDark => l10n.presetDefaultDark,
    TerminalPreset.githubLight => l10n.light,
    TerminalPreset.dracula => 'Dracula',
    TerminalPreset.oneDark => 'One Dark',
    TerminalPreset.nord => 'Nord',
    TerminalPreset.tokyoNight => 'Tokyo Night',
    TerminalPreset.gruvboxDark => 'Gruvbox Dark',
    TerminalPreset.monokai => 'Monokai',
    TerminalPreset.solarizedDark => 'Solarized Dark',
  };
}

/// 终端样式偏好：配色预设 + 字体 + 字号，由 [TerminalStyleScope] 的 notifier
/// 全局持有。
class TerminalStylePrefs {
  const TerminalStylePrefs({
    this.preset = TerminalPreset.githubDark,
    this.font = TerminalFont.jetBrainsMono,
    this.fontSize = defaultFontSize,
  });

  /// 字号默认值与范围（逻辑像素）。默认比早先写死的 13 大两号：13 在
  /// 高分屏上偏小，长会话看起来吃力；界面只做 ± 步进，边界收在这里。
  static const defaultFontSize = 15;
  static const minFontSize = 11;
  static const maxFontSize = 22;

  final TerminalPreset preset;
  final TerminalFont font;

  /// 终端字号（逻辑像素）。
  final int fontSize;

  TerminalTheme get theme => preset.theme;

  /// 交给 xterm `TerminalStyle` 的族名：内置项是随包族名，[TerminalFont.systemMonospace]
  /// 是通用族名 `monospace`（由平台解析成真正的系统等宽，绝不会是比例字体）。
  String get resolvedFontFamily => font.family;

  List<String> get fontFallback => font.fallback;

  /// 按步进调整字号；越界夹住，界面不必自己判边界。
  TerminalStylePrefs withFontSize(int value) =>
      copyWith(fontSize: clampFontSize(value));

  /// 把任意来源（界面步进 / 落盘存档）的字号收敛到合法范围：
  /// 非数字或越界都退回合法值，脏存档不至于把终端字号带崩。
  static int clampFontSize(Object? value, {int fallback = defaultFontSize}) {
    final size = value is num ? value.toInt() : int.tryParse('${value ?? ''}');
    if (size == null) return fallback;
    return size < minFontSize
        ? minFontSize
        : (size > maxFontSize ? maxFontSize : size);
  }

  TerminalStylePrefs copyWith({
    TerminalPreset? preset,
    TerminalFont? font,
    int? fontSize,
  }) => TerminalStylePrefs(
    preset: preset ?? this.preset,
    font: font ?? this.font,
    fontSize: fontSize ?? this.fontSize,
  );

  /// 值相等即同一份偏好。
  ///
  /// 这不只是整洁问题：`TerminalStyleScope` 用 [ValueNotifier] 承载它，
  /// 而 ValueNotifier 的守卫是**身份**比较。没有 `==` 时，重复点选同一个
  /// 预设也会发出一次通知，下游终端随之重建（xterm 会重新量字符宽度并
  /// 清空段落缓存），还会多写一次盘。无变化守卫在这一层就得成立。
  @override
  bool operator ==(Object other) =>
      other is TerminalStylePrefs &&
      other.preset == preset &&
      other.font == font &&
      other.fontSize == fontSize;

  @override
  int get hashCode => Object.hash(preset, font, fontSize);
}

/// 终端样式作用域：挂在 MaterialApp.builder 之上，
/// 普通页面、全屏路由与对话框都能读取；内容变化经 notifier 通知，按需局部重建。
final class TerminalStyleScope extends InheritedWidget {
  const TerminalStyleScope({
    super.key,
    required this.notifier,
    required super.child,
  });

  final ValueNotifier<TerminalStylePrefs> notifier;

  static TerminalStyleScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TerminalStyleScope>()!;

  @override
  bool updateShouldNotify(TerminalStyleScope oldWidget) => false;
}
