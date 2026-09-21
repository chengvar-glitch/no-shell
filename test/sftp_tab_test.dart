import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/l10n/generated/app_localizations.dart';
import 'package:no_shell/main.dart';
import 'package:no_shell/store.dart';
import 'package:no_shell/ssh/local_files.dart';
import 'package:no_shell/ssh/sftp.dart';
import 'package:no_shell/ssh/ssh_credentials.dart';
import 'package:no_shell/ssh/terminal_session.dart';
import 'package:no_shell/theme.dart';
import 'package:no_shell/widgets/sftp_browser.dart';

import 'support/demo_servers.dart';
import 'support/sftp_fakes.dart';

/// 用固定尺寸的宿主承载 SFTP 面板：
/// 900 走桌面（宽表格 + 完整工具条），390 走紧凑（移动）布局。
Widget host(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: AppTheme.light(),
  home: Scaffold(body: child),
);

/// 建一个已连接会话并挂上面板；返回会话便于断言通道只开一次。
Future<TerminalSession> pumpPanel(
  WidgetTester tester, {
  required FakeSftpFileSystem fileSystem,
  FakeLocalFileGateway? gateway,
  double width = 900,
  double height = 640,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = TerminalSession(
    server: testServer(),
    credentials: const SshCredentials(password: 'pw'),
    transport: FakeSftpTransport(fileSystem: fileSystem),
    localFiles: gateway ?? FakeLocalFileGateway(),
  );
  addTearDown(session.dispose);
  await session.start();
  await tester.pumpWidget(
    host(SftpTab(session: session, idleHint: '会话未建立 —— 先连接')),
  );
  await tester.pumpAndSettle();
  return session;
}

LocalUpload upload(String name, List<int> bytes) => LocalUpload(
  name: name,
  length: bytes.length,
  openRead: () => Stream.value(bytes),
);

void main() {
  group('SftpTab 未连接态', () {
    testWidgets('无会话时展示引导文案，不打开 SFTP 通道', (tester) async {
      tester.view.physicalSize = const Size(900, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(const SftpTab(idleHint: '会话未建立 —— 先连接')));
      await tester.pump();

      expect(find.text('SFTP'), findsOneWidget);
      expect(find.text('会话未建立 —— 先连接'), findsOneWidget);
    });

    testWidgets('会话结束后展示重连入口', (tester) async {
      tester.view.physicalSize = const Size(900, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var retried = 0;

      await tester.pumpWidget(
        host(SftpTab(idleHint: '会话未建立', onRetry: () => retried++)),
      );
      await tester.pump();

      await tester.tap(find.text('重连'));
      await tester.pump();
      expect(retried, 1);
    });
  });

  group('SftpTab 可见性', () {
    testWidgets('Tab 不可见时不开 SFTP 通道，切到可见才开', (tester) async {
      tester.view.physicalSize = const Size(900, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final fs = FakeSftpFileSystem();
      fs.addFile(fs.home, 'nginx.conf');
      final transport = FakeSftpTransport(fileSystem: fs);
      final session = TerminalSession(
        server: testServer(),
        credentials: const SshCredentials(password: 'pw'),
        transport: transport,
      );
      addTearDown(session.dispose);
      await session.start();

      // 桌面端三个 Tab 常驻在树里保活，不可见的那个不该顺手建一条 SFTP 连接。
      Widget tab({required bool visible}) => host(
        Visibility(
          visible: visible,
          maintainSize: true,
          maintainState: true,
          maintainAnimation: true,
          child: SftpTab(session: session, idleHint: '会话未建立'),
        ),
      );

      await tester.pumpWidget(tab(visible: false));
      await tester.pump();
      expect(transport.openSftpCalls, 0);

      await tester.pumpWidget(tab(visible: true));
      await tester.pumpAndSettle();
      expect(transport.openSftpCalls, 1);
      expect(find.text('nginx.conf'), findsOneWidget);
    });
  });

  group('SftpTab 浏览', () {
    testWidgets('列出家目录并可用隐藏文件开关扩大范围', (tester) async {
      final fs = FakeSftpFileSystem();
      fs.addDirectory(fs.home, 'logs');
      fs.addFile(fs.home, 'nginx.conf');
      fs.addFile(fs.home, '.env');
      await pumpPanel(tester, fileSystem: fs);

      expect(find.text('logs'), findsOneWidget);
      expect(find.text('nginx.conf'), findsOneWidget);
      expect(find.text('.env'), findsNothing);
      expect(find.text('2 项'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.visibility_off_rounded));
      await tester.pump();
      expect(find.text('.env'), findsOneWidget);
      expect(find.text('3 项'), findsOneWidget);
    });

    testWidgets('单击选中后出现操作条，删除需确认', (tester) async {
      final fs = FakeSftpFileSystem();
      fs.addFile(fs.home, 'nginx.conf');
      await pumpPanel(tester, fileSystem: fs);

      // 桌面端的单击是鼠标：按下那一刻就选中，不等手势竞技场裁决。
      await tester.tap(find.text('nginx.conf'), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(find.text('已选 1 项'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除「nginx.conf」？'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(find.text('nginx.conf'), findsNothing);
      expect(fs.contents, isEmpty);
    });

    testWidgets('双击目录进入，面包屑可回上级', (tester) async {
      final fs = FakeSftpFileSystem();
      final logs = fs.addDirectory(fs.home, 'logs');
      fs.addFile(logs.path, 'app.log');
      await pumpPanel(tester, fileSystem: fs);

      final row = find.text('logs');
      await tester.tap(row);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.text('app.log'), findsOneWidget);
      expect(find.text('logs'), findsOneWidget); // 面包屑最后一段

      await tester.tap(find.text('deploy'));
      await tester.pumpAndSettle();
      expect(find.text('app.log'), findsNothing);
      expect(find.text('logs'), findsOneWidget); // 回到上级，目录重新出现在列表
    });

    testWidgets('紧凑布局下单击目录直接进入', (tester) async {
      final fs = FakeSftpFileSystem();
      final logs = fs.addDirectory(fs.home, 'logs');
      fs.addFile(logs.path, 'app.log');
      await pumpPanel(tester, width: 390, height: 700, fileSystem: fs);

      await tester.tap(find.text('logs'));
      await tester.pumpAndSettle();

      expect(find.text('app.log'), findsOneWidget);
    });

    testWidgets('地址栏浏览态与编辑态共用同一个外框与前置标记', (tester) async {
      final fs = FakeSftpFileSystem();
      fs.addFile(fs.home, 'nginx.conf');
      await pumpPanel(tester, fileSystem: fs);

      // 前置文件夹标记是两种状态共用的「这是路径」提示。
      final mark = find.byIcon(Icons.folder_open_rounded);
      Rect barRect() => tester.getRect(
        find.ancestor(of: mark, matching: find.byType(Container)).first,
      );

      expect(mark, findsOneWidget, reason: '浏览态也要有前置标记');
      final browse = barRect();
      // 两种状态的内容都从同一个 x 起：1px 描边 + 9 间距 + 15 图标 + 7 间距。
      final contentLeft = browse.left + 32;
      expect(
        tester.getTopLeft(find.byType(SingleChildScrollView)).dx,
        contentLeft,
      );

      await tester.tap(find.text('deploy'));
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget, reason: '进入编辑态');
      expect(mark, findsOneWidget, reason: '编辑态保留同一个前置标记');
      // 两种状态只换内容，不换外框：尺寸与位置必须一致。
      expect(barRect(), browse);
      expect(
        tester.getTopLeft(find.byType(TextField)).dx,
        contentLeft,
        reason: '输入框与面包屑内容框左边界对齐',
      );
      // 输入框左右内边距与面包屑文字（各 5px）一致，路径文字原地不动。
      final decoration = tester
          .widget<TextField>(find.byType(TextField))
          .decoration!;
      expect((decoration.contentPadding! as EdgeInsets).horizontal, 10);
    });

    testWidgets('载入中转圈恒定占位：地址栏宽度不随忙闲跳动', (tester) async {
      final fs = FakeSftpFileSystem();
      fs.addFile(fs.home, 'nginx.conf');
      await pumpPanel(tester, fileSystem: fs);

      // 地址栏外框：两种状态下都带同一个前置文件夹标记。
      final bar = find
          .ancestor(
            of: find.byIcon(Icons.folder_open_rounded),
            matching: find.byType(Container),
          )
          .first;
      final idle = tester.getRect(bar);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // 把刷新钉在半路：这一帧面板处于「载入中」。
      final gate = Completer<void>();
      fs.listGate = gate;
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pump();

      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
        reason: '载入中应该有转圈',
      );
      expect(tester.getRect(bar), idle, reason: '转圈出现不该把地址栏挤窄（之前就是这里抖）');

      fs.listGate = null;
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.getRect(bar), idle, reason: '载入结束也不该回弹');
    });

    testWidgets('点路径栏直接进入可编辑状态，回车按输入前往', (tester) async {
      final fs = FakeSftpFileSystem();
      final logs = fs.addDirectory(fs.home, 'logs');
      fs.addFile(logs.path, 'app.log');
      fs.addFile(fs.home, 'nginx.conf');
      await pumpPanel(tester, fileSystem: fs);

      // 当前层那一段没有跳转语义，点它就是点路径栏：进编辑态、整条路径选中。
      await tester.tap(find.text('deploy'));
      await tester.pump();

      final editor = find.byType(TextField);
      expect(editor, findsOneWidget);
      final field = tester.widget<TextField>(editor);
      expect(field.controller!.text, fs.home);
      expect(
        field.controller!.selection,
        TextSelection(baseOffset: 0, extentOffset: fs.home.length),
      );

      await tester.enterText(editor, logs.path);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('app.log'), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: '前往后回到面包屑');
    });

    testWidgets('编辑态按 Esc 放弃输入，停在原目录', (tester) async {
      final fs = FakeSftpFileSystem();
      fs.addFile(fs.home, 'nginx.conf');
      await pumpPanel(tester, fileSystem: fs);

      await tester.tap(find.text('deploy'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '/tmp');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.text('nginx.conf'), findsOneWidget);
      expect(fs.listCalls, ['/home/deploy'], reason: 'Esc 不该触发跳转');
    });

    testWidgets('读取失败展示分类错误并可重试', (tester) async {
      final fs = FakeSftpFileSystem();
      fs.addFile(fs.home, 'nginx.conf');
      await pumpPanel(tester, fileSystem: fs);

      fs.listError = const SftpException(SftpErrorKind.permission);
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pumpAndSettle();
      expect(find.text('没有权限访问该位置'), findsOneWidget);

      fs.listError = null;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('nginx.conf'), findsOneWidget);
    });

    testWidgets('筛选在当前目录内即时生效', (tester) async {
      final fs = FakeSftpFileSystem();
      fs.addFile(fs.home, 'nginx.conf');
      fs.addFile(fs.home, 'redis.conf');
      await pumpPanel(tester, fileSystem: fs);

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, 'redis');
      await tester.pump();

      expect(find.text('redis.conf'), findsOneWidget);
      expect(find.text('nginx.conf'), findsNothing);
      expect(find.text('没有匹配的条目'), findsNothing);
    });
  });

  group('SftpTab 触屏交互（紧凑布局）', () {
    /// 造一份够长的目录：列表真的能滚，滑动手势才成立。
    FakeSftpFileSystem scrollableFileSystem() {
      final fs = FakeSftpFileSystem();
      fs.addDirectory(fs.home, 'logs');
      for (var i = 0; i < 20; i++) {
        fs.addFile(fs.home, 'file-$i.log');
      }
      return fs;
    }

    testWidgets('在目录行上滑动只滚列表，不进入目录', (tester) async {
      final fs = scrollableFileSystem();
      await pumpPanel(tester, width: 390, height: 700, fileSystem: fs);
      final before = List.of(fs.listCalls);

      // 从目录那一行起手往上滑：手指落点就在「logs」上。
      // 手指抬起时那一行已经滚出视口，所以判据是「有没有发列目录请求」
      // 与列表内容，而不是那一行还在不在画面上。
      await tester.drag(find.text('logs'), const Offset(0, -180));
      await tester.pumpAndSettle();

      expect(fs.listCalls, before, reason: '滑动期间一次列目录请求都不该发');
      expect(find.text('21 项'), findsOneWidget, reason: '列表仍是家目录');
    });

    testWidgets('在文件行上滑动不会改变选中', (tester) async {
      final fs = scrollableFileSystem();
      await pumpPanel(tester, width: 390, height: 700, fileSystem: fs);

      await tester.drag(find.text('file-0.log'), const Offset(0, -180));
      await tester.pumpAndSettle();

      expect(find.text('已选 1 项'), findsNothing, reason: '滑动不是选中');
      expect(find.text('21 项'), findsOneWidget, reason: '列表内容不变');
    });

    testWidgets('滑动之后照旧点得中：目录能进、文件能选', (tester) async {
      final fs = scrollableFileSystem();
      final app = fs.addDirectory(fs.home, 'app');
      fs.addFile(app.path, 'app.log');
      await pumpPanel(tester, width: 390, height: 700, fileSystem: fs);

      // 滑上去再滑回来：滚动手势不会把点击一直扣在竞技场里。
      await tester.drag(find.text('file-0.log'), const Offset(0, -180));
      await tester.pumpAndSettle();
      await tester.drag(find.text('file-19.log'), const Offset(0, 180));
      await tester.pumpAndSettle();

      await tester.tap(find.text('app'));
      await tester.pumpAndSettle();
      expect(find.text('app.log'), findsOneWidget);

      await tester.tap(find.text('app.log'));
      await tester.pump();
      expect(find.text('已选 1 项'), findsOneWidget);
    });

    testWidgets('单击文件切换多选，再点一下取消', (tester) async {
      final fs = FakeSftpFileSystem();
      fs.addFile(fs.home, 'nginx.conf');
      await pumpPanel(tester, width: 390, height: 700, fileSystem: fs);

      await tester.tap(find.text('nginx.conf'));
      await tester.pump();
      expect(find.text('已选 1 项'), findsOneWidget);

      await tester.tap(find.text('nginx.conf'));
      await tester.pump();
      expect(find.text('已选 1 项'), findsNothing);
    });

    testWidgets('长按弹出行菜单，不会顺手进入目录', (tester) async {
      final fs = scrollableFileSystem();
      final zulu = fs.addDirectory(fs.home, 'zulu');
      fs.addFile(zulu.path, 'app.log');
      await pumpPanel(tester, width: 390, height: 700, fileSystem: fs);
      final before = List.of(fs.listCalls);

      await tester.longPress(find.text('zulu'));
      await tester.pumpAndSettle();

      // 只断言菜单里的那几项：底下的选中操作条也有一个「删除」。
      final menu = find.byType(PopupMenuItem<String>);
      expect(
        find.descendant(of: menu, matching: find.text('重命名')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: menu, matching: find.text('复制路径')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: menu, matching: find.text('删除')),
        findsOneWidget,
      );
      expect(fs.listCalls, before, reason: '长按只开菜单，不进入目录');
    });

    testWidgets('连点目录只发一次列目录请求', (tester) async {
      final fs = FakeSftpFileSystem();
      final logs = fs.addDirectory(fs.home, 'logs');
      fs.addFile(logs.path, 'app.log');
      await pumpPanel(tester, width: 390, height: 700, fileSystem: fs);

      // 把这次载入钉在半路：第二下点击落在「请求还没回来」的窗口里。
      final gate = Completer<void>();
      fs.listGate = gate;
      final row = find.text('logs');
      await tester.tap(row);
      await tester.pump();
      await tester.tap(row);
      await tester.pump();

      fs.listGate = null;
      gate.complete();
      await tester.pumpAndSettle();

      expect(
        fs.listCalls.where((path) => path == logs.path),
        hasLength(1),
        reason: '慢链路上重复点按不该再发一条请求',
      );
      expect(find.text('app.log'), findsOneWidget);
    });

    testWidgets('宽屏上的手指拖动只滚列表，鼠标单击仍是按下即选中', (tester) async {
      final fs = FakeSftpFileSystem();
      for (var i = 0; i < 20; i++) {
        fs.addFile(fs.home, 'file-$i.log');
      }
      // 宽屏（平板 / 折叠屏 / 分屏窗口）走的是桌面那套行，指针类型才是判据。
      await pumpPanel(tester, width: 900, height: 640, fileSystem: fs);

      await tester.drag(find.text('file-0.log'), const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 项'), findsNothing, reason: '手指拖动不是选中');

      // 滑过之后仍在视口里的那一行（名字按字典序排，file-15 在 file-1 之后）。
      await tester.tap(find.text('file-15.log'), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(find.text('已选 1 项'), findsOneWidget, reason: '鼠标按下即选中');

      // 桌面端挂着双击手势，单击的「落定」要等 kDoubleTapTimeout 过去。
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('目录行的「点进去」箭头只出现在触屏紧凑布局', (tester) async {
      final fs = FakeSftpFileSystem();
      fs.addDirectory(fs.home, 'logs');
      fs.addFile(fs.home, 'nginx.conf');

      await pumpPanel(tester, width: 900, height: 640, fileSystem: fs);
      expect(
        find.byIcon(Icons.chevron_right_rounded),
        findsNothing,
        reason: '桌面端靠悬停给提示，列表里不加箭头',
      );

      await pumpPanel(tester, width: 390, height: 700, fileSystem: fs);
      expect(
        find.byIcon(Icons.chevron_right_rounded),
        findsOneWidget,
        reason: '触屏只有目录行带箭头，文件行没有',
      );
    });
  });

  group('SftpTab 传输', () {
    testWidgets('上传写入远端、刷新列表并提示完成', (tester) async {
      final fs = FakeSftpFileSystem();
      final gateway = FakeLocalFileGateway()
        ..uploads = [
          upload('app.log', [1, 2, 3, 4]),
        ];
      await pumpPanel(tester, fileSystem: fs, gateway: gateway);

      await tester.tap(find.widgetWithText(FilledButton, '上传'));
      await tester.pumpAndSettle();

      expect(fs.contents[sftpJoin(fs.home, 'app.log')], isNotNull);
      // 列表行 + 传输行各一个。
      expect(find.text('app.log'), findsNWidgets(2));
      expect(find.text('传输'), findsOneWidget);
      expect(find.text('已完成'), findsOneWidget);
      expect(find.text('已上传 app.log'), findsOneWidget);
    });

    testWidgets('同名上传先确认覆盖', (tester) async {
      final fs = FakeSftpFileSystem();
      fs.addFile(fs.home, 'app.log');
      final gateway = FakeLocalFileGateway()
        ..uploads = [
          upload('app.log', [9, 9, 9, 9]),
        ];
      await pumpPanel(tester, fileSystem: fs, gateway: gateway);

      await tester.tap(find.widgetWithText(FilledButton, '上传'));
      await tester.pumpAndSettle();
      expect(find.text('文件已存在'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '覆盖'));
      await tester.pumpAndSettle();
      expect(fs.contents[sftpJoin(fs.home, 'app.log')], const [9, 9, 9, 9]);
    });

    testWidgets('取消覆盖则不产生传输', (tester) async {
      final fs = FakeSftpFileSystem();
      fs.addFile(fs.home, 'app.log');
      final gateway = FakeLocalFileGateway()
        ..uploads = [
          upload('app.log', [9, 9, 9, 9]),
        ];
      await pumpPanel(tester, fileSystem: fs, gateway: gateway);

      await tester.tap(find.widgetWithText(FilledButton, '上传'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(find.text('传输'), findsNothing);
      expect(fs.contents[sftpJoin(fs.home, 'app.log')], const [65, 66, 67, 68]);
    });

    testWidgets('选择器不可用时给出提示', (tester) async {
      final fs = FakeSftpFileSystem();
      final gateway = FakeLocalFileGateway()
        ..pickError = StateError('no picker');
      await pumpPanel(tester, fileSystem: fs, gateway: gateway);

      await tester.tap(find.widgetWithText(FilledButton, '上传'));
      await tester.pumpAndSettle();
      expect(find.text('无法打开文件选择器'), findsOneWidget);
    });

    testWidgets('下载入队后写盘并展示传输行', (tester) async {
      final fs = FakeSftpFileSystem();
      fs.addFile(fs.home, 'nginx.conf', content: List.filled(8, 5));
      final gateway = FakeLocalFileGateway()
        ..downloadTarget = const LocalTarget(
          path: '/tmp/nginx.conf',
          name: 'nginx.conf',
        );
      await pumpPanel(tester, fileSystem: fs, gateway: gateway);

      await tester.tap(find.text('nginx.conf'), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, '下载'));
      await tester.pumpAndSettle();

      expect(gateway.bytesOf('/tmp/nginx.conf'), hasLength(8));
      expect(find.text('传输'), findsOneWidget);
      expect(find.text('已保存 nginx.conf'), findsOneWidget);
    });
  });

  group('详情页 Tab 接入', () {
    testWidgets('桌面端详情面板新增 SFTP Tab 并展示未连接引导', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('zh')];
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        NoShellApp(store: ServerStore(seed: demoServers)),
      );
      await tester.pump();
      await tester.tap(find.text('web-prod-01'));
      await tester.pumpAndSettle();

      // 三个 Tab 常驻保活，未选中的 Tab 内容也留在树里，
      // 因此断言与点击都限定在标签栏内。
      final tabBar = find.byType(TabBar);
      for (final label in ['概览', '终端', 'SFTP']) {
        expect(
          find.descendant(of: tabBar, matching: find.text(label)),
          findsOneWidget,
        );
      }

      await tester.tap(
        find.descendant(of: tabBar, matching: find.text('SFTP')),
      );
      await tester.pumpAndSettle();
      // 终端 Tab 的引导文案也是「会话未建立」，断言限定在 SFTP 面板内。
      expect(
        find.descendant(
          of: find.byType(SftpTab),
          matching: find.textContaining('会话未建立', findRichText: true),
        ),
        findsOneWidget,
      );
    });

    testWidgets('移动端详情页同样有 SFTP Tab', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('zh')];
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        NoShellApp(store: ServerStore(seed: demoServers)),
      );
      await tester.pump();
      await tester.tap(find.text('db-primary'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(of: find.byType(TabBar), matching: find.text('SFTP')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('会话未建立', findRichText: true), findsOneWidget);
    });
  });
}
