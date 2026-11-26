import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'server_metrics.dart';
import 'ssh_transport.dart';

/// 服务器负载轮询器的状态。
enum ServerMonitorStatus {
  /// 还没开始采样（未连接 / 概览页没在前台）。
  idle,

  /// 已开始，但一次可用读数都还没拿到。
  loading,

  /// 有数据且在持续采样。
  live,

  /// 远端给不出任何指标（Windows / 极简系统）：停止重试。
  unsupported,

  /// 采样失败（网络抖动 / 命令超时），保留上一次数据并继续重试。
  failed,
}

/// 概览图表上的一个采样点。
@immutable
final class MetricPoint {
  const MetricPoint({
    required this.at,
    this.cpuPercent,
    this.memoryPercent,
    this.diskPercent,
    this.rxRate,
    this.txRate,
  });

  final DateTime at;

  /// 0…100；Linux 上第一个采样点没有差分基准，因此为 null。
  final double? cpuPercent;
  final double? memoryPercent;
  final double? diskPercent;

  /// 字节 / 秒；取不到收发计数时为 null。
  final double? rxRate;
  final double? txRate;
}

/// 一次解析后的完整指标快照（原始读数 + 差分结果）。
@immutable
final class ServerMetrics {
  const ServerMetrics({
    this.hostname,
    this.osName,
    this.kernel,
    this.arch,
    this.cpuCores,
    this.uptime,
    this.load1,
    this.load5,
    this.load15,
    this.cpuPercent,
    this.memoryUsedBytes,
    this.memoryTotalBytes,
    this.diskUsedBytes,
    this.diskTotalBytes,
    this.diskMount,
    this.rxRate,
    this.txRate,
  });

  final String? hostname;
  final String? osName;
  final String? kernel;
  final String? arch;
  final int? cpuCores;
  final Duration? uptime;
  final double? load1;
  final double? load5;
  final double? load15;
  final double? cpuPercent;
  final int? memoryUsedBytes;
  final int? memoryTotalBytes;
  final int? diskUsedBytes;
  final int? diskTotalBytes;
  final String? diskMount;
  final double? rxRate;
  final double? txRate;

  double? get memoryPercent => _percent(memoryUsedBytes, memoryTotalBytes);

  double? get diskPercent => _percent(diskUsedBytes, diskTotalBytes);

  static double? _percent(int? used, int? total) {
    if (used == null || total == null || total <= 0) return null;
    return (used / total * 100).clamp(0, 100);
  }
}

/// 一条会话的服务器负载采样器。
///
/// 生命周期由 [TerminalSession] 持有（与 SFTP / 转发同样挂在会话上），
/// 但**采样由界面驱动**：概览页可见且会话已连接时 [start]，切走 Tab /
/// 应用退到后台 / 断开时 [stop]——没人看的图表不该每 3 秒去服务器跑一次
/// 命令，那在按流量计费的链路上是实打实的成本。
///
/// 轮询是「跑完一次再排下一次」而不是 `Timer.periodic`：慢链路上一次采集
/// 可能超过采样间隔，周期计时器会让请求叠加，这里以完成时间为准。
final class ServerMonitor extends ChangeNotifier {
  ServerMonitor({
    required this.runCommand,
    this.interval = const Duration(seconds: 3),
    this.historyLength = 60,
    DateTime Function()? clock,
    this.timeout = const Duration(seconds: 8),
  }) : _clock = clock ?? DateTime.now;

  /// 采样间隔（也是界面「每 N 秒」文案的来源）。
  final Duration interval;

  /// 图表保留的采样点数量（默认 60 点 ≈ 3 分钟）。
  final int historyLength;

  /// 远端命令执行入口（会话传输层）。
  final RemoteCommandRunner runCommand;

  /// 单次采集的超时上限：超过它按失败处理并重试，不把界面卡在 loading。
  final Duration timeout;

  final DateTime Function() _clock;

  final List<MetricPoint> _history = [];

  ServerMetrics? _metrics;
  ServerMonitorStatus _status = ServerMonitorStatus.idle;
  String? _error;
  DateTime? _updatedAt;

  ServerMetricsSample? _lastSample;
  DateTime? _lastSampleAt;

  Timer? _timer;
  bool _running = false;
  bool _polling = false;
  bool _disposed = false;

  ServerMetrics? get metrics => _metrics;

  /// 采样历史，按时间从旧到新。
  late final List<MetricPoint> history = UnmodifiableListView(_history);

  ServerMonitorStatus get status => _status;

  /// 最近一次失败的原始错误串；只用于诊断，界面展示走本地化文案。
  String? get error => _error;

  DateTime? get updatedAt => _updatedAt;

  bool get isRunning => _running;

  /// 开始采样：立即采一次，之后按 [interval] 滚动。可重复调用。
  void start() {
    if (_disposed || _running) return;
    if (_status == ServerMonitorStatus.unsupported) return;
    _running = true;
    if (_status != ServerMonitorStatus.live) {
      _status = ServerMonitorStatus.loading;
      _notify();
    }
    _schedule(Duration.zero);
  }

