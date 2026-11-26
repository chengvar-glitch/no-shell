import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/ssh/server_monitor.dart';

/// 只带 CPU 累计刻度与网卡计数的 Linux 采集结果：够算差分，省掉无关段落。
String _sample({
  required int user,
  required int idle,
  required int rx,
  required int tx,
  int memTotal = 1000,
  int memAvailable = 250,
}) =>
    '''
@@hostname
web-01
@@os
Linux
@@kind
linux
@@load
0.10 0.20 0.30 1/10 100
@@cpu
cpu $user 0 0 $idle 0 0 0 0 0 0
@@mem
MemTotal: $memTotal kB
MemAvailable: $memAvailable kB
@@net
eth0: $rx 0 0 0 0 0 0 0 $tx 0 0 0 0 0 0 0
@@df
Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/sda1 1000000 250000 750000 25% /
''';

void main() {
  test('首帧没有差分基准：CPU 为 null，内存 / 磁盘 / 系统信息立即可用', () {
    fakeAsync((async) {
      final monitor = ServerMonitor(
        runCommand: (_) async =>
            _sample(user: 100, idle: 900, rx: 1000, tx: 2000),
        clock: () => DateTime(2024, 1, 1),
      );
      addTearDown(monitor.dispose);

      monitor.start();
      async.elapse(Duration.zero);

      expect(monitor.status, ServerMonitorStatus.live);
      final metrics = monitor.metrics!;
      expect(metrics.hostname, 'web-01');
      expect(metrics.cpuPercent, isNull);
      expect(metrics.memoryPercent, closeTo(75, 0.001));
      expect(metrics.diskPercent, closeTo(25, 0.001));
      expect(monitor.history, hasLength(1));
      expect(monitor.history.single.cpuPercent, isNull);
    });
  });

  test('第二次采样按刻度差分算 CPU，按字节差算上下行速率', () {
    fakeAsync((async) {
      var now = DateTime(2024, 1, 1);
      var call = 0;
      final monitor = ServerMonitor(
        runCommand: (_) async {
          call++;
          return call == 1
              ? _sample(user: 100, idle: 900, rx: 1000, tx: 2000)
              : _sample(user: 200, idle: 1800, rx: 4000, tx: 2000);
        },
        clock: () => now,
      );
      addTearDown(monitor.dispose);

      monitor.start();
      async.elapse(Duration.zero);
      expect(monitor.metrics!.cpuPercent, isNull);

      now = now.add(const Duration(seconds: 3));
      async.elapse(const Duration(seconds: 3));
      async.elapse(Duration.zero);

      // Δbusy / Δtotal = 100 / 1000。
      expect(monitor.metrics!.cpuPercent, closeTo(10, 0.001));
      // Δrx 3000 字节 / 3 秒；tx 没变。
      expect(monitor.metrics!.rxRate, closeTo(1000, 0.001));
      expect(monitor.metrics!.txRate, closeTo(0, 0.001));
      expect(monitor.history, hasLength(2));
      expect(monitor.history.last.cpuPercent, closeTo(10, 0.001));
    });
  });

  test('历史长度有上限，超出后保留最近的点', () {
    fakeAsync((async) {
      var now = DateTime(2024, 1, 1);
      var call = 0;
      final monitor = ServerMonitor(
        runCommand: (_) async {
          call++;
          return _sample(user: call * 100, idle: call * 900, rx: 0, tx: 0);
        },
        historyLength: 3,
        clock: () => now,
      );
      addTearDown(monitor.dispose);

      monitor.start();
      async.elapse(Duration.zero);
      for (var i = 0; i < 4; i++) {
        now = now.add(const Duration(seconds: 3));
        async.elapse(const Duration(seconds: 3));
        async.elapse(Duration.zero);
      }
      expect(monitor.history, hasLength(3));
      expect(monitor.history.last.at, now);
    });
  });

  test('远端明确不支持（UnsupportedError）时永久停止，不再排下一次采样', () {
    fakeAsync((async) {
      var calls = 0;
      final monitor = ServerMonitor(
        runCommand: (_) async {
          calls++;
          throw UnsupportedError('no remote command');
        },
      );
      addTearDown(monitor.dispose);

      monitor.start();
      async.elapse(Duration.zero);
      expect(monitor.status, ServerMonitorStatus.unsupported);
      expect(monitor.isRunning, isFalse);
      expect(async.pendingTimers, isEmpty);

      async.elapse(const Duration(minutes: 1));
      expect(calls, 1);
    });
  });

  test('输出里没有任何可用指标时同样判为不支持', () {
    fakeAsync((async) {
      final monitor = ServerMonitor(
        runCommand: (_) async => 'Windows PowerShell\r\n',
      );
      addTearDown(monitor.dispose);

      monitor.start();
      async.elapse(Duration.zero);
      expect(monitor.status, ServerMonitorStatus.unsupported);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('瞬时失败保留上次数据并继续重试，恢复后回到 live', () {
    fakeAsync((async) {
      var now = DateTime(2024, 1, 1);
      var fail = false;
      var calls = 0;
      final monitor = ServerMonitor(
        runCommand: (_) async {
          calls++;
          if (fail) throw StateError('connection lost');
          return _sample(user: 100, idle: 900, rx: 0, tx: 0);
        },
        clock: () => now,
      );
      addTearDown(monitor.dispose);

      monitor.start();
      async.elapse(Duration.zero);
      final before = monitor.metrics;
      expect(before, isNotNull);

      fail = true;
      now = now.add(const Duration(seconds: 3));
      async.elapse(const Duration(seconds: 3));
      async.elapse(Duration.zero);
      expect(monitor.status, ServerMonitorStatus.failed);
      expect(monitor.metrics, same(before));
      expect(monitor.error, contains('connection lost'));

      fail = false;
      now = now.add(const Duration(seconds: 3));
      async.elapse(const Duration(seconds: 3));
      async.elapse(Duration.zero);
      expect(monitor.status, ServerMonitorStatus.live);
      expect(calls, greaterThanOrEqualTo(3));
    });
  });

  test('stop 取消定时器，start 可再次启动；dispose 之后不再通知', () {
    fakeAsync((async) {
      var calls = 0;
      final monitor = ServerMonitor(
        runCommand: (_) async {
          calls++;
          return _sample(user: 100, idle: 900, rx: 0, tx: 0);
        },
      );
      var notifications = 0;
      monitor.addListener(() => notifications++);

      monitor.start();
      async.elapse(Duration.zero);
      expect(calls, 1);

      monitor.stop();
      async.elapse(const Duration(minutes: 1));
      expect(calls, 1);
      expect(async.pendingTimers, isEmpty);

      monitor.start();
      async.elapse(Duration.zero);
      expect(calls, 2);

      monitor.dispose();
      expect(async.pendingTimers, isEmpty);
      final seen = notifications;
      async.elapse(const Duration(minutes: 1));
      expect(notifications, seen);
    });
  });

  test('手动刷新会取消原计时器，不会多出一条并行采样节奏', () {
    fakeAsync((async) {
      var calls = 0;
      final monitor = ServerMonitor(
        runCommand: (_) async {
          calls++;
          return _sample(user: 100, idle: 900, rx: 0, tx: 0);
        },
      );
      addTearDown(monitor.dispose);

      monitor.start();
      async.elapse(Duration.zero);
      expect(calls, 1);

      // 在第 1 秒手动刷新：下一次自动采样应落在刷新后的第 3 秒。
      async.elapse(const Duration(seconds: 1));
      monitor.refresh();
      async.elapse(Duration.zero);
      expect(calls, 2);

      // 原来第 3 秒那次已经被取消，这里不应再采。
      async.elapse(const Duration(seconds: 2));
      expect(calls, 2);

      async.elapse(const Duration(seconds: 1));
      expect(calls, 3);
    });
  });

  test('手动刷新立刻采一次，不打断原来的采样节奏', () {
    fakeAsync((async) {
      var calls = 0;
      final monitor = ServerMonitor(
        runCommand: (_) async {
          calls++;
          return _sample(user: 100, idle: 900, rx: 0, tx: 0);
        },
      );
      addTearDown(monitor.dispose);

      monitor.start();
      async.elapse(Duration.zero);
      expect(calls, 1);

      monitor.refresh();
      async.elapse(Duration.zero);
      expect(calls, 2);
    });
  });
}
