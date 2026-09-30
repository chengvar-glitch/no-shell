@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/ssh/local_files.dart';

/// 宿主通道（`DownloadsChannel`）在测试里的替身。
const _channel = MethodChannel('com.noshell/downloads');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  /// 宿主交回来的 fd 路径。测试里用真实临时文件顶替 `/proc/self/fd/N`：
  /// 应用侧那条路本来就是「拿一个可写的路径，用 dart:io 往里灌数据」。
  late String writePath;

  late List<MethodCall> calls;

  void mockHost({
    bool mediaStore = true,
    bool beginFails = false,
    String? promotedName,
    String? legacyPath,
    bool storageGranted = false,
    bool storageRequestGranted = true,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'mediaStoreAvailable':
              return mediaStore;
            case 'begin':
              if (beginFails) {
                throw PlatformException(code: 'downloads_failed');
              }
              return writePath;
            case 'finish':
              return promotedName ?? call.arguments['name'];
            case 'abort':
              return true;
            case 'share':
              return true;
            case 'legacyPath':
              return legacyPath;
            case 'hasStoragePermission':
              return storageGranted;
            case 'requestStoragePermission':
              return storageRequestGranted;
          }
          return null;
        });
  }

  List<String> methods() => [for (final call in calls) call.method];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('noshell-android-downloads');
    writePath = '${dir.path}/write.bin';
    calls = [];
    // 条件导出的 io 版本按 defaultTargetPlatform 判断平台；测试宿主不是
    // Android，得显式覆盖。探测 / 权限结果另有进程级缓存，每个用例前清掉。
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    debugResetAndroidDownloadProbe();
    mockHost();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    debugResetAndroidDownloadProbe();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('Android 10+：MediaStore 那支', () {
    test('探通之后下载落点落在系统下载目录，探测自己建行也自己收尾', () async {
      final target = await const NativeLocalFileGateway().pickDownloadTarget(
        'nginx.conf',
      );

      expect(target, isNotNull);
      expect(isMediaStoreDownloadPath(target!.path), isTrue);
      expect(target.name, 'nginx.conf');
      expect(
        methods(),
        containsAllInOrder(['mediaStoreAvailable', 'begin', 'abort']),
      );
      // 探测写的那条记录与用户要下的文件不是一回事，名字带前缀分开。
      expect(calls[1].arguments['name'], isNot('nginx.conf'));
    });

    test('探测结果会缓存：同一次运行里不反复建行试探', () async {
      const gateway = NativeLocalFileGateway();
      await gateway.pickDownloadTarget('a.conf');
      await gateway.pickDownloadTarget('b.conf');

      expect(methods().where((m) => m == 'mediaStoreAvailable'), hasLength(1));
      expect(methods().where((m) => m == 'begin'), hasLength(1));
    });

    test('落点本身就是临时态：不加 .noshell-part，也不问要不要覆盖', () async {
      const gateway = NativeLocalFileGateway();
      const token = 'mediastore:a.conf';

      expect(gateway.temporaryPath(token), token);
      // 重名由系统改成 `a (1).conf`，没有「覆盖」这个动作可确认。
      expect(await gateway.localFileExists(token), isFalse);
    });

    test('写入经 MediaStore 记录，收尾回报系统改名后的真实文件名', () async {
      mockHost(promotedName: 'nginx (1).conf');
      const gateway = NativeLocalFileGateway();
      const token = 'mediastore:nginx.conf';

      final handle = await gateway.openWrite(token, ownerOnly: true);
      handle.add([1, 2, 3]);
      await handle.close();
      final name = await gateway.promote(token, token);

      expect(File(writePath).readAsBytesSync(), [1, 2, 3]);
      expect(name, 'nginx (1).conf');
      expect(methods(), containsAllInOrder(['begin', 'finish']));
      expect(calls.first.arguments['name'], 'nginx.conf');
    });

    test('半成品按同一个落点清掉', () async {
      await const NativeLocalFileGateway().discard('mediastore:a.conf');

      expect(calls.single.method, 'abort');
      expect(calls.single.arguments['name'], 'a.conf');
    });

    test('分享走宿主：文件在共享集合里，不拷第二份', () async {
      await const NativeLocalFileGateway().shareDownload(
        'mediastore:a.conf',
        title: 'a.conf',
      );

      expect(calls.single.method, 'share');
      expect(calls.single.arguments['name'], 'a.conf');
      expect(calls.single.arguments['title'], 'a.conf');
    });
  });

  group('Android 9 及以下：真路径那支', () {
    test('拿到存储权限后落点是公共下载目录里的真路径', () async {
      mockHost(mediaStore: false, legacyPath: dir.path);

      final target = await const NativeLocalFileGateway().pickDownloadTarget(
        'a.conf',
      );

      expect(target, isNotNull);
      expect(androidDownloadRealPath(target!.path), '${dir.path}/a.conf');
      expect(
        methods(),
        containsAllInOrder([
          'mediaStoreAvailable',
          'legacyPath',
          'hasStoragePermission',
          'requestStoragePermission',
        ]),
      );
    });

    test('落点仍是「先写临时、成功再改名」，且不收紧权限', () async {
      mockHost(mediaStore: false, legacyPath: dir.path, storageGranted: true);
      const gateway = NativeLocalFileGateway();
      final target = await gateway.pickDownloadTarget('a.conf');
      final real = androidDownloadRealPath(target!.path)!;

      final temporary = gateway.temporaryPath(target.path);
      expect(androidDownloadRealPath(temporary), '$real.noshell-part');
      // 已经有了权限：这一支不该再去弹权限框。
      expect(methods(), isNot(contains('requestStoragePermission')));

      final handle = await gateway.openWrite(temporary, ownerOnly: true);
      handle.add([7]);
      await handle.close();
      await gateway.promote(temporary, target.path);

      expect(File(real).readAsBytesSync(), [7]);
      expect(File(temporary).existsSync(), isFalse);
      expect(await gateway.localFileExists(target.path), isTrue);
      if (!Platform.isWindows) {
        // 公共目录里的文件要让别的应用读得到（相册 / 办公套件都靠读它），
        // 所以这里的 ownerOnly 刻意不生效。
        expect(File(real).statSync().mode & 0x1FF, isNot(0x180));
      }
    });

    test('权限被拒就退回应用目录，而且只问一次', () async {
      mockHost(
        mediaStore: false,
        legacyPath: dir.path,
        storageGranted: false,
        storageRequestGranted: false,
      );
      const gateway = NativeLocalFileGateway();

      final first = await gateway.pickDownloadTarget('a.conf');
      final asked = methods()
          .where((m) => m == 'requestStoragePermission')
          .length;
      final second = await gateway.pickDownloadTarget('b.conf');

      expect(isAndroidDownloadPath(first!.path), isFalse);
      expect(first.path, endsWith('a.conf'));
      expect(second, isNotNull);
      expect(isAndroidDownloadPath(second!.path), isFalse);
      expect(asked, 1);
      expect(
        methods().where((m) => m == 'requestStoragePermission'),
        hasLength(1),
      );
    });
  });

  group('公共下载目录走不了时', () {
    test('MediaStore 探不通、又没有真路径那支，就退回原来的落点', () async {
      mockHost(mediaStore: false, beginFails: true);

      final target = await const NativeLocalFileGateway().pickDownloadTarget(
        'a.conf',
      );

      expect(target, isNotNull);
      expect(isAndroidDownloadPath(target!.path), isFalse);
      expect(target.path, endsWith('a.conf'));
    });

    test('非 Android 平台一次通道都不碰', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      debugResetAndroidDownloadProbe();

      final target = await const NativeLocalFileGateway().pickDownloadTarget(
        'a.conf',
      );

      expect(target, isNotNull);
      expect(isAndroidDownloadPath(target!.path), isFalse);
      expect(calls, isEmpty);
    });
  });
}
