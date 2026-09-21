import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_locale.dart';
import 'settings.dart';

/// 当前落盘的「默认值版本」。**改动任一偏好的出厂默认值时把它 +1**，
/// 老用户的存档才会被按新默认读取一次（用户自己改过的项除外，
/// 见 [AppSettings.fromJson]）。
///
/// 它不是存档格式的版本：字段增删不必动它，它只回答「这份存档是在哪一代
/// 默认值下写出来的」。需要它的原因：老版本每次保存设置都会把当时的默认值
/// 写进 JSON，于是字段既不是缺的、也不代表用户选过——只靠「缺字段就用新默认」
/// 的兜底，改默认值对老用户永远不会生效（`copyOnSelect` 踩过这个坑：
/// 默认从关改成开后，用户界面里仍然是关的）。
const int kDefaultsVersion = 2;

/// 引入默认值版本标记**之前**那一代的编号（老存档读出来就是它）。
/// 比它旧的存档里，`copyOnSelect` 存着的是那时的出厂默认，不是用户的选择。
const int kLegacyDefaultsVersion = 1;

/// 落盘的偏好快照：主题 / 语言 + 终端样式（配色、字体、字号）+ 连接兼容性。
///
/// 只存枚举名而不是索引：以后往枚举中间插值也不会把存档读串。
/// 单个字段读不出来只退回该字段的默认值，不让一条脏数据带走整份偏好。
/// 不认得的字段读时忽略、下次保存即被抹掉。
///
/// 唯一的例外是 [kDefaultsVersion] 标记：它区分「老版本顺手写下的默认值」
/// 与「用户自己的选择」——见那个常量的说明。
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.language = AppLanguage.system,
    this.terminalStyle = const TerminalStylePrefs(),
    this.allowLegacyHostKeys = false,
    this.quickPreviewLimit = QuickPreviewLimit.defaultLimit,
  });

  final ThemeMode themeMode;
  final AppLanguage language;
  final TerminalStylePrefs terminalStyle;

  /// 是否允许连接只提供 `ssh-rsa`（SHA-1）主机密钥的老设备。
  ///
  /// 默认关闭：SHA-1 签名早已不该被信任，现代 sshd 也默认不再提供它。
  /// 但交换机 / 嵌入式设备这类只在旧固件上跑的机器确实还会用到，
  /// 因此给一个显式开关，而不是把算法放宽成默认行为。
  final bool allowLegacyHostKeys;

  /// SFTP 快速预览允许读入内存的最大字节数档位。
  ///
  /// 存枚举名而不是裸字节数：以后调整档位定义或插入新档位时，
  /// 旧存档仍能按名字落到正确语义上。
  final QuickPreviewLimit quickPreviewLimit;

  AppSettings copyWith({
    ThemeMode? themeMode,
    AppLanguage? language,
    TerminalStylePrefs? terminalStyle,
    bool? allowLegacyHostKeys,
    QuickPreviewLimit? quickPreviewLimit,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    language: language ?? this.language,
    terminalStyle: terminalStyle ?? this.terminalStyle,
    allowLegacyHostKeys: allowLegacyHostKeys ?? this.allowLegacyHostKeys,
    quickPreviewLimit: quickPreviewLimit ?? this.quickPreviewLimit,
  );

  Map<String, Object?> toJson() => {
    'defaultsVersion': kDefaultsVersion,
    'themeMode': themeMode.name,
    'language': language.name,
    'terminalPreset': terminalStyle.preset.name,
    'terminalFont': terminalStyle.font.name,
    'terminalFontSize': terminalStyle.fontSize,
    'terminalCopyOnSelect': terminalStyle.copyOnSelect,
    'allowLegacyHostKeys': allowLegacyHostKeys,
    'quickPreviewLimit': quickPreviewLimit.name,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    // 老存档没有这个标记，按「上一代默认值」处理；一旦保存过就会带上当前值。
    final savedDefaultsVersion = switch (json['defaultsVersion']) {
      final int value => value,
      _ => 0,
    };
    return AppSettings(
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
        font: _enumByName(
          TerminalFont.values,
          json['terminalFont'],
          TerminalFont.jetBrainsMono,
        ),
        fontSize: TerminalStylePrefs.clampFontSize(json['terminalFontSize']),
        // 没带标记的存档（标记出现之前存的）一律给新默认（打开，即
        // `TerminalStylePrefs()` 的出厂值）：里面那个 false 是那时的出厂默认，
        // 不是用户按过的值——不这样，改默认值对老用户就永远不生效。代价是
        // 老存档里用户自己关过的开关也会被打开一次。
        // 带上标记之后，存档里的值就是用户的选择，此后原样读回、不再被覆盖。
        copyOnSelect: savedDefaultsVersion >= kDefaultsVersion
            ? json['terminalCopyOnSelect'] == true
            : const TerminalStylePrefs().copyOnSelect,
      ),
      // 缺字段（旧存档）即默认关闭。
      allowLegacyHostKeys: json['allowLegacyHostKeys'] == true,
      quickPreviewLimit: _enumByName(
        QuickPreviewLimit.values,
        json['quickPreviewLimit'],
        QuickPreviewLimit.defaultLimit,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode == themeMode &&
      other.language == language &&
      other.terminalStyle.preset == terminalStyle.preset &&
      other.terminalStyle.font == terminalStyle.font &&
      other.terminalStyle.fontSize == terminalStyle.fontSize &&
      other.terminalStyle.copyOnSelect == terminalStyle.copyOnSelect &&
      other.allowLegacyHostKeys == allowLegacyHostKeys &&
      other.quickPreviewLimit == quickPreviewLimit;

  @override
  int get hashCode => Object.hash(
    themeMode,
    language,
    terminalStyle.preset,
    terminalStyle.font,
    terminalStyle.fontSize,
    terminalStyle.copyOnSelect,
    allowLegacyHostKeys,
    quickPreviewLimit,
  );
}

/// 按名字取枚举值；读不到（旧存档 / 脏数据）就退回默认值。
///
/// 不做旧取值迁移：本应用还在开发阶段，存档格式不背历史包袱
/// （见 AGENTS.md「导入 / 导出」一节对格式的态度）。
T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  return values.asNameMap()[name] ?? fallback;
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
