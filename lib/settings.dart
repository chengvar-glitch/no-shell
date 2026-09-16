import 'package:flutter/material.dart';
import 'package:xterm/ui.dart';

import 'l10n/generated/app_localizations.dart';

/// 界面字体预设：字体名 + 回退链，目标字体未安装时按链回退，不打包字体资产。
enum UiFont {
  system,
  pingFang,
  microsoftYaHei,
  monospace;

  String? get fontFamily => switch (this) {
    UiFont.system => null,
    UiFont.pingFang => 'PingFang SC',
    UiFont.microsoftYaHei => 'Microsoft YaHei',
    UiFont.monospace => 'Menlo',
  };

  List<String> get fallback => switch (this) {
    UiFont.system => const [],
    UiFont.pingFang => const [
      'Helvetica Neue',
      'Microsoft YaHei',
      'Noto Sans CJK SC',
    ],
    UiFont.microsoftYaHei => const [
      'PingFang SC',
      'Noto Sans CJK SC',
      'Helvetica Neue',
    ],
    UiFont.monospace => const [
      'SF Mono',
      'Consolas',
      'DejaVu Sans Mono',
      'Courier New',
    ],
  };

  String label(AppLocalizations l10n) => switch (this) {
    UiFont.system => l10n.fontSystemDefault,
    UiFont.pingFang => 'PingFang 苹方',
    UiFont.microsoftYaHei => 'Microsoft YaHei 雅黑',
    UiFont.monospace => l10n.fontMonospace,
  };
}

/// 终端字体预设：「系统默认」按平台等宽回退链解析。
/// [custom] 允许用户直接填系统里已安装的字体族名 —— 各平台的系统字体枚举
/// 手段差异太大（web / iOS 根本拿不到，Linux 要解析字体文件或跑 fc-list），
/// 这里先给一个跨平台都能用的入口：名字填对就用，填错按回退链降级。
enum TerminalFont {
  system,
  menlo,
  consolas,
  jetbrainsMono,
  custom;

  String? get fontFamily => switch (this) {
    TerminalFont.system => null,
    TerminalFont.menlo => 'Menlo',
    TerminalFont.consolas => 'Consolas',
    TerminalFont.jetbrainsMono => 'JetBrains Mono',
    // 具体字体名由 [TerminalStylePrefs.customFontName] 提供。
    TerminalFont.custom => null,
  };

  List<String> get fallback => switch (this) {
    TerminalFont.system => const [
      'SF Mono',
      'Menlo',
      'Consolas',
      'DejaVu Sans Mono',
    ],
    TerminalFont.menlo => const ['SF Mono', 'DejaVu Sans Mono', 'Consolas'],
    TerminalFont.consolas => const [
      'Cascadia Code',
      'Menlo',
      'DejaVu Sans Mono',
    ],
    TerminalFont.jetbrainsMono => const [
      'Menlo',
      'Consolas',
      'DejaVu Sans Mono',
    ],
    TerminalFont.custom => const ['Menlo', 'Consolas', 'DejaVu Sans Mono'],
  };

  String label(AppLocalizations l10n) => switch (this) {
    TerminalFont.system => l10n.fontSystemDefault,
    TerminalFont.menlo => 'Menlo（macOS）',
    TerminalFont.consolas => 'Consolas（Windows）',
    TerminalFont.jetbrainsMono => 'JetBrains Mono',
    TerminalFont.custom => l10n.fontCustom,
  };
}

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
    this.font = TerminalFont.system,
    this.customFontName = '',
    this.fontSize = defaultFontSize,
  });

  /// 字号默认值与范围（逻辑像素）。默认比早先写死的 13 大两号：13 在
  /// 高分屏上偏小，长会话看起来吃力；界面只做 ± 步进，边界收在这里。
  static const defaultFontSize = 15;
  static const minFontSize = 11;
  static const maxFontSize = 22;

  final TerminalPreset preset;
  final TerminalFont font;

  /// [TerminalFont.custom] 使用的字体族名；其它预设忽略。
  final String customFontName;

  /// 终端字号（逻辑像素）。
  final int fontSize;

  TerminalTheme get theme => preset.theme;

  /// xterm 的 TerminalStyle 要求具体字体名；
  /// 「系统默认」沿用 xterm 的通用等宽族名，由平台解析。
  String get resolvedFontFamily {
    if (font != TerminalFont.custom) return font.fontFamily ?? 'monospace';
    final name = customFontName.trim();
    return name.isEmpty ? 'monospace' : name;
  }

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
    String? customFontName,
    int? fontSize,
  }) => TerminalStylePrefs(
    preset: preset ?? this.preset,
    font: font ?? this.font,
    customFontName: customFontName ?? this.customFontName,
    fontSize: fontSize ?? this.fontSize,
  );
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
