/// 服务器负载采集：远程命令 + 跨平台解析。
///
/// 采集分两族：Linux 读 procfs（`/proc/stat`、`/proc/meminfo`、`/proc/net/dev`），
/// 其余类 Unix（macOS / *BSD）退回 `sysctl`、`vm_stat`、`netstat` 与 `top`。
/// **不引入任何远端依赖**（不要求装 `vnstat` / `sysstat` / Python），
/// 只用 POSIX 系统自带的命令——SSH 管理器的概览页不该为了一个图表去装东西。
///
/// 命令在一条 SSH exec 通道里跑完，段落用 `@@名字` 分隔：一次往返拿全部指标，
/// 轮询频率才有意义（多通道串行往返会把采样间隔拖到十几秒）。
/// 所有可能缺的段落都用 `2>/dev/null` 静音，解析端逐段判空，
/// 因此同一套脚本能同时服务 Linux、macOS 与部分 BSD。
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 负载采集命令。以 POSIX sh 书写（不依赖 bash 扩展），无需 root。
///
/// 段名是采集与解析之间的契约，改动要同步 [ServerMetricsParser]；
/// `@@kind` 只用来给解析器省掉「靠字段猜系统」的分支。
const String kServerMetricsCommand = r'''
export LC_ALL=C
echo '@@hostname'
uname -n 2>/dev/null
echo '@@os'
uname -s 2>/dev/null
echo '@@kernel'
uname -r 2>/dev/null
echo '@@arch'
uname -m 2>/dev/null
echo '@@now'
date +%s 2>/dev/null
if [ -r /proc/stat ]; then
echo '@@kind'
echo linux
echo '@@load'
cat /proc/loadavg 2>/dev/null
echo '@@uptime'
cat /proc/uptime 2>/dev/null
echo '@@cpu'
head -n 1 /proc/stat 2>/dev/null
echo '@@cores'
grep -c '^processor' /proc/cpuinfo 2>/dev/null
echo '@@mem'
cat /proc/meminfo 2>/dev/null
echo '@@net'
cat /proc/net/dev 2>/dev/null
else
echo '@@kind'
echo bsd
echo '@@load'
sysctl -n vm.loadavg 2>/dev/null
echo '@@boot'
sysctl -n kern.boottime 2>/dev/null
echo '@@cores'
sysctl -n hw.ncpu 2>/dev/null
echo '@@memtotal'
sysctl -n hw.memsize 2>/dev/null
echo '@@vmstat'
vm_stat 2>/dev/null
echo '@@cptime'
sysctl -n kern.cp_time 2>/dev/null
echo '@@net'
netstat -ibn 2>/dev/null
echo '@@cputop'
top -l 2 -n 0 -s 1 2>/dev/null | grep 'CPU usage' | tail -n 1
fi
echo '@@df'
df -kP / 2>/dev/null
''';

/// 一次采集的原始读数。
///
/// CPU 与网速是**差分**指标：这里只带计数器，百分比 / 速率由轮询方
/// （`ServerMonitor`）拿前后两次读数算，解析层保持无状态、便于单测。
@immutable
class ServerMetricsSample {
  const ServerMetricsSample({
    this.hostname,
    this.osName,
    this.kernel,
    this.arch,
    this.cpuCores,
    this.uptime,
    this.load1,
    this.load5,
    this.load15,
    this.cpuBusyTicks,
    this.cpuTotalTicks,
    this.cpuPercentDirect,
    this.memUsedBytes,
    this.memTotalBytes,
    this.diskUsedBytes,
    this.diskTotalBytes,
    this.diskMount,
    this.rxBytes,
    this.txBytes,
  });

  /// 主机名（`uname -n`）。
  final String? hostname;

  /// 内核名（`uname -s`：Linux / Darwin / FreeBSD）。
  final String? osName;

  /// 内核版本（`uname -r`）。
  final String? kernel;

  /// CPU 架构（`uname -m`）。
  final String? arch;

