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

    test('默认不收紧权限，普通下载落点不受影响', () async {
      final path = '${dir.path}/plain.bin';
      final handle = openLocalWrite(path);
      handle.add([9]);
      await handle.close();
      expect(File(path).readAsBytesSync(), [9]);
      if (!Platform.isWindows) {
        // 走进程 umask，不主动改权限位（默认 022 下是 0644）。
        expect(_modeOf(path), isNot(0x180), reason: '没要求 ownerOnly 就不该动权限');
      }
    });

    test('ownerOnly 覆盖已存在的文件时把权限收回 0600', () async {
      final path = '${dir.path}/exists.nsbak';
      File(path).writeAsStringSync('old');
      if (!Platform.isWindows) {
        // 上一次导出留下的文件（或用户自己建的），先给它一个宽松权限位。
        Process.runSync('chmod', ['0644', path]);
        expect(_modeOf(path), 0x1A4);
      }

      final handle = openLocalWrite(path, ownerOnly: true);
      handle.add([7]);
      await handle.close();

      expect(File(path).readAsBytesSync(), [7]);
      if (!Platform.isWindows) {
        // 沿用原权限位等于让同机器上任何本地账号都能读到这里刚写进去的密码。
        expect(
          _modeOf(path),
          0x180, // 0600
          reason: '覆盖导出时也要把权限收回来',
        );
      }
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
