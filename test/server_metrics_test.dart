import 'package:flutter_test/flutter_test.dart';
import 'package:no_shell/ssh/server_metrics.dart';

/// Linux 采集结果样例：/proc 各段 + df。
String _linuxOutput({
  int user = 123456,
  int idle = 5678901,
  int rx = 1000000,
  int tx = 2000000,
  int memAvailable = 8192000,
}) =>
    '''
@@hostname
web-01
@@os
Linux
@@kernel
6.8.0-45-generic
@@arch
x86_64
@@now
1732000000
@@kind
linux
@@load
0.52 0.58 0.59 1/523 45678
@@uptime
123456.78 987654.32
@@cpu
cpu  $user 2345 34567 $idle 12345 0 6789 0 0 0
@@cores
8
@@mem
MemTotal:       16384000 kB
MemFree:         2048000 kB
MemAvailable:   $memAvailable kB
Buffers:          512000 kB
Cached:          4096000 kB
SwapTotal:       2048000 kB
SwapFree:        2048000 kB
@@net
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 999999 50 0 0 0 0 0 0 888888 50 0 0 0 0 0 0
  eth0: $rx 100 0 0 0 0 0 0 $tx 200 0 0 0 0 0 0
@@df
Filesystem     1024-blocks      Used Available Capacity Mounted on
/dev/sda1        102400000  40960000  61440000      40% /
''';

/// macOS / BSD 采集结果样例：vm_stat + netstat + top。
const String _bsdOutput = '''
@@hostname
mac-mini.local
@@os
Darwin
@@kernel
24.1.0
@@arch
arm64
@@now
1732000000
@@kind
bsd
@@load
{ 1.23 1.45 1.67 }
@@boot
{ sec = 1731000000, usec = 0 } Fri Nov  8 10:00:00 2024
@@cores
10
@@memtotal
17179869184
@@vmstat
Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                               37003.
Pages active:                            400000.
Pages inactive:                          700000.
Pages speculative:                        12345.
Pages wired down:                        300000.
Pages purgeable:                          10000.
"Translation faults":                  1234567.
Pages occupied by compressor:            120000.
@@cptime

@@net
Name       Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
lo0       16384 <Link#1>                        1000     0     100000     1000     0     100000     0
lo0       16384 127           127.0.0.1           1000     -     100000     1000     -     100000     -
en0       1500  <Link#4>    aa:bb:cc:dd:ee:ff    5000     0    2000000     4000     0    1000000     0
en0       1500  192.168.1     192.168.1.5         5000     -    2000000     4000     -    1000000     -
@@cputop
CPU usage: 3.12% user, 6.25% sys, 90.62% idle
@@df
Filesystem     1024-blocks      Used Available Capacity Mounted on
/dev/disk3s1s1   971350180  500000000 450000000      53% /
''';