  final int? cpuCores;

  /// 开机时长（秒）。
  final double? uptime;

  final double? load1;
  final double? load5;
  final double? load15;

  /// Linux / BSD `kern.cp_time` 的累计 CPU 刻度；差分算占用率。
  final int? cpuBusyTicks;
  final int? cpuTotalTicks;

  /// macOS 只能从 `top` 拿现成的占用率（拿不到累计刻度时用这个）。
  final double? cpuPercentDirect;

  final int? memUsedBytes;
  final int? memTotalBytes;

  final int? diskUsedBytes;
  final int? diskTotalBytes;
  final String? diskMount;

  /// 网卡累计收发字节（所有非回环网卡求和）；差分算速率。
  final int? rxBytes;
  final int? txBytes;

  /// 一段可用的读数都没有：远端既不是 procfs 也给不出常用命令的结果。
  /// 轮询方据此判定「该主机不支持指标采集」，停止重试而不是每 3 秒打一次。
  bool get isEmpty =>
      hostname == null &&
      cpuTotalTicks == null &&
      cpuPercentDirect == null &&
      memTotalBytes == null &&
      diskTotalBytes == null &&
      rxBytes == null &&
      txBytes == null;

  /// CPU 计数器可用于差分。
  bool get hasCpuCounters => cpuBusyTicks != null && cpuTotalTicks != null;
}

/// `kServerMetricsCommand` 输出的解析器。
///
/// 容忍：段缺失、空段、段内多行、行尾 CR、无关前缀行（登录 banner）。
abstract final class ServerMetricsParser {
  static ServerMetricsSample parse(String output) {
    final sections = _sectionsOf(output);

    final kind = _firstLine(sections['kind'])?.toLowerCase();
    final now = int.tryParse(_firstLine(sections['now']) ?? '');
    final cores = int.tryParse(_firstLine(sections['cores']) ?? '');
    final load = _loadAverages(sections['load']);

    final uptime =
        _firstDouble(sections['uptime']) ??
        _uptimeFromBoot(sections['boot'], now);

    final cpu = switch (kind) {
      'linux' => _linuxCpu(sections['cpu']),
      'bsd' => _bsdCpuTicks(sections['cptime']),
      _ => _CpuTicks.empty(),
    };
    final cpuDirect = cpu.hasCounters
        ? null
        : _cpuPercentFromTop(sections['cputop']);

    final mem = kind == 'bsd'
        ? _bsdMemory(sections['memtotal'], sections['vmstat'])
        : _linuxMemory(sections['mem']);
    final net = kind == 'bsd'
        ? _bsdNetwork(sections['net'])
        : _linuxNetwork(sections['net']);
    final disk = _disk(sections['df']);

    return ServerMetricsSample(
      hostname: _firstLine(sections['hostname']),
      osName: _firstLine(sections['os']),
      kernel: _firstLine(sections['kernel']),
      arch: _firstLine(sections['arch']),
      cpuCores: cores != null && cores > 0 ? cores : null,
      uptime: uptime,
      load1: load.$1,
      load5: load.$2,
      load15: load.$3,
      cpuBusyTicks: cpu.busy,
      cpuTotalTicks: cpu.total,
      cpuPercentDirect: cpuDirect,
      memUsedBytes: mem.$1,
      memTotalBytes: mem.$2,
      diskUsedBytes: disk.$1,
      diskTotalBytes: disk.$2,
      diskMount: disk.$3,
      rxBytes: net.$1,
      txBytes: net.$2,
    );
  }

  /// 按 `@@段名` 把输出切段；第一个标记之前的内容（banner）丢弃。
  static Map<String, String> _sectionsOf(String output) {
    final sections = <String, String>{};
    String? current;
    final buffer = StringBuffer();
    void flush() {
      final key = current;
      if (key != null) sections[key] = buffer.toString().trim();
      buffer.clear();
    }

    for (final rawLine in output.split('\n')) {
      final line = rawLine.endsWith('\r')
          ? rawLine.substring(0, rawLine.length - 1)
          : rawLine;
      if (line.startsWith('@@')) {
        flush();
        current = line.substring(2).trim();
        continue;
      }
      if (current != null) {
        buffer.writeln(line);
      }
    }
    flush();
    return sections;
  }