  /// 停止采样（保留已采到的数据与历史，重新 [start] 时接着画）。
  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  /// 手动刷新一次（采样间隔之外）。
  Future<void> refresh() async {
    if (_disposed) return;
    if (!_running) {
      // 手动刷新视为用户要求继续采样。
      if (_status == ServerMonitorStatus.unsupported && _metrics == null) {
        return;
      }
      _running = true;
    }
    await _poll();
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (!_running || _disposed) return;
    _timer = Timer(delay, _poll);
  }

  Future<void> _poll() async {
    // 先取消挂着的计时器再采：手动刷新会绕过计时器直接进来，不取消的话
    // 原来那一次仍会按时触发，每点一次刷新就多一条并行节奏。
    _timer?.cancel();
    _timer = null;
    if (!_running || _disposed || _polling) return;
    _polling = true;
    try {
      final output = await runCommand(kServerMetricsCommand).timeout(timeout);
      if (_disposed) return;
      final sample = ServerMetricsParser.parse(output);
      if (sample.isEmpty) {
        _stopUnsupported();
        return;
      }
      _apply(sample, _clock());
      _error = null;
      _status = ServerMonitorStatus.live;
      _notify();
    } on UnsupportedError catch (error) {
      // 平台 / 传输层明确表示做不了（web、假传输）：没有重试的意义。
      _error = error.toString();
      _stopUnsupported();
    } on Object catch (error) {
      if (_disposed) return;
      _error = error.toString();
      // 一次都没成功过就是 failed；已有数据时保留旧图，只在状态条上提示。
      _status = ServerMonitorStatus.failed;
      _notify();
    } finally {
      _polling = false;
      if (_running && !_disposed) _schedule(interval);
    }
  }

  void _stopUnsupported() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _status = ServerMonitorStatus.unsupported;
    _notify();
  }

  void _apply(ServerMetricsSample sample, DateTime now) {
    final previous = _lastSample;
    final previousAt = _lastSampleAt;
    final elapsed = previousAt == null
        ? Duration.zero
        : now.difference(previousAt);
    final deltaUsable =
        previous != null &&
        elapsed.inMilliseconds >= 200 &&
        elapsed.inMilliseconds <= 60000;

    double? cpuPercent = sample.cpuPercentDirect;
    if (cpuPercent == null &&
        deltaUsable &&
        sample.hasCpuCounters &&
        previous.hasCpuCounters) {
      final totalDelta = sample.cpuTotalTicks! - previous.cpuTotalTicks!;
      final busyDelta = sample.cpuBusyTicks! - previous.cpuBusyTicks!;
      if (totalDelta > 0 && busyDelta >= 0) {
        cpuPercent = (busyDelta / totalDelta * 100).clamp(0, 100).toDouble();
      }
    }
    // 差分条件不满足（刚启动 / 手动连点刷新）时沿用上一次的占用率，
    // 免得图表上的 CPU 线突然断一截。
    cpuPercent ??= _metrics?.cpuPercent;

    double? rxRate;
    double? txRate;
    if (deltaUsable &&
        sample.rxBytes != null &&
        sample.txBytes != null &&
        previous.rxBytes != null &&
        previous.txBytes != null) {
      final seconds = elapsed.inMicroseconds / 1000000;
      final rxDelta = sample.rxBytes! - previous.rxBytes!;
      final txDelta = sample.txBytes! - previous.txBytes!;
      // 计数器回绕 / 网卡重连会让差值为负，按 0 处理而不是画出一个负速率。
      if (seconds > 0) {
        rxRate = rxDelta >= 0 ? rxDelta / seconds : 0;
        txRate = txDelta >= 0 ? txDelta / seconds : 0;
      }
    }
    // 第一笔采样没有差分基准，网速先记 0（图表从下一个点开始有值）。
    rxRate ??= previous == null ? 0 : _metrics?.rxRate;
    txRate ??= previous == null ? 0 : _metrics?.txRate;

    _metrics = ServerMetrics(
      hostname: sample.hostname,
      osName: sample.osName,
      kernel: sample.kernel,
      arch: sample.arch,
      cpuCores: sample.cpuCores,
      uptime: sample.uptime == null
          ? null
          : Duration(seconds: sample.uptime!.round()),
      load1: sample.load1,
      load5: sample.load5,
      load15: sample.load15,
      cpuPercent: cpuPercent,
      memoryUsedBytes: sample.memUsedBytes,
      memoryTotalBytes: sample.memTotalBytes,
      diskUsedBytes: sample.diskUsedBytes,
      diskTotalBytes: sample.diskTotalBytes,
      diskMount: sample.diskMount,
      rxRate: rxRate,
      txRate: txRate,
    );
    _appendPoint(
      MetricPoint(
        at: now,
        cpuPercent: cpuPercent,
        memoryPercent: _metrics!.memoryPercent,
        diskPercent: _metrics!.diskPercent,
        rxRate: rxRate,
        txRate: txRate,
      ),
    );
    _lastSample = sample;
    _lastSampleAt = now;
    _updatedAt = now;
  }

  void _appendPoint(MetricPoint point) {
    _history.add(point);
    if (_history.length <= historyLength) return;
    // 一次性裁掉溢出量：逐点 removeAt(0) 在 60 点上无所谓，但这里保持
    // 「超出多少裁多少」的直观语义，也避免以后调大窗口时退化成 O(n²)。
    _history.removeRange(0, _history.length - historyLength);
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _running = false;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
