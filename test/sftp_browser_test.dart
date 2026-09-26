import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/ssh/local_files.dart';
import 'package:no_shell/ssh/sftp.dart';
import 'package:no_shell/ssh/sftp_browser.dart';
import 'package:no_shell/ssh/sftp_transfer.dart';

import 'support/sftp_fakes.dart';

/// 组装一个已就绪的控制器：SFTP 通道立即打开，家目录已载入。
Future<({SftpBrowserController controller, FakeSftpFileSystem fs})> ready({
  FakeLocalFileGateway? gateway,
}) async {
  final fs = FakeSftpFileSystem();
  final controller = SftpBrowserController(
    openFileSystem: () async => fs,
    localFiles: gateway ?? FakeLocalFileGateway(),
  );
  await controller.ensureReady();
  return (controller: controller, fs: fs);
}

void main() {
  group('远端路径工具', () {
    test('拼接与切分', () {
      expect(sftpJoin('/etc', 'nginx.conf'), '/etc/nginx.conf');
      expect(sftpJoin('/etc/', 'nginx.conf'), '/etc/nginx.conf');
      expect(sftpParent('/etc/nginx/nginx.conf'), '/etc/nginx');
      expect(sftpParent('/etc'), '/');
      expect(sftpParent('/'), '/');
    });

    test('快捷路径只给 Unix 远端，Windows 盘符路径不给', () {
      final paths = sftpQuickPaths(home: '/home/deploy')
          .map((target) => target.path)
          .toList();
      expect(paths.first, '/');
      expect(paths.contains('/home/deploy'), isTrue);
      expect(paths, containsAll(['/etc', '/var', '/tmp', '/usr']));

      // Win32 OpenSSH 的 SFTP 家目录是这种形态；给它看 /etc 只是误导。
      expect(sftpQuickPaths(home: '/C:/Users/deploy'), isEmpty);
      expect(
        sftpIsWindowsRemotePath('/C:/ProgramData'),
        isTrue,
        reason: 'SFTP 视图里盘符保留 / 前缀',
      );
      expect(sftpIsWindowsRemotePath('/mnt/c/data'), isFalse);

      // 家目录本身是某个常用目录时，用 ~ 表示它，不再重复同名胶囊。
      final homePaths = sftpQuickPaths(home: '/etc');
      expect(homePaths.map((target) => target.label), contains('~'));
      expect(homePaths.map((target) => target.label), isNot(contains('/etc')));
    });

    test('盘符条目名归一：带不带尾斜杠、大小写都收，其余不认', () {
      expect(sftpDriveName('c:'), 'C:');
      expect(sftpDriveName('D:'), 'D:');
      expect(sftpDriveName('e:/'), 'E:');
      expect(sftpDriveName('f:\\'), 'F:');
      expect(sftpDriveName('Users'), isNull);
      expect(sftpDriveName('c'), isNull);
      expect(sftpDriveName('C:/Users'), isNull);
      expect(sftpDriveName(''), isNull);
    });

    test('光秃盘符路径补上斜杠，其余原样', () {
      expect(sftpNormalizedRemotePath('/C:'), '/C:/');
      expect(sftpNormalizedRemotePath('/d:'), '/d:/');
      expect(sftpNormalizedRemotePath('/C:/Users'), '/C:/Users');
      expect(sftpNormalizedRemotePath('/etc'), '/etc');
    });

    test('SFTP 盘符路径 → Windows 原生写法（地址栏编辑态预填）', () {
      expect(sftpPathToWindowsDisplay('/C:/Users/admin'), r'C:\Users\admin');
      expect(sftpPathToWindowsDisplay('/C:/'), r'C:\');
      expect(sftpPathToWindowsDisplay('/etc/nginx'), '/etc/nginx');
    });

    test('Windows 胶囊：~ + 盘符，家目录所在盘必给', () {
      final paths = sftpWindowsQuickPaths(
        home: '/C:/Users/deploy',
        drives: const ['E:', 'D:'],
      );
      expect(paths.map((target) => target.label), ['~', 'C:', 'D:', 'E:']);
      expect(paths.map((target) => target.path), [
        '/C:/Users/deploy',
        '/C:/',
        '/D:/',
        '/E:/',
      ]);

      // 根目录没读到（旧版服务端 / 权限）时至少还有家目录所在盘。
      final fallback = sftpWindowsQuickPaths(home: '/c:/Users/deploy');
      expect(fallback.map((target) => target.label), ['~', 'C:']);

      // 家目录本身就是盘根时用 ~ 表示它，不再重复一颗同名胶囊。
      final atRoot = sftpWindowsQuickPaths(
        home: '/D:/',
        drives: const ['D:', 'E:'],
      );
      expect(atRoot.map((target) => target.label), ['~', 'E:']);

      // Unix 家目录不属于这里（sftpQuickPaths 管那一侧）。
      expect(sftpWindowsQuickPaths(home: '/home/deploy'), isEmpty);
    });

    test('面包屑逐级给出绝对路径', () {
      final crumbs = sftpBreadcrumbs('/var/log/nginx');
      expect(crumbs.map((crumb) => crumb.label), ['/', 'var', 'log', 'nginx']);
      expect(crumbs.last.path, '/var/log/nginx');
    });

    test('家目录及其子目录折成一段', () {
      final home = sftpBreadcrumbs('/home/deploy', home: '/home/deploy');
      expect(home, hasLength(1));
      expect(home.single.isHome, isTrue);
      expect(home.single.path, '/home/deploy');

      final nested = sftpBreadcrumbs(
        '/home/deploy/logs/nginx',
        home: '/home/deploy',
      );
      expect(nested.map((crumb) => crumb.path), [
        '/home/deploy',
        '/home/deploy/logs',
        '/home/deploy/logs/nginx',
      ]);
      expect(nested.first.isHome, isTrue);
      expect(nested.last.isHome, isFalse);

      // 家目录之外照旧从根逐段拆。
      expect(sftpBreadcrumbs('/var/log', home: '/home/deploy'), hasLength(3));
    });

    test('地址栏输入：~、相对路径、..、引号都规整成绝对路径', () {
      String? resolve(String input) =>
          resolveSftpPath(input, home: '/home/deploy', base: '/var/log');

      expect(resolve('~'), '/home/deploy');
      expect(resolve('~/logs'), '/home/deploy/logs');
      expect(resolve('logs'), '/var/log/logs');
      expect(resolve('/etc/nginx/'), '/etc/nginx');
      expect(resolve('/var/log/../tmp'), '/var/tmp');
      expect(resolve('../../etc'), '/etc', reason: '根目录之上的 .. 停在根');
      expect(resolve('//var///log'), '/var/log');
      expect(resolve('  "/var/log"  '), '/var/log');
      expect(resolve(''), isNull);
      expect(resolve('   '), isNull);
      // `~user` 得问服务端才知道是谁的家目录，不猜。
      expect(resolve('~someone/logs'), '~someone/logs');
      // 家目录未知时也不猜。
      expect(resolveSftpPath('~/logs', base: '/'), '~/logs');
    });

    test('Windows 原生盘符写法贴回地址栏照样前往', () {
      String? resolve(String input) =>
          resolveSftpPath(input, home: '/C:/Users/deploy', base: '/C:/Users');

      expect(resolve(r'C:\Users\admin'), '/C:/Users/admin');
      expect(resolve('C:/Users'), '/C:/Users');
      expect(resolve(r'"C:\Program Files"'), '/C:/Program Files');
      expect(resolve('C:'), '/C:/', reason: '单独盘符落在盘根');
      // SFTP 形态照旧；~ 与相对路径不受盘符归一影响。
      expect(resolve('/C:/Users'), '/C:/Users');
      expect(resolve('~'), '/C:/Users/deploy');
      expect(resolve('logs'), '/C:/Users/logs');
      // `C:` 后面没跟分隔符的不做盘符解释，按相对路径处理。
      expect(resolve('C:nope'), '/C:/Users/C:nope');
    });

    test('超长的名字中间省略，短的照旧', () {
      expect(elideSftpName('logs', 7), 'logs');
      expect(elideSftpName('2026-09-21', 7), '2026-09-21', reason: '没超就不动它');
      expect(elideSftpName('2026-09-21-release', 7), '2026-09…se');
      expect(
        elideSftpName('a-very-long-directory-name', 28),
        'a-very-long-directory-name',
      );
    });

    test('补全查询：拆成「要列的目录 + 名称前缀」', () {
      ({String directory, String prefix})? query(String input) =>
          sftpCompletionQuery(input, home: '/home/deploy', base: '/var/log');

      expect(query('/home/de')?.directory, '/home');
      expect(query('/home/de')?.prefix, 'de');
      expect(query('/home/deploy/')?.directory, '/home/deploy');
      expect(query('/home/deploy/')?.prefix, '');
      expect(query('~/lo')?.directory, '/home/deploy');
      expect(query('~/lo')?.prefix, 'lo');
      expect(query('~/')?.directory, '/home/deploy');
      expect(query('logs')?.directory, '/var/log');
      expect(query('logs')?.prefix, 'logs');
      expect(query('/var/log/../et')?.directory, '/var');
      expect(query('/var/log/../et')?.prefix, 'et');
      // 单独一个 `~` 不补全（GNOME 也是敲到斜杠才开始给候选），回车才展开。
      expect(query('~'), isNull);
      expect(query('~someone/logs'), isNull);
      expect(
        sftpCompletionQuery('~/logs', base: '/'),
        isNull,
        reason: '家目录未知时不补全',
      );
    });

    test('补全查询：Windows 原生盘符写法先归一再拆段', () {
      ({String directory, String prefix})? windows(String input) =>
          sftpCompletionQuery(
            input,
            home: '/C:/Users/deploy',
            base: '/C:/Users',
          );

      expect(windows(r'C:\Use')?.directory, '/C:/');
      expect(windows(r'C:\Use')?.prefix, 'Use');
      expect(windows(r'C:\Users\')?.directory, '/C:/Users');
      expect(windows(r'C:\Users\')?.prefix, '');
      expect(windows('C:')?.directory, '/C:/', reason: '单独盘符列盘根');
      expect(windows('C:')?.prefix, '');
      expect(windows('C:/Use')?.directory, '/C:/');
    });

    test('名称校验拦截路径分隔符与相对路径', () {
      expect(isValidEntryName('nginx.conf'), isTrue);
      expect(isValidEntryName('  logs  '), isTrue);
      expect(isValidEntryName(''), isFalse);
      expect(isValidEntryName('..'), isFalse);
      expect(isValidEntryName('a/b'), isFalse);
      expect(isValidEntryName('a\\b'), isFalse);
    });

    test('大小与耗时格式', () {
      expect(formatSftpSize(0), '0 B');
      expect(formatSftpSize(512), '512 B');
      expect(formatSftpSize(2048), '2.0 KB');
      expect(formatSftpSize(5 * 1024 * 1024), '5.0 MB');
      expect(formatSftpDuration(const Duration(seconds: 3)), '3s');
      expect(formatSftpDuration(const Duration(seconds: 90)), '1m 30s');
      expect(formatSftpDuration(const Duration(seconds: 3600)), '1h');
      expect(formatSftpDuration(const Duration(seconds: 5400)), '1h 30m');
    });
  });

  group('SftpBrowserController', () {
    test('ensureReady 打开通道并载入家目录', () async {
      final fs = FakeSftpFileSystem();
      fs.addFile(fs.home, '.bashrc');
      fs.addDirectory(fs.home, 'logs');
      final controller = SftpBrowserController(openFileSystem: () async => fs);
      addTearDown(controller.dispose);

      expect(controller.isReady, isFalse);
      await controller.ensureReady();

      expect(controller.isReady, isTrue);
      expect(controller.path, fs.home);
      expect(
        controller.entries.map((entry) => entry.name),
        ['logs'], // 隐藏文件默认不展示
      );
      // 重复调用不会再次打开通道。
      await controller.ensureReady();
      expect(fs.listCalls.length, 1);
    });

    test('Windows 远端后台探测盘符，升序给出；Unix 远端不探测', () async {
      // 根目录条目名按 Win32 OpenSSH 的两种形态给：`c:` 与带尾斜杠的 `d:/`。
      final fs = FakeSftpFileSystem(home: '/C:/Users/deploy');
      fs.addDirectory('/', 'c:');
      fs.addDirectory('/', 'd:/');
      final controller = SftpBrowserController(openFileSystem: () async => fs);
      addTearDown(controller.dispose);

      await controller.ensureReady();
      expect(controller.isWindowsRemote, isTrue);
      // 探测在首屏之后后台跑：等它落地。
      await pumpEventQueue();
      expect(controller.drives, ['C:', 'D:']);

      final unixFs = FakeSftpFileSystem(home: '/home/deploy');
      final unixController = SftpBrowserController(
        openFileSystem: () async => unixFs,
      );
      addTearDown(unixController.dispose);
      await unixController.ensureReady();
      await pumpEventQueue();
      expect(unixController.isWindowsRemote, isFalse);
      expect(unixController.drives, isEmpty);
      expect(unixFs.listCalls, ['/home/deploy'], reason: '不该多读一次根目录');
    });

    test('地址栏补全：同目录同前缀，目录带尾斜杠，点文件不进候选', () async {
      final (:controller, :fs) = await ready();
      addTearDown(controller.dispose);
      fs.addDirectory(fs.home, 'logs');
      fs.addDirectory(fs.home, 'local');
      fs.addFile(fs.home, 'nginx.conf');
      fs.addFile(fs.home, '.env');
      await controller.refresh();
      final listed = fs.listCalls.length;

      // 候选保留用户敲的写法：`~` 还是 `~`，相对路径还是相对路径。
      expect(await controller.completePath('~/lo'), ['~/local/', '~/logs/']);
      expect(await controller.completePath('~/nginx'), ['~/nginx.conf']);
      expect(await controller.completePath('~/'), [
        '~/local/',
        '~/logs/',
        '~/nginx.conf',
      ], reason: '前缀为空时列全部，但隐藏文件不列');
      expect(await controller.completePath('~/.e'), ['~/.env']);
      expect(await controller.completePath('lo'), ['local/', 'logs/']);
      expect(fs.listCalls.length, listed, reason: '补全当前目录不该再问一次服务端');
      expect(
        await controller.completePath('~'),
        isEmpty,
        reason: '单独一个 ~ 不补全（GNOME 也是敲到斜杠才给候选）',
      );

      // 别的目录要现问；问不到就当没有候选，不抛。
      expect(await controller.completePath('/etc/ng'), isEmpty);
      expect(
        await controller.completePath('/nope/x'),
        isEmpty,
        reason: '读目录失败不弹错误，静静返回空',
      );
    });

    test('浏览器默认隐藏点文件，可切换显示', () async {
      final (:controller, :fs) = await ready();
      addTearDown(controller.dispose);
      fs.addFile(fs.home, '.env');

      await controller.refresh();
      expect(
        controller.entries.map((entry) => entry.name),
        isNot(contains('.env')),
      );

      controller.toggleHidden();
      expect(controller.entries.map((entry) => entry.name), contains('.env'));
    });

    test('目录恒排在文件之前，排序可切换字段与方向', () async {
      final (:controller, :fs) = await ready();
      addTearDown(controller.dispose);
      fs.listings[fs.home] = [];
      fs.addFile(fs.home, 'b.txt', content: List.filled(30, 65));
      fs.addFile(fs.home, 'a.txt', content: List.filled(10, 65));
      fs.addDirectory(fs.home, 'z-dir');
      await controller.refresh();

      expect(controller.entries.map((entry) => entry.name), [
        'z-dir',
        'a.txt',
        'b.txt',
      ]);

      controller.toggleSort(SftpSortField.size);
      expect(controller.entries.map((entry) => entry.name), [
        'z-dir',
        'a.txt',
        'b.txt',
      ]);
      controller.toggleSort(SftpSortField.size);
      expect(controller.entries.map((entry) => entry.name), [
        'z-dir',
        'b.txt',
        'a.txt',
      ]);
    });

    test('筛选只影响展示序列，不重新读目录', () async {
      final (:controller, :fs) = await ready();
      addTearDown(controller.dispose);
      fs.addFile(fs.home, 'nginx.conf');
      fs.addFile(fs.home, 'redis.conf');
      await controller.refresh();
      final calls = fs.listCalls.length;

      controller.setQuery('redis');
      expect(controller.entries.map((entry) => entry.name), ['redis.conf']);
      expect(fs.listCalls.length, calls);
    });

    test('筛选沿用当前排序，改排序键后过滤结果跟着重排', () async {
      // 展示序列是「先排好序再过滤」的一份（见 _rebuildVisible），
      // 这条用例守住它与「先过滤再排序」等价，以及排序键变化能生效。
      final (:controller, :fs) = await ready();
      addTearDown(controller.dispose);
      for (final name in ['c.txt', 'a.txt', 'b.txt']) {
        fs.addFile(fs.home, name);
      }
      await controller.refresh();

      controller.setQuery('.txt');
      expect(controller.entries.map((entry) => entry.name), [
        'a.txt',
        'b.txt',
        'c.txt',
      ]);

      // 再点一次同一个字段 → 反转方向，过滤结果跟着反过来。
      controller.toggleSort(SftpSortField.name);
      expect(controller.entries.map((entry) => entry.name), [
        'c.txt',
        'b.txt',
        'a.txt',
      ]);

      // 换搜索词后仍按当前方向排列。
      controller.setQuery('t');
      expect(controller.entries.map((entry) => entry.name), [
        'c.txt',
        'b.txt',
        'a.txt',
      ]);
    });

    test('导航进入子目录、返回上级并清空选中', () async {
      final (:controller, :fs) = await ready();
      addTearDown(controller.dispose);
      final logs = fs.addDirectory(fs.home, 'logs');
      fs.addFile(logs.path, 'app.log');
      await controller.refresh();

      controller.select(fs.entriesOf(fs.home).first.path);
      expect(controller.selectedPaths, isNotEmpty);

      await controller.navigate(logs.path);
      expect(controller.path, logs.path);
      expect(controller.entries.map((entry) => entry.name), ['app.log']);
      expect(controller.selectedPaths, isEmpty);

      await controller.goUp();
      expect(controller.path, fs.home);
    });

    test('目录历史支持后退 / 前进，并按新导航截断前进分支', () async {
      final (:controller, :fs) = await ready();
      addTearDown(controller.dispose);
      final etc = fs.addDirectory('/', 'etc');
      final varDir = fs.addDirectory('/', 'var');
      final opt = fs.addDirectory('/', 'opt');

      expect(controller.canGoBack, isFalse);
      expect(controller.canGoForward, isFalse);

      await controller.navigate(etc.path);
      await controller.navigate(varDir.path);
      expect(controller.canGoBack, isTrue);
      expect(controller.canGoForward, isFalse);

      await controller.goBack();
      expect(controller.path, etc.path);
      expect(controller.canGoBack, isTrue);
      expect(controller.canGoForward, isTrue);

      await controller.goForward();
      expect(controller.path, varDir.path);

      await controller.goBack();
      await controller.navigate(opt.path);
      expect(controller.path, opt.path);
      expect(controller.canGoForward, isFalse, reason: '新导航会丢弃旧的前进分支');

      await controller.goBack();
      expect(controller.path, etc.path);
    });

    test('快速连点后退不会把游标退过头', () async {
      final (:controller, :fs) = await ready();
      addTearDown(controller.dispose);
      final etc = fs.addDirectory('/', 'etc');
      final varDir = fs.addDirectory('/', 'var');

      await controller.navigate(etc.path);
      await controller.navigate(varDir.path);

      // 侧键连点：第二下与第一下是同一个目标，还在载入就算重复，
      // 否则同一次载入被两笔 back 各退一格，游标与画面错位。
      final first = controller.goBack();
      final second = controller.goBack();
      await first;
      await second;

      expect(controller.path, etc.path);
      expect(controller.canGoBack, isTrue, reason: '只退了一格，家目录仍在历史里');
      await controller.goBack();
      expect(controller.path, fs.home);
    });

    test('失败导航不进入历史，不影响后退游标', () async {
      final (:controller, :fs) = await ready();
      addTearDown(controller.dispose);
      final logs = fs.addDirectory(fs.home, 'logs');

      fs.listError = const SftpException(SftpErrorKind.permission);
      await controller.navigate('/nope');
      fs.listError = null;

      expect(controller.canGoBack, isFalse, reason: '失败路径不入史');
      await controller.navigate(logs.path);
      await controller.goBack();
      expect(controller.path, fs.home);
    });

    test('读取失败时保留路径并暴露分类错误', () async {
      final (:controller, :fs) = await ready();
      addTearDown(controller.dispose);
      fs.listings['/root'] = [];

      fs.listError = const SftpException(SftpErrorKind.permission);
      await controller.navigate('/root');
      fs.listError = null;

      expect(controller.path, '/root');
      expect(controller.error?.kind, SftpErrorKind.permission);
      expect(controller.entries, isEmpty);

      await controller.refresh();
      expect(controller.error, isNull);
    });

    test('打开通道失败时暴露错误，重试可恢复', () async {
      final fs = FakeSftpFileSystem();
      var calls = 0;
      Object? failure = const SftpException(SftpErrorKind.unsupported);
      final controller = SftpBrowserController(
        openFileSystem: () async {
          calls++;
          final error = failure;
          if (error != null) throw error;
          return fs;
        },
      );
      addTearDown(controller.dispose);

      await controller.ensureReady();
      expect(controller.error?.kind, SftpErrorKind.unsupported);
      expect(controller.isReady, isFalse);
      expect(controller.isLoading, isFalse);

      // 网络恢复后再次进入面板 / 点重试即可连上。
      failure = null;
      await controller.refresh();
      expect(controller.isReady, isTrue);
      expect(controller.error, isNull);
      expect(calls, 2);
    });

    test('新建目录、重命名与递归删除', () async {
      final (:controller, :fs) = await ready();
      addTearDown(controller.dispose);
      final nested = fs.addDirectory(fs.home, 'nested');
      final inner = fs.addDirectory(nested.path, 'inner');
      fs.addFile(inner.path, 'deep.txt');
      await controller.refresh();

      await controller.createFolder('releases');
      expect(
        controller.entries.map((entry) => entry.name),
        contains('releases'),
      );

      await controller.renameEntry(
        controller.entries.firstWhere((entry) => entry.name == 'releases'),
        'builds',
      );
      expect(controller.entries.map((entry) => entry.name), contains('builds'));

      // 递归删除：先清空内层再逐级 rmdir。
      await controller.deleteEntries([
        controller.entries.firstWhere((entry) => entry.name == 'nested'),
      ]);
      expect(fs.listings.containsKey(nested.path), isFalse);
      expect(fs.listings.containsKey(inner.path), isFalse);
      expect(controller.entries.map((entry) => entry.name), ['builds']);
    });

    test('递归删除不穿透符号链接', () async {
      final (:controller, :fs) = await ready();
      addTearDown(controller.dispose);
      // /data 是真实目录，home 里的 link 指向它：删 link 不能动 /data 的内容。
      final data = fs.addDirectory(fs.home, 'data');
      fs.addFile(data.path, 'precious.txt', content: [1, 2, 3]);
      fs.addSymlink(fs.home, 'link', data.path);
      await controller.refresh();

      await controller.deleteEntries([
        controller.entries.firstWhere((entry) => entry.name == 'link'),
      ]);
      // 链接已删，目标目录与其内容原样保留。
      expect(controller.entries.map((entry) => entry.name), ['data']);
      expect(fs.listings.containsKey(data.path), isTrue);
      expect(fs.contents['${data.path}/precious.txt'], [1, 2, 3]);
    });

    test('非法名称被拒绝', () async {
      final (:controller, :fs) = await ready();
      addTearDown(controller.dispose);
      expect(() => controller.createFolder('a/b'), throwsArgumentError);
      expect(fs.listings[fs.home], isEmpty);
    });

    test('选中：追加、连选与全选', () async {
      final (:controller, :fs) = await ready();
      addTearDown(controller.dispose);
      for (final name in ['a', 'b', 'c', 'd']) {
        fs.addFile(fs.home, name);
      }
      await controller.refresh();

      controller.select(sftpJoin(fs.home, 'a'));
      controller.select(sftpJoin(fs.home, 'c'), additive: true);
      expect(controller.selectedPaths, {
        sftpJoin(fs.home, 'a'),
        sftpJoin(fs.home, 'c'),
      });

      // 未按住修饰键时再次单击 -> 只保留当前项，并以它作为连选锚点。
      controller.select(sftpJoin(fs.home, 'b'));
      controller.selectTo(sftpJoin(fs.home, 'd'));
      expect(controller.selectedPaths, {
        sftpJoin(fs.home, 'b'),
        sftpJoin(fs.home, 'c'),
        sftpJoin(fs.home, 'd'),
      });

      controller.selectAll();
      expect(controller.selectedPaths.length, 4);
      controller.clearSelection();
      expect(controller.selectedPaths, isEmpty);
    });

    test('刷新后丢弃已消失条目的选中态', () async {
      final (:controller, :fs) = await ready();
      addTearDown(controller.dispose);
      final file = fs.addFile(fs.home, 'temp.txt');
      await controller.refresh();
      controller.select(file.path);

      fs.listings[fs.home]!.removeWhere((entry) => entry.path == file.path);
      await controller.refresh();

      expect(controller.selectedPaths, isEmpty);
    });

    test('上传冲突检测覆盖隐藏文件', () async {
      final (:controller, :fs) = await ready();
      addTearDown(controller.dispose);
      fs.addFile(fs.home, '.env');
      await controller.refresh();

      final sources = [_upload('app.log'), _upload('.env')];
      expect(controller.conflictsWith(sources).map((source) => source.name), [
        '.env',
      ]);
    });
  });

  group('上传 / 下载编排', () {
    test('上传入队后写入远端并刷新列表', () async {
      final gateway = FakeLocalFileGateway()
        ..uploads = [
          _upload('app.log', content: const [1, 2, 3, 4]),
        ];
      final (:controller, :fs) = await ready(gateway: gateway);
      addTearDown(controller.dispose);

      final sources = await controller.pickUploads('上传');
      expect(sources, hasLength(1));
      controller.startUpload(sources);
      await pumpEventQueue();

      expect(fs.contents[sftpJoin(fs.home, 'app.log')]!.length, 4);
      final transfer = controller.transfers.transfers.single;
      expect(transfer.state, SftpTransferState.done);
      expect(transfer.progress, 1);
      // 上传完成后目录已刷新，新文件出现在列表里。
      expect(
        controller.entries.map((entry) => entry.name),
        contains('app.log'),
      );
    });

    test('上传失败清理半截远端文件并标记失败', () async {
      final gateway = FakeLocalFileGateway()..uploads = [_upload('big.bin')];
      final (:controller, :fs) = await ready(gateway: gateway);
      addTearDown(controller.dispose);
      fs.writeError = const SftpException(SftpErrorKind.network);

      controller.startUpload(gateway.uploads);
      await pumpEventQueue();

      // 半截内容只落在临时文件上，清理它，目标路径始终没被碰过。
      expect(fs.contents.containsKey(sftpJoin(fs.home, 'big.bin')), isFalse);
      expect(
        fs.listings[fs.home]!.any((entry) => entry.name == 'big.bin'),
        isFalse,
      );
      final transfer = controller.transfers.transfers.single;
      expect(transfer.state, SftpTransferState.failed);
      expect(transfer.errorKind, SftpErrorKind.network);
    });

    test('上传走临时文件再改名，失败不毁掉远端原有的同名文件', () async {
      final gateway = FakeLocalFileGateway()..uploads = [_upload('app.log')];
      final (:controller, :fs) = await ready(gateway: gateway);
      addTearDown(controller.dispose);
      // 远端已有一份重要文件，本次上传要在中途失败。
      fs.addFile(fs.home, 'app.log', content: const [9, 9, 9]);
      fs.writeError = const SftpException(SftpErrorKind.network);

      controller.startUpload(gateway.uploads);
      await pumpEventQueue();

      expect(
        controller.transfers.transfers.single.state,
        SftpTransferState.failed,
      );
      expect(fs.contents[sftpJoin(fs.home, 'app.log')], [
        9,
        9,
        9,
      ], reason: '覆盖写失败时远端原有的文件必须原封不动');
    });

    test('上传成功后才把临时文件改名到目标', () async {
      final gateway = FakeLocalFileGateway()
        ..uploads = [
          _upload('app.log', content: const [1, 2, 3, 4]),
        ];
      final (:controller, :fs) = await ready(gateway: gateway);
      addTearDown(controller.dispose);
      fs.addFile(fs.home, 'app.log', content: const [9, 9, 9]);

      controller.startUpload(gateway.uploads);
      await pumpEventQueue();

      expect(fs.contents[sftpJoin(fs.home, 'app.log')], [
        1,
        2,
        3,
        4,
      ], reason: '成功时新内容顶替旧内容');
      // 临时文件不留在远端目录里。
      expect(
        fs.listings[fs.home]!.any(
          (entry) => entry.name.contains('.noshell-part'),
        ),
        isFalse,
      );
    });

    test('传输中途销毁队列不炸：不再对已 dispose 的任务发通知', () async {
      final gateway = FakeLocalFileGateway()
        ..downloadTarget = const LocalTarget(
          path: '/tmp/raw.bin',
          name: 'raw.bin',
        );
      final fs = GatedReadFileSystem()
        ..addFile(
          '/home/deploy',
          'raw.bin',
          content: List.generate(64, (i) => i),
        );
      final controller = SftpBrowserController(
        openFileSystem: () async => fs,
        localFiles: gateway,
      );
      await controller.ensureReady();

      controller.transfers.enqueueDownload(
        entry: fs.entryNamed('raw.bin'),
        target: gateway.downloadTarget!,
      );
      await fs.readStarted.future; // 传输进行中

      // 用户此时断开连接 / 删掉主机：控制器被销毁，队列跟着销毁。
      controller.dispose();
      fs.releaseRead();
      await pumpEventQueue();

      // 修复前这里会抛 FlutterError: A SftpTransfer was used after being disposed
      expect(fs.disposed, isTrue);
    });

    test('下载写盘并支持取消', () async {
      final gateway = FakeLocalFileGateway()
        ..downloadTarget = const LocalTarget(
          path: '/tmp/app.log',
          name: 'app.log',
        );
      final (:controller, :fs) = await ready(gateway: gateway);
      addTearDown(controller.dispose);
      final file = fs.addFile(
        fs.home,
        'app.log',
        content: List.generate(16, (index) => index),
      );

      final outcome = await controller.downloadEntries([file], '保存');
      expect(outcome, SftpDownloadOutcome.enqueued);
      await pumpEventQueue();

      expect(gateway.bytesOf('/tmp/app.log').length, 16);
      expect(
        controller.transfers.transfers.single.state,
        SftpTransferState.done,
      );
      // 下载落点收到 0600：远端内容里可能是私钥这类只该自己读的东西。
      expect(gateway.ownerOnlyWrites, [gateway.temporaryPath('/tmp/app.log')]);
    });

    test('多个条目走目录选择，取消则不产生传输', () async {
      final gateway = FakeLocalFileGateway()..downloadDirectory = null;
      final (:controller, :fs) = await ready(gateway: gateway);
      addTearDown(controller.dispose);
      final a = fs.addFile(fs.home, 'a.txt');
      final b = fs.addFile(fs.home, 'b.txt');

      final canceled = await controller.downloadEntries([a, b], '保存');
      expect(canceled, SftpDownloadOutcome.canceled);
      expect(controller.transfers.transfers, isEmpty);
    });

    test('选不出落点时给出 unavailable', () async {
      final gateway = FakeLocalFileGateway()
        ..downloadDirectory = const <LocalTarget>[];
      final (:controller, :fs) = await ready(gateway: gateway);
      addTearDown(controller.dispose);
      final a = fs.addFile(fs.home, 'a.txt');
      final b = fs.addFile(fs.home, 'b.txt');

      expect(
        await controller.downloadEntries([a, b], '保存'),
        SftpDownloadOutcome.unavailable,
      );
    });

    test('取消下载只清临时文件，落点上原有的文件不动', () async {
      final gateway = FakeLocalFileGateway()
        ..downloadTarget = const LocalTarget(
          path: '/tmp/raw.bin',
          name: 'raw.bin',
        );
      // 落点已有一份旧文件：取消下载绝不能把它毁掉。
      gateway.written['/tmp/raw.bin'] = const [1, 2, 3];
      final fs = GatedReadFileSystem()
        ..addFile(
          '/home/deploy',
          'raw.bin',
          content: List.generate(64, (i) => i),
        );
      final controller = SftpBrowserController(
        openFileSystem: () async => fs,
        localFiles: gateway,
      );
      addTearDown(controller.dispose);
      await controller.ensureReady();

      final transfer = controller.transfers.enqueueDownload(
        entry: fs.entryNamed('raw.bin'),
        target: gateway.downloadTarget!,
      );
      await fs.readStarted.future; // 已经读到中途
      transfer.cancel();
      fs.releaseRead();
      await pumpEventQueue();

      expect(transfer.state, SftpTransferState.canceled);
      expect(gateway.discarded, [
        '/tmp/raw.bin.noshell-part',
      ], reason: '半成品是临时文件');
      expect(gateway.written['/tmp/raw.bin'], [
        1,
        2,
        3,
      ], reason: '落点上原有的文件必须原封不动');
    });

    test('清除已完成的任务', () async {
      final gateway = FakeLocalFileGateway()
        ..downloadTarget = const LocalTarget(path: '/tmp/a.txt', name: 'a.txt');
      final (:controller, :fs) = await ready(gateway: gateway);
      addTearDown(controller.dispose);
      final file = fs.addFile(fs.home, 'a.txt');

      await controller.downloadEntries([file], '保存');
      await pumpEventQueue();
      expect(controller.transfers.transfers, hasLength(1));

      controller.transfers.clearFinished();
      expect(controller.transfers.transfers, isEmpty);
    });

    test('下载中途失败：报错、清掉半成品，落点上原有的文件不动', () async {
      final gateway = FakeLocalFileGateway()
        ..downloadTarget = const LocalTarget(
          path: '/tmp/raw.bin',
          name: 'raw.bin',
        );
      // 落点上已有一份旧文件。
      gateway.written['/tmp/raw.bin'] = const [9, 9];
      final (:controller, :fs) = await ready(gateway: gateway);
      addTearDown(controller.dispose);
      final file = fs.addFile(
        fs.home,
        'raw.bin',
        content: List.generate(64, (i) => i),
      );
      // 吐出一块之后连接断掉。
      fs.readError = const SftpException(SftpErrorKind.network);
      fs.readErrorAfterChunks = 1;

      controller.transfers.enqueueDownload(
        entry: file,
        target: gateway.downloadTarget!,
      );
      await pumpEventQueue();

      final transfer = controller.transfers.transfers.single;
      expect(transfer.state, SftpTransferState.failed);
      expect(transfer.errorKind, SftpErrorKind.network);
      expect(gateway.discarded, ['/tmp/raw.bin.noshell-part']);
      expect(gateway.written['/tmp/raw.bin'], [
        9,
        9,
      ], reason: '下载失败不该动落点上原有的文件');
    });

    test('已有结构性操作在执行时，后续请求明确报错而不是假装成功', () async {
      final fs = GatedListFileSystem();
      final controller = SftpBrowserController(
        openFileSystem: () async => fs,
        localFiles: FakeLocalFileGateway(),
      );
      addTearDown(controller.dispose);
      // 首次载入先放行，避免它把后面的闸门吃掉。
      final ready = controller.ensureReady();
      fs.releaseList();
      fs.arm();
      await ready;

      // 钉住这次操作收尾时的刷新，让 isMutating 保持为 true。
      final mutating = controller.createFolder('new-dir');
      await fs.listStarted.future;
      expect(controller.isMutating, isTrue);

      // 静默 return 会让调用方以为改成功了，其实什么都没做。
      await expectLater(
        controller.createFolder('another'),
        throwsA(
          isA<SftpException>().having(
            (e) => e.kind,
            'kind',
            SftpErrorKind.busy,
          ),
        ),
      );

      fs.releaseList();
      await mutating;
    });

    test('落点数量少于目标时整体不下载，不半途下标越界', () async {
      final gateway = FakeLocalFileGateway()
        // 选择器只回了一个落点，但要下两个文件。
        ..downloadDirectory = const [
          LocalTarget(path: '/tmp/a.txt', name: 'a.txt'),
        ];
      final (:controller, :fs) = await ready(gateway: gateway);
      addTearDown(controller.dispose);
      final a = fs.addFile(fs.home, 'a.txt', content: const [1]);
      final b = fs.addFile(fs.home, 'b.txt', content: const [2]);

      expect(
        await controller.downloadEntries([a, b], '保存'),
        SftpDownloadOutcome.unavailable,
      );
      // 一个都不该入队：要么整批下载，要么都不下。
      expect(controller.transfers.transfers, isEmpty);
    });

    test('落点已存在同名文件：确认通过才下载，拒绝则整批取消', () async {
      final gateway = FakeLocalFileGateway()
        ..downloadDirectory = const [
          LocalTarget(path: '/tmp/a.txt', name: 'a.txt'),
          LocalTarget(path: '/tmp/b.txt', name: 'b.txt'),
        ]
        ..existingLocalFiles.addAll(['/tmp/a.txt']);
      final (:controller, :fs) = await ready(gateway: gateway);
      addTearDown(controller.dispose);
      final a = fs.addFile(fs.home, 'a.txt', content: const [1]);
      final b = fs.addFile(fs.home, 'b.txt', content: const [2]);

      // 回调为 null（不确认）时不得覆盖。
      expect(
        await controller.downloadEntries([a, b], '保存'),
        SftpDownloadOutcome.canceled,
      );
      expect(controller.transfers.transfers, isEmpty);

      // 确认覆盖后照常入队。
      expect(
        await controller.downloadEntries(
          [a, b],
          '保存',
          confirmOverwrite: (conflicts) async =>
              conflicts.length == 1 && conflicts.single == 'a.txt',
        ),
        SftpDownloadOutcome.enqueued,
      );
      await pumpEventQueue();
      expect(controller.transfers.transfers, hasLength(2));
    });

    test('传输失败同样触发 onTransferFinished（失败提示不再无声）', () async {
      final gateway = FakeLocalFileGateway()..uploads = [_upload('big.bin')];
      final (:controller, :fs) = await ready(gateway: gateway);
      addTearDown(controller.dispose);
      fs.writeError = const SftpException(SftpErrorKind.network);
      final finished = <SftpTransfer>[];
      controller.transfers.onTransferFinished = finished.add;

      controller.startUpload(await controller.pickUploads('上传'));
      await pumpEventQueue();

      expect(finished, hasLength(1));
      expect(finished.single.state, SftpTransferState.failed);
    });

    test('源读尽后的收尾窗口取消：效果如实呈现', () async {
      final gateway = FakeLocalFileGateway()
        ..uploads = [
          _upload('conf.bin', content: const [1]),
        ];
      final (:controller, :fs) = await ready(gateway: gateway);
      addTearDown(controller.dispose);
      // 目标已有旧内容。
      final target = sftpJoin(fs.home, 'conf.bin');
      fs.contents[target] = const [9];
      fs.renameGate = Completer<void>();

      controller.startUpload(await controller.pickUploads('上传'));
      await pumpEventQueue(); // write 已完成，卡在 rename 上
      controller.transfers.transfers.single.cancel();
      fs.renameGate!.complete();
      await pumpEventQueue();

      // rename 在取消之后仍执行了（它是一次原子的远端请求，无法中途
      // 撤回）：目标被替换，状态必须报 done——「已取消 + 文件被覆盖」
      // 才是骗人。
      expect(
        controller.transfers.transfers.single.state,
        SftpTransferState.done,
      );
      expect(fs.contents[target], const [1]);
    });

    test('rename 前收到取消：目标原样保留，状态报取消', () async {
      final gateway = FakeLocalFileGateway()
        ..uploads = [
          _upload('conf.bin', content: const [1]),
        ];
      final (:controller, :fs) = await ready(gateway: gateway);
      addTearDown(controller.dispose);
      final target = sftpJoin(fs.home, 'conf.bin');
      fs.contents[target] = const [9];
      // 写入本身卡住：取消会让 isAborted 命中（真实适配器靠它捅破
      // done 的等待；假实现里 write 在流上同步收尾，这里用流不出块
      // 之前的取消覆盖同一条路径——_guarded 抛 _TransferCanceled）。
      final slow = Completer<void>();
      gateway.uploads = [
        LocalUpload(
          name: 'conf.bin',
          length: 1,
          openRead: () async* {
            await slow.future;
            yield const [1];
          },
        ),
      ];
      controller.startUpload(gateway.uploads);
      await pumpEventQueue();
      controller.transfers.transfers.single.cancel();
      slow.complete();
      await pumpEventQueue();

      expect(
        controller.transfers.transfers.single.state,
        SftpTransferState.canceled,
      );
      expect(fs.contents[target], const [9]);
    });

    test('队列销毁后入队：任务标记失败而不是断言崩溃', () async {
      final (:controller, :fs) = await ready();
      addTearDown(controller.dispose);
      final queue = SftpTransferQueue(
        fileSystem: () => fs,
        localFiles: FakeLocalFileGateway(),
      );
      queue.dispose();

      final transfer = queue.enqueueUpload(
        source: _upload('x.bin'),
        remoteDir: fs.home,
      );
      expect(transfer.state, SftpTransferState.failed);
      expect(queue.transfers, isEmpty);
    });
  });
}

LocalUpload _upload(String name, {List<int>? content}) {
  final bytes = content ?? List.filled(8, 7);
  return LocalUpload(
    name: name,
    length: bytes.length,
    openRead: () => Stream.value(bytes),
  );
}