  static String? _firstLine(String? value) {
    if (value == null) return null;
    for (final line in value.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  static double? _firstDouble(String? value) {
    final line = _firstLine(value);
    if (line == null) return null;
    return double.tryParse(line.split(RegExp(r'\s+')).first);
  }

  /// 负载三件套：Linux 是 `0.52 0.58 0.59 1/123 4567`，
  /// macOS 的 `vm.loadavg` 是 `{ 1.23 1.45 1.67 }`。取前三个数字即可。
  static (double?, double?, double?) _loadAverages(String? value) {
    if (value == null) return (null, null, null);
    final numbers = RegExp(r'[-+]?\d+(?:\.\d+)?')
        .allMatches(value)
        .map((m) => double.parse(m.group(0)!))
        .toList();
    if (numbers.isEmpty) return (null, null, null);
    double? at(int i) => i < numbers.length ? numbers[i] : null;
    return (at(0), at(1), at(2));
  }

  /// BSD 用 `kern.boottime`（`{ sec = 1750000000, usec = 0 } ...`）配远端
  /// `date +%s` 算开机时长。不用本机时钟：客户端与服务器可能差时区或漂移。
  static double? _uptimeFromBoot(String? boot, int? remoteNow) {
    if (boot == null || remoteNow == null) return null;
    final match = RegExp(r'sec\s*=\s*(\d+)').firstMatch(boot);
    final sec = match == null ? null : int.tryParse(match.group(1)!);
    if (sec == null || remoteNow <= sec) return null;
    return (remoteNow - sec).toDouble();
  }

  /// Linux `/proc/stat` 第一行：
  /// `cpu  user nice system idle iowait irq softirq steal guest guest_nice`
  /// guest 已包含在 user / nice 里，只取前 8 列求和，否则会重复计数。
  static _CpuTicks _linuxCpu(String? value) {
    final line = _firstLine(value);
    if (line == null) return const _CpuTicks.empty();
    final parts = line.split(RegExp(r'\s+'));
    if (parts.isEmpty || !parts.first.startsWith('cpu')) {
      return const _CpuTicks.empty();
    }
    final ticks = <int>[];
    for (final part in parts.skip(1)) {
      final tick = int.tryParse(part);
      if (tick == null) break;
      ticks.add(tick);
    }
    if (ticks.length < 5) return const _CpuTicks.empty();
    final total = ticks.take(8).fold<int>(0, (sum, tick) => sum + tick);
    // idle + iowait 都算「空转」：等待 IO 的 CPU 没在干活。
    final idle = ticks[3] + ticks[4];
    return _CpuTicks(busy: total - idle, total: total);
  }

  /// BSD `kern.cp_time`：`user nice sys intr idle`（5 个累计刻度）。
  static _CpuTicks _bsdCpuTicks(String? value) {
    final line = _firstLine(value);
    if (line == null) return const _CpuTicks.empty();
    final ticks = <int>[];
    for (final part in line.split(RegExp(r'\s+'))) {
      final tick = int.tryParse(part);
      if (tick == null) break;
      ticks.add(tick);
    }
    if (ticks.length < 5) return const _CpuTicks.empty();
    final total = ticks.fold<int>(0, (sum, tick) => sum + tick);
    return _CpuTicks(busy: total - ticks.last, total: total);
  }

  /// macOS `top` 的 `CPU usage: 3.12% user, 6.25% sys, 90.62% idle`。
  static double? _cpuPercentFromTop(String? value) {
    if (value == null) return null;
    final match = RegExp(
      r'([\d.]+)%\s*user,\s*([\d.]+)%\s*sys,\s*([\d.]+)%\s*idle',
    ).firstMatch(value);
    if (match == null) return null;
    final idle = double.tryParse(match.group(3)!);
    if (idle == null) return null;
    return (100 - idle).clamp(0, 100).toDouble();
  }

  /// Linux `/proc/meminfo`：`MemTotal` / `MemAvailable`（老内核退回
  /// free + buffers + cached）。单位是 kB。
  static (int?, int?) _linuxMemory(String? value) {
    if (value == null) return (null, null);
    final fields = <String, int>{};
    for (final match in RegExp(
      r'^(\w+):\s+(\d+)',
      multiLine: true,
    ).allMatches(value)) {
      fields[match.group(1)!] = int.parse(match.group(2)!);
    }
    final totalKb = fields['MemTotal'];
    if (totalKb == null) return (null, null);
    var availableKb = fields['MemAvailable'];
    if (availableKb == null) {
      final free = fields['MemFree'];
      final buffers = fields['Buffers'];
      final cached = fields['Cached'];
      if (free != null) {
        availableKb =
            free +
            (buffers ?? 0) +
            (cached ?? 0) +
            (fields['SReclaimable'] ?? 0);
      }
    }
    if (availableKb == null) return (null, totalKb * 1024);
    final usedKb = math.max(0, totalKb - availableKb);
    return (usedKb * 1024, totalKb * 1024);
  }

  /// macOS / BSD 内存：总量取 `hw.memsize`，已用按 `vm_stat` 的
  /// active + wired + compressor 页估算。
  ///
  /// 「已用」在这里不可能精确到与活动监视器一致（free / inactive /
  /// purgeable 的回收时机只有内核知道），但只要口径固定，趋势就是对的。
  static (int?, int?) _bsdMemory(String? totalValue, String? vmStat) {
    final total = int.tryParse(_firstLine(totalValue) ?? '');
    if (vmStat == null) return (null, total);
    final pageSizeMatch = RegExp(r'page size of (\d+) bytes')
        .firstMatch(vmStat);
    final pageSize = pageSizeMatch == null
        ? 4096
        : int.parse(pageSizeMatch.group(1)!);
    final pages = <String, int>{};
    for (final match in RegExp(
      r'^(?:Pages?|")([^:"]+)"?:\s+(\d+)',
      multiLine: true,
    ).allMatches(vmStat)) {
      pages[match.group(1)!.trim().toLowerCase()] = int.parse(match.group(2)!);
    }
    int pagesOf(String key) => pages[key] ?? 0;
    final usedPages =
        pagesOf('active') +
        pagesOf('wired down') +
        pagesOf('occupied by compressor');
    if (usedPages == 0) return (null, total);
    final used = usedPages * pageSize;
    if (total == null) return (used, null);
    return (math.min(used, total), total);
  }

  /// Linux `/proc/net/dev`：`iface: rx_bytes ... tx_bytes ...`（16 列）。
  /// 跳过 lo 与虚拟网卡，避免把容器网桥的流量重复算进物理网卡。
  static (int?, int?) _linuxNetwork(String? value) {
    if (value == null) return (null, null);
    var rx = 0;
    var tx = 0;
    var seen = false;
    for (final rawLine in value.split('\n')) {
      final line = rawLine.trim();
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final name = line.substring(0, colon).trim();
      if (_ignoredInterface(name)) continue;
      final fields = line.substring(colon + 1).trim().split(RegExp(r'\s+'));
      if (fields.length < 9) continue;
      final rxBytes = int.tryParse(fields[0]);
      final txBytes = int.tryParse(fields[8]);
      if (rxBytes == null || txBytes == null) continue;
      rx += rxBytes;
      tx += txBytes;
      seen = true;
    }
    return seen ? (rx, tx) : (null, null);
  }

  /// BSD `netstat -ibn`：只认 `<Link#N>` 行（一行就是一块网卡的全部计数），
  /// 列的位置由表头决定——各 BSD 的列数不一致（FreeBSD 多一列 Idrop），
  /// 写死下标会在另一种系统上读错列。
  ///
  /// `<Link#>` 行在 macOS 上 Address 列为空、在 FreeBSD 上有 MAC，
  /// 所以先判 Address 是否存在，再按表头偏移取 Ibytes / Obytes。
  static (int?, int?) _bsdNetwork(String? value) {
    if (value == null) return (null, null);
    final lines = value.split('\n');
    List<String>? header;
    for (final line in lines) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length > 3 && parts.first == 'Name') {
        header = parts;
        break;
      }
    }
    if (header == null) return (null, null);
    final packetsIndex = header.indexOf('Ipkts');
    final rxIndex = header.indexOf('Ibytes');
    final txIndex = header.indexOf('Obytes');
    if (packetsIndex < 0 || rxIndex < 0 || txIndex < 0) return (null, null);

    var rx = 0;
    var tx = 0;
    var seen = false;
    for (final line in lines) {
      final parts = line.trim().split(RegExp(r'\s+'));
      // Name / Mtu / Network 三列固定在前，Network 为 `<Link#N>` 才是链路行。
      if (parts.length < 4 || parts[0] == 'Name') continue;
      if (!parts[2].startsWith('<Link')) continue;
      final name = parts[0];
      if (_ignoredInterface(name)) continue;
      // FreeBSD 的链路行在 Address 列有 MAC；macOS 这一列为空。
      final addressPresent = parts.length > 3 && parts[3].contains(':');
      final start = addressPresent ? 4 : 3;
      int? field(int headerIndex) {
        final index = start + (headerIndex - packetsIndex);
        if (headerIndex < packetsIndex || index >= parts.length) return null;
        return int.tryParse(parts[index]);
      }

      final rxBytes = field(rxIndex);
      final txBytes = field(txIndex);
      if (rxBytes == null || txBytes == null) continue;
      rx += rxBytes;
      tx += txBytes;
      seen = true;
    }
    return seen ? (rx, tx) : (null, null);
  }

