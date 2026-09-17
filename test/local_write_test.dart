@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/ssh/local_write.dart';

/// 文件模式位（Permission denied 之外，mode 的低 9 位）。
int _modeOf(String path) => File(path).statSync().mode & 0x1FF;

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('noshell-local-write');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('openLocalWrite 权限', () {
    test('ownerOnly 建出来的文件是 0600（导出备份含明文密码）', () async {
      final path = '${dir.path}/hosts.nsbak';
      final handle = openLocalWrite(path, ownerOnly: true);
      handle.add([1, 2, 3]);
      await handle.close();

      expect(File(path).readAsBytesSync(), [1, 2, 3]);
      if (!Platform.isWindows) {
        expect(
          _modeOf(path),
          0x180, // 0600
          reason: '备份文件不能对同机器上的其他账号可读',
        );
      }
    });

    test('默认不收紧权限，普通下载不受影响', () async {
      final path = '${dir.path}/plain.bin';
      final handle = openLocalWrite(path);
      handle.add([9]);
      await handle.close();
      expect(File(path).readAsBytesSync(), [9]);
    });

    test('ownerOnly 覆盖已存在的文件时沿用原文件权限', () async {
      final path = '${dir.path}/exists.nsbak';
      File(path).writeAsStringSync('old');
      final handle = openLocalWrite(path, ownerOnly: true);
      handle.add([7]);
      await handle.close();

      expect(File(path).readAsBytesSync(), [7]);
    });
  });

  group('promoteLocalFile 改名', () {
    test('临时文件改名到目标，覆盖目标上的旧内容', () async {
      final target = '${dir.path}/target.bin';
      final temporary = localTemporaryPath(target);
      File(target).writeAsBytesSync([1, 1, 1]);
      File(temporary).writeAsBytesSync([2, 2, 2]);

      await promoteLocalFile(temporary, target);

      expect(File(target).readAsBytesSync(), [2, 2, 2]);
      expect(File(temporary).existsSync(), isFalse);
    });

    test('目标不存在时改名同样成立', () async {
      final target = '${dir.path}/fresh.bin';
      final temporary = localTemporaryPath(target);
      File(temporary).writeAsBytesSync([5]);

      await promoteLocalFile(temporary, target);

      expect(File(target).readAsBytesSync(), [5]);
    });

    test('临时文件不存在时抛出，由调用方决定怎么收场', () async {
      final target = '${dir.path}/missing.bin';
      expect(
        () => promoteLocalFile(localTemporaryPath(target), target),
        throwsA(isA<FileSystemException>()),
      );
      // 目标未被创建，也不会被删。
      expect(File(target).existsSync(), isFalse);
    });
  });
}
