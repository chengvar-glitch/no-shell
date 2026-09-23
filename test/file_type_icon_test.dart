import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:no_shell/widgets/file_type_icon.dart';

/// 文件类型图标的接线校验。
///
/// 这条链上的错都不会报错，只会静默降级：资产漏打包 → 运行时读不到、
/// 图标位置出现空白；许可漏随附 → MIT 的分发要求缺失。
/// 全部靠这里的断言守住（模式与 font_assets_test 相同）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pubspec = File('pubspec.yaml').readAsStringSync();

  /// 映射表里出现过的全部资产文件名（扩展名表 + 整名表 + 兜底）。
  final allIcons = {
    ...kFileTypeIconByExtension.values,
    ...kFileTypeIconByName.values,
  };

  test('扩展名映射：常见类型各有图标', () {
    expect(fileTypeIconAsset('a.js'), contains('file_type_javascript.svg'));
    expect(fileTypeIconAsset('b.DART'), contains('file_type_dartlang.svg'));
    expect(fileTypeIconAsset('c.tar.gz'), contains('file_type_zip.svg'));
    expect(fileTypeIconAsset('dump.sql'), contains('file_type_sql.svg'));
    // 配置类后缀：.cnf（my.cnf）与 systemd 单元 .service 走配置齿轮。
    expect(fileTypeIconAsset('my.cnf'), contains('file_type_config.svg'));
    expect(fileTypeIconAsset('app.service'), contains('file_type_config.svg'));
  });

  test('整名映射：Dockerfile 与点开头的隐藏文件取不到扩展名，按名字认', () {
    expect(fileTypeIconAsset('Dockerfile'), contains('file_type_docker.svg'));
    expect(fileTypeIconAsset('.gitignore'), contains('file_type_git.svg'));
    // 反例：dot.zip 的扩展名正常取到，不走整名表。
    expect(fileTypeIconAsset('.gitignore.bak'), contains('default_file.svg'));
  });

  test('认不出的一律回落到通用文件图标，永不抛错', () {
    expect(fileTypeIconAsset('no-extension'), contains('default_file.svg'));
    expect(fileTypeIconAsset('x.unknownext'), contains('default_file.svg'));
    expect(fileTypeIconAsset(''), contains('default_file.svg'));
  });

  test('映射到的每个 SVG 都真实存在', () {
    for (final icon in allIcons) {
      final path = '$_assetDirForTest/$icon';
      expect(File(path).existsSync(), isTrue, reason: '$path 不存在');
    }
  });

  test('图标目录在 pubspec 的 assets 里按目录声明，运行时读得到', () {
    expect(
      pubspec,
      contains('$_assetDirForTest/'),
      reason: 'assets 必须按目录声明，否则运行时读不到',
    );
  });

  test('每个映射到的 SVG 都能经 rootBundle 读出内容（打包链路校验）', () async {
    for (final icon in allIcons) {
      final bytes = await rootBundle.load('$_assetDirForTest/$icon');
      expect(bytes.lengthInBytes, greaterThan(0), reason: '$icon 是空文件');
    }
  });

  test('MIT 许可随包分发：登记、声明、文件、内容四样齐全', () {
    final license = kFileTypeIconLicenses['vscode-icons'];
    expect(license, isNotNull, reason: 'MIT 要求分发时随附许可，缺登记');
    // 许可文本随图标目录整体打包，pubspec 里只声明目录。
    expect(
      pubspec,
      contains('$_assetDirForTest/'),
      reason: '许可文本所在目录未在 assets 声明，运行时读不到',
    );
    expect(File(license!).existsSync(), isTrue, reason: '$license 不存在');
    expect(
      File(license).readAsStringSync(),
      contains('MIT License'),
      reason: '$license 不像 MIT 文本',
    );
  });
}

/// 测试里拿不到私有常量，目录前缀单独声明；file_type_icon.dart 改目录时同步。
const _assetDirForTest = 'assets/icons/file_type';
