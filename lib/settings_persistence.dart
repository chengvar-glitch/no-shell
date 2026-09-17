import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_locale.dart';
import 'settings.dart';

/// 落盘的偏好快照：主题 / 语言 + 终端样式（配色、字体、字号）。
///
/// 只存枚举名而不是索引：以后往枚举中间插值也不会把旧存档读串。
/// 单个字段读不出来只退回该字段的默认值，不让一条脏数据带走整份偏好。
/// 已删除的字段（界面字体、终端自定义字体名）读时忽略、下次保存即被抹掉，
/// 不需要额外的存档版本号。
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.language = AppLanguage.system,
    this.terminalStyle = const TerminalStylePrefs(),
  });

  final ThemeMode themeMode;
  final AppLanguage language;
  final TerminalStylePrefs terminalStyle;

  AppSettings copyWith({
    ThemeMode? themeMode,
    AppLanguage? language,
    TerminalStylePrefs? terminalStyle,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    language: language ?? this.language,
    terminalStyle: terminalStyle ?? this.terminalStyle,
  );

  Map<String, Object?> toJson() => {
    'themeMode': themeMode.name,
    'language': language.name,
    'terminalPreset': terminalStyle.preset.name,
    'terminalFont': terminalStyle.font.name,
    'terminalFontSize': terminalStyle.fontSize,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
    themeMode: _enumByName(
      ThemeMode.values,
      json['themeMode'],
      ThemeMode.system,
    ),
    language: _enumByName(
      AppLanguage.values,
      json['language'],
      AppLanguage.system,
    ),
    terminalStyle: TerminalStylePrefs(
      preset: _enumByName(
        TerminalPreset.values,
        json['terminalPreset'],
        TerminalPreset.githubDark,
      ),
      font: _terminalFont(json['terminalFont'], json['terminalCustomFontName']),
      fontSize: TerminalStylePrefs.clampFontSize(json['terminalFontSize']),
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode == themeMode &&
      other.language == language &&
      other.terminalStyle.preset == terminalStyle.preset &&
      other.terminalStyle.font == terminalStyle.font &&
      other.terminalStyle.fontSize == terminalStyle.fontSize;

  @override
  int get hashCode => Object.hash(
    themeMode,
    language,
    terminalStyle.preset,
    terminalStyle.font,
    terminalStyle.fontSize,
  );
}

/// 终端字体的存档迁移：老版本的取值比现在多，逐个映射到现有选项。
///
/// - `system` / `menlo` / `consolas`：用户选的是「系统里的等宽」，
///   换成同语义的 [TerminalFont.systemMonospace]。
/// - `custom`（手填族名）：入口已删除，而它正是 Linux 上被 fontconfig
///   顶替成比例字体、终端排版散架的事故来源，不能把用户留在那个状态；
///   填过 Fira Code 的落到内置 Fira Code，其余统一落到内置默认。
/// - 新取值原样返回；认不出来（脏档 / 更早的档）一律用内置默认。
TerminalFont _terminalFont(Object? name, Object? legacyCustomName) {
  const legacySystemPresets = {'system', 'menlo', 'consolas'};
  if (name is String) {
    for (final font in TerminalFont.values) {
      if (font.name == name) return font;
    }
    if (legacySystemPresets.contains(name)) return TerminalFont.systemMonospace;
    if (name == 'custom') {
      final custom = legacyCustomName;
      if (custom is String && custom.toLowerCase().contains('fira')) {
        return TerminalFont.firaCode;
      }
    }
  }
  return TerminalFont.jetBrainsMono;
}

/// 按名字取枚举值；读不到（旧存档 / 脏数据）就退回默认值。
T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

/// 偏好落盘通道；内存中的唯一状态源仍是 [NoShellApp] 持有的那几个字段与
/// `TerminalStyleScope` 的 notifier。测试可注入内存假实现。
abstract interface class SettingsPersistence {
  /// 读取已保存的偏好；从未保存过返回 null，由调用方按默认值启动。
  /// 存档损坏同样返回 null，让下次保存覆盖为干净数据。
  Future<AppSettings?> load();

  Future<void> save(AppSettings settings);
}

/// 基于 shared_preferences 的 JSON 实现，六个平台均可用（web 为 localStorage）。
/// 只存偏好本身，不含任何凭据。
final class SharedPreferencesSettingsPersistence
    implements SettingsPersistence {
  static const _key = 'app_settings_v1';

  @override
  Future<AppSettings?> load() async {
    final String raw;
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_key);
      if (value == null) return null;
      raw = value;
    } catch (_) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return AppSettings.fromJson(decoded.cast<String, Object?>());
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    // 与 load 同样的兜底：落盘失败只降级为「改动未存档」，不上抛成未处理异常。
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(settings.toJson()));
    } on FormatException {
      return;
    } on TypeError {
      return;
    } catch (_) {
      return;
    }
  }
}
