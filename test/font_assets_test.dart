import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:no_shell/settings.dart';

/// 随包字体的接线校验。
///
/// 字体这条链上的错都不会报错，只会静默降级：族名写错 → 引擎去系统里找替代
/// （Linux 上可能拿到比例字体，终端网格散架）；字体文件漏打包 → 同样的降级；
/// 许可漏打包 → OFL 要求的随附许可缺失。三种静默失败都靠这里的断言守住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pubspec = File('pubspec.yaml').readAsStringSync();
  final fontsSection = _section(pubspec, 'fonts');
  final assetsSection = _section(pubspec, 'assets');

  /// 需要打包的族（`monospace` 是通用族名，由平台解析，不打包）。
  final bundled = [
    for (final font in TerminalFont.values)
      if (font.family != _systemFamily) font,
  ];

  test('内置族名与 pubspec 的 fonts 声明一一对应', () {
    expect(_declaredFamilies(fontsSection), [
      for (final font in bundled) font.family,
    ], reason: '族名是落盘偏好的取值，改名必须同时改存档迁移逻辑');
  });

  test('每个内置族都带常规 + 粗体，且字体文件真实存在', () {
    for (final font in bundled) {
      final block = _familyBlock(fontsSection, font.family);
      expect(block, isNotNull, reason: '${font.family} 缺 fonts 声明');

      final weights = RegExp(r'weight:\s*(\d+)')
          .allMatches(block!)
          .map((m) => int.parse(m.group(1)!))
          .toSet();
      expect(weights, {
        400,
        700,
      }, reason: '${font.family} 必须同时打包常规与粗体，否则粗体只能靠合成');

      for (final asset in _assetsOf(block)) {
        expect(
          File(asset).existsSync(),
          isTrue,
          reason: '$asset 在 pubspec 里声明了但文件不存在',
        );
      }
    }
  });

  test('许可文本随包分发：asset 声明、文件存在、内容是 OFL', () {
    for (final font in bundled) {
      final display = font.family.replaceFirst(_familyPrefix, '');
      final license = kBundledFontLicenses[display];
      expect(license, isNotNull, reason: 'OFL 要求分发字体时随附许可：$display 缺登记');
      expect(
        assetsSection,
        contains(license!),
        reason: '$license 必须在 pubspec 的 assets 里声明，否则运行时读不到',
      );
      expect(File(license).existsSync(), isTrue, reason: '$license 不存在');
      expect(
        File(license).readAsStringSync(),
        contains('SIL OPEN FONT LICENSE'),
        reason: '$license 不像 OFL 文本',
      );
    }
    // 反向：登记了许可却没有对应内置族 = 名单不同步。
    expect(kBundledFontLicenses, hasLength(bundled.length));
  });

  test('FontManifest 里带上了内置族（打包链路本身也校验一次）', () async {
    final manifest = await rootBundle.loadString('FontManifest.json');
    for (final font in bundled) {
      expect(manifest, contains(font.family), reason: '资产包缺 ${font.family}');
    }
  });
}

const _systemFamily = 'monospace';

/// 内置族名的前缀：与系统字体彻底解耦，引擎必定命中随包文件。
const _familyPrefix = 'NoShell ';

/// 取 pubspec 里某个顶层键（两空格缩进）到下一个同级键之间的片段。
String _section(String pubspec, String key) {
  final lines = pubspec.split('\n');
  final start = lines.indexWhere((line) => line.trimRight() == '  $key:');
  if (start < 0) return '';
  final buffer = <String>[];
  for (final line in lines.skip(start + 1)) {
    if (RegExp(r'^  \S').hasMatch(line)) break;
    buffer.add(line);
  }
  return buffer.join('\n');
}

List<String> _declaredFamilies(String fontsSection) => RegExp(
  r'^\s*- family:\s*(.+)$',
  multiLine: true,
).allMatches(fontsSection).map((m) => m.group(1)!.trim()).toList();

String? _familyBlock(String fontsSection, String family) {
  final blocks = fontsSection.split(RegExp(r'^\s*- family:', multiLine: true));
  for (final block in blocks.skip(1)) {
    if (block.trimLeft().startsWith(family)) return block;
  }
  return null;
}

Iterable<String> _assetsOf(String familyBlock) =>
    RegExp(r'asset:\s*(\S+)').allMatches(familyBlock).map((m) => m.group(1)!);
