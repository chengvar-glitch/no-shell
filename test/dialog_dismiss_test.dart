/// 弹窗一律「点遮罩不关」：误点窗口空白处不再把弹窗（连输入）一起收走。
///
/// 这条行为由框架保证——`barrierDismissible: false` 一设，遮罩点击就不再生效——
/// 所以这里不逐个弹窗去点一遍，只守住「每一处 showDialog 都带了这个开关」这条
/// 不变量：新加弹窗时漏写会被这条用例拦下（`busy_overlay.dart` 一直这么写）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('每一处 showDialog 都关掉了点遮罩关闭', () {
    // 调用与开关之间隔着 builder，给足几行（最长的那个还夹着 useSafeArea）。
    const lookahead = 6;
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // 注释里提到 showDialog（说明、文档）不算调用点。
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (!lines[i].contains('showDialog')) continue;
        final call = lines.skip(i).take(lookahead).join('\n');
        if (!call.contains('barrierDismissible')) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty, reason: '这些 showDialog 会被点遮罩关掉');
  });
}