void main() {
  group('Linux（procfs）', () {
    test('解析系统信息 / 负载 / 内存 / 磁盘 / 网卡计数', () {
      final sample = ServerMetricsParser.parse(_linuxOutput());

      expect(sample.isEmpty, isFalse);
      expect(sample.hostname, 'web-01');
      expect(sample.osName, 'Linux');
      expect(sample.kernel, '6.8.0-45-generic');
      expect(sample.arch, 'x86_64');
      expect(sample.cpuCores, 8);
      expect(sample.uptime, closeTo(123456.78, 0.01));
      expect(sample.load1, 0.52);
      expect(sample.load5, 0.58);
      expect(sample.load15, 0.59);
      expect(sample.cpuPercentDirect, isNull);

      // 前 8 列求和 = 总刻度；idle + iowait 为空转。
      final total = 123456 + 2345 + 34567 + 5678901 + 12345 + 0 + 6789 + 0;
      expect(sample.cpuTotalTicks, total);
      expect(sample.cpuBusyTicks, total - (5678901 + 12345));

      // MemAvailable 优先，不用 free + buffers + cached。
      expect(sample.memTotalBytes, 16384000 * 1024);
      expect(sample.memUsedBytes, (16384000 - 8192000) * 1024);

      // lo 必须被跳过：只有 eth0 的计数。
      expect(sample.rxBytes, 1000000);
      expect(sample.txBytes, 2000000);

      expect(sample.diskTotalBytes, 102400000 * 1024);
      expect(sample.diskUsedBytes, 40960000 * 1024);
      expect(sample.diskMount, '/');
    });

    test('没有 MemAvailable 的老内核退回 free + buffers + cached', () {
      final output = _linuxOutput().replaceFirst(
        'MemAvailable:   8192000 kB',
        'MemFree:         2048000 kB',
      );
      final sample = ServerMetricsParser.parse(output);
      expect(
        sample.memUsedBytes,
        (16384000 - (2048000 + 512000 + 4096000)) * 1024,
      );
    });

    test('行尾 CR 与首个标记之前的 banner 不影响解析', () {
      final output =
          'Welcome to Ubuntu 24.04 LTS\r\n'
          '${_linuxOutput().replaceAll('\n', '\r\n')}';
      final sample = ServerMetricsParser.parse(output);
      expect(sample.hostname, 'web-01');
      expect(sample.diskMount, '/');
    });
  });

  group('BSD / macOS（sysctl + vm_stat + netstat + top）', () {
    test('解析系统信息 / 内存 / CPU 占用 / 网卡计数', () {
      final sample = ServerMetricsParser.parse(_bsdOutput);

      expect(sample.isEmpty, isFalse);
      expect(sample.osName, 'Darwin');
      expect(sample.cpuCores, 10);
      // 开机时长由远端 date + kern.boottime 算，不读本机时钟。
      expect(sample.uptime, closeTo(1000000, 0.01));
      expect(sample.load1, 1.23);
      expect(sample.load5, 1.45);
      expect(sample.load15, 1.67);

      // cptime 为空，改取 top 现成的占用率。
      expect(sample.cpuTotalTicks, isNull);
      expect(sample.cpuPercentDirect, closeTo(9.38, 0.001));

      const pageSize = 16384;
      expect(sample.memTotalBytes, 17179869184);
      expect(sample.memUsedBytes, (400000 + 300000 + 120000) * pageSize);

      // lo0 跳过，en0 按 <Link> 行去重（不能把 inet 那行再加一遍）。
      expect(sample.rxBytes, 2000000);
      expect(sample.txBytes, 1000000);
      expect(sample.diskMount, '/');
    });

    test('cptime 有计数时优先用差分而不是 top', () {
      final output = _bsdOutput.replaceFirst(
        "CPU usage: 3.12% user, 6.25% sys, 90.62% idle",
        '',
      );
      final withCptime = output.replaceFirst(
        '@@cptime\n\n',
        '@@cptime\n100 20 30 40 500\n',
      );
      final sample = ServerMetricsParser.parse(withCptime);
      expect(sample.cpuTotalTicks, 690);
      expect(sample.cpuBusyTicks, 190);
      expect(sample.cpuPercentDirect, isNull);
    });
  });

  group('容错', () {
    test('全是无关输出 → isEmpty（视为该主机不支持指标）', () {
      final sample = ServerMetricsParser.parse(
        'Windows PowerShell\r\nCopyright (C) Microsoft Corporation\r\n',
      );
      expect(sample.isEmpty, isTrue);
    });

    test('只有部分段缺失时，缺的字段为 null 但不影响其它字段', () {
      final sample = ServerMetricsParser.parse('''
@@os
Linux
@@kind
linux
@@load
0.10 0.20 0.30 1/10 100
@@df
Filesystem 1024-blocks Used Available Capacity Mounted on
/dev/sda1  1000000  250000  750000  25% /
''');
      expect(sample.isEmpty, isFalse);
      expect(sample.load1, 0.10);
      expect(sample.hostname, isNull);
      expect(sample.cpuCores, isNull);
      expect(sample.memTotalBytes, isNull);
      expect(sample.diskUsedBytes, 250000 * 1024);
    });

    test('netstat 表头列顺序不同的 BSD 也能按列名定位', () {
      const output = '''
@@kind
bsd
@@net
Name  Mtu Network Address Ipkts Ierrs Idrop Ibytes Opkts Oerrs Obytes
em0  1500 <Link#1>              10     0     0    3000    20     0    4000
''';
      final sample = ServerMetricsParser.parse(output);
      expect(sample.rxBytes, 3000);
      expect(sample.txBytes, 4000);
    });
  });

  group('格式化', () {
    test('字节数按 1024 进制并收敛小数位', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(16 * 1024 * 1024), '16 MB');
      expect(formatBytes(2 * 1024 * 1024 * 1024), '2.0 GB');
    });

    test('速率带 /s，负数按 0 处理', () {
      expect(formatRate(1536), '1.5 KB/s');
      expect(formatRate(-10), '0 B/s');
    });
  });
}