  static bool _ignoredInterface(String name) =>
      name == 'lo' ||
      name == 'lo0' ||
      name.startsWith('docker') ||
      name.startsWith('veth') ||
      name.startsWith('br-') ||
      name.startsWith('virbr');

  /// `df -kP /`：单位为 1K 块。保留块的差异让「已用 + 可用 ≠ 总量」，
  /// 所以百分比统一用 已用 / 总量。
  static (int?, int?, String?) _disk(String? value) {
    if (value == null) return (null, null, null);
    for (final line in value.split('\n').reversed) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 6) continue;
      final totalKb = int.tryParse(parts[1]);
      final usedKb = int.tryParse(parts[2]);
      if (totalKb == null || usedKb == null || totalKb <= 0) continue;
      final mount = parts.sublist(5).join(' ');
      return (usedKb * 1024, totalKb * 1024, mount);
    }
    return (null, null, null);
  }
}

/// CPU 累计刻度（Linux / BSD 共用）。
@immutable
final class _CpuTicks {
  const _CpuTicks({required this.busy, required this.total});
  const _CpuTicks.empty() : busy = null, total = null;

  final int? busy;
  final int? total;

  bool get hasCounters => busy != null && total != null;
}

/// 字节数的人类可读形式（1024 进制，一位小数）。
///
/// 单位符号（B / KB / MB / GB）是技术记号、不随语言翻译，与终端里的
/// `ssh` / `SFTP` 同一取向；需要翻译的只有跟随它们的说明文字。
String formatBytes(num bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  // 个位数保留一位小数（6.4 GB），两位数以上取整（126 GB）：卡片宽度有限，
  // 多出来的小数位对「用了多少」没有信息量。
  final text = value >= 10 || unit == 0
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

/// 速率的人类可读形式，如 `1.2 MB/s`。
String formatRate(double bytesPerSecond) =>
    '${formatBytes(bytesPerSecond.clamp(0, double.infinity))}/s';
