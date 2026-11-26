import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models.dart';
import '../ssh/server_metrics.dart';
import '../ssh/server_monitor.dart';
import '../ssh/terminal_session.dart';
import '../theme.dart';
import 'tab_visibility.dart';

/// 概览页的「服务器负载」分区：系统信息 + CPU / 内存 / 磁盘 / 网络图表。
///
/// 数据来自 [TerminalSession.monitor]（会话层持有、界面驱动起停）。本组件
/// 只负责「什么时候该采样」与「怎么画」：
/// - 会话未连接 / 概览 Tab 不可见 / 窗口不在前台 / 被别的路由盖住 → 停止采样；
/// - 重新可见且仍连接 → 立刻补采一次，图表不用等下一轮定时器。
class ServerLoadSection extends StatefulWidget {
  const ServerLoadSection({super.key, required this.server, this.session});

  /// 当前主机（拨号信息与主机名兜底用）。
  final SshServer server;

  /// 当前会话；为空表示未连接。
  final TerminalSession? session;

  @override
  State<ServerLoadSection> createState() => _ServerLoadSectionState();
}

class _ServerLoadSectionState extends State<ServerLoadSection> {
  late final AppLifecycleListener _lifecycle;
  bool _foreground = true;
  bool _tabVisible = true;
  bool _routeCurrent = true;

  TerminalSession? get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycleChanged);
    widget.session?.addListener(_onSessionChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tabVisible = TabVisibilityScope.visibleOf(context);
    _routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    _syncSampling();
  }

  @override
  void didUpdateWidget(ServerLoadSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      oldWidget.session?.removeListener(_onSessionChanged);
      oldWidget.session?.monitor.stop();
      widget.session?.addListener(_onSessionChanged);
      _syncSampling();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.session?.removeListener(_onSessionChanged);
    // 只停采样，不 dispose：monitor 归会话所有。
    widget.session?.monitor.stop();
    super.dispose();
  }

  void _onLifecycleChanged(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _syncSampling();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    // 会话阶段（连接中 → 已连接 / 断开）会改变分区形态与采样开关。
    setState(() {});
    _syncSampling();
  }

  bool get _shouldSample {
    final session = _session;
    return session != null &&
        session.phase == TerminalPhase.connected &&
        _foreground &&
        _tabVisible &&
        _routeCurrent;
  }

  void _syncSampling() {
    final session = _session;
    if (session == null) return;
    if (_shouldSample) {
      session.monitor.start();
    } else {
      session.monitor.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final session = _session;
    if (session == null || session.phase != TerminalPhase.connected) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            theme: theme,
            l10n: l10n,
            status: _SectionStatus.idle,
            interval: null,
            onRefresh: null,
          ),
          const SizedBox(height: 10),
          _NoticePanel(
            theme: theme,
            icon: Icons.monitor_heart_outlined,
            text: l10n.serverLoadIdleHint,
          ),
        ],
      );
    }
    final monitor = session.monitor;
    return ListenableBuilder(
      listenable: monitor,
      builder: (context, _) {
        final hasMetrics = monitor.metrics != null;
        final status = monitor.status;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              theme: theme,
              l10n: l10n,
              // 标题行的状态只说「现在在做什么」；采样中与「失败且没有数据」
              // 由下面的面板说明，不在这里重复一遍。
              status: switch (status) {
                ServerMonitorStatus.unsupported => _SectionStatus.unsupported,
                ServerMonitorStatus.failed when hasMetrics =>
                  _SectionStatus.failed,
                _ => hasMetrics ? _SectionStatus.live : _SectionStatus.idle,
              },
              interval: monitor.interval,
              onRefresh: status == ServerMonitorStatus.unsupported
                  ? null
                  : () => monitor.refresh(),
            ),
            const SizedBox(height: 10),
            if (status == ServerMonitorStatus.unsupported)
              _NoticePanel(
                theme: theme,
                icon: Icons.monitor_heart_outlined,
                text: l10n.serverLoadUnsupported,
              )
            else if (!hasMetrics)
              _NoticePanel(
                theme: theme,
                icon: status == ServerMonitorStatus.failed
                    ? Icons.error_outline_rounded
                    : Icons.hourglass_empty_rounded,
                text: status == ServerMonitorStatus.failed
                    ? l10n.serverLoadFailed
                    : l10n.serverLoadLoading,
                action: status == ServerMonitorStatus.failed
                    ? _RetryButton(
                        l10n: l10n,
                        onPressed: () => monitor.refresh(),
                      )
                    : null,
              )
            else
              _MetricsBody(
                server: widget.server,
                metrics: monitor.metrics!,
                history: monitor.history,
              ),
          ],
        );
      },
    );
  }
}

enum _SectionStatus { idle, live, failed, unsupported }

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.theme,
    required this.l10n,
    required this.status,
    required this.interval,
    required this.onRefresh,
  });

  final ThemeData theme;
  final AppLocalizations l10n;
  final _SectionStatus status;
  final Duration? interval;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final dotColor = switch (status) {
      _SectionStatus.live => theme.statusColor(ServerStatus.connected),
      _SectionStatus.failed => theme.statusColor(ServerStatus.error),
      _ => theme.secondaryText,
    };
    final statusText = switch (status) {
      _SectionStatus.live => l10n.serverLoadLive(interval?.inSeconds ?? 0),
      _SectionStatus.failed => l10n.serverLoadFailed,
      _SectionStatus.unsupported => l10n.serverLoadUnsupported,
      _SectionStatus.idle => null,
    };
    return Row(
      children: [
        Text(
          l10n.serverLoad,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: theme.secondaryText,
          ),
        ),
        const SizedBox(width: 10),
        if (statusText != null) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: theme.secondaryText),
            ),
          ),
        ],
        const Spacer(),
        if (onRefresh != null)
          IconButton(
            tooltip: l10n.serverLoadRefresh,
            onPressed: onRefresh,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            iconSize: 16,
            icon: Icon(Icons.refresh_rounded, color: theme.secondaryText),
          ),
      ],
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.l10n, required this.onPressed});

  final AppLocalizations l10n;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 30),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(l10n.serverLoadRetry),
    );
  }
}

/// 未连接 / 采样中 / 不支持时的说明面板：与概览上的卡片同一套底色与描边。
class _NoticePanel extends StatelessWidget {
  const _NoticePanel({
    required this.theme,
    required this.icon,
    required this.text,
    this.action,
  });

  final ThemeData theme;
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: theme.panelBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.hairline),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.secondaryText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.80),
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// 有数据时的正文：系统信息卡 + 四张指标卡。
class _MetricsBody extends StatelessWidget {
  const _MetricsBody({
    required this.server,
    required this.metrics,
    required this.history,
  });

  final SshServer server;
  final ServerMetrics metrics;
  final List<MetricPoint> history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final cpu = _values(history, (point) => point.cpuPercent);
    final memory = _values(history, (point) => point.memoryPercent);
    final rx = _values(history, (point) => point.rxRate);
    final tx = _values(history, (point) => point.txRate);
    final netMax = _autoMax([...rx, ...tx]);
    final accent = theme.colorScheme.primary;
    final cards = <Widget>[
      _MetricCard(
        theme: theme,
        title: l10n.metricCpu,
        color: accent,
        value: _percentText(metrics.cpuPercent),
        detail: metrics.cpuCores == null
            ? null
            : l10n.metricCores(metrics.cpuCores!),
        chart: MetricSparkline(
          series: [MetricSeries(values: cpu, color: accent, fill: true)],
          maxValue: 100,
          hint: l10n.metricWaiting,
          theme: theme,
        ),
      ),
      _MetricCard(
        theme: theme,
        title: l10n.metricMemory,
        color: theme.colorScheme.tertiary,
        value: _percentText(metrics.memoryPercent),
        detail: _usedOfTotal(metrics.memoryUsedBytes, metrics.memoryTotalBytes),
        chart: MetricSparkline(
          series: [
            MetricSeries(
              values: memory,
              color: theme.colorScheme.tertiary,
              fill: true,
            ),
          ],
          maxValue: 100,
          hint: l10n.metricWaiting,
          theme: theme,
        ),
      ),
      _MetricCard(
        theme: theme,
        title: l10n.metricDisk,
        color: theme.statusColor(ServerStatus.connecting),
        value: _percentText(metrics.diskPercent),
        // 已用 / 总量在环形图的图例里，顶部只留百分比与挂载点，不重复一遍。
        trailing: metrics.diskMount,
        chart: _DiskGauge(
          theme: theme,
          percent: metrics.diskPercent,
          usedBytes: metrics.diskUsedBytes,
          totalBytes: metrics.diskTotalBytes,
          l10n: l10n,
          color: theme.statusColor(ServerStatus.connecting),
        ),
      ),
      _MetricCard(
        theme: theme,
        title: l10n.metricNetwork,
        color: accent,
        value: metrics.rxRate == null
            ? null
            : '↓ ${formatRate(metrics.rxRate!)}',
        detail: metrics.txRate == null
            ? null
            : '↑ ${formatRate(metrics.txRate!)}',
        chart: MetricSparkline(
          series: [
            MetricSeries(values: rx, color: accent),
            MetricSeries(
              values: tx,
              color: theme.statusColor(ServerStatus.connected),
            ),
          ],
          maxValue: netMax,
          hint: l10n.metricWaiting,
          theme: theme,
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SystemInfoCard(
          theme: theme,
          l10n: l10n,
          server: server,
          metrics: metrics,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 4
                : constraints.maxWidth >= 520
                ? 2
                : 1;
            const gap = 12.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final card in cards) SizedBox(width: width, child: card),
              ],
            );
          },
        ),
      ],
    );
  }

  static List<double?> _values(
    List<MetricPoint> points,
    double? Function(MetricPoint) select,
  ) => [for (final point in points) select(point)];

  static double? _autoMax(List<double?> values) {
    var max = 0.0;
    for (final value in values) {
      if (value != null && value > max) max = value;
    }
    // 下限 4 KB/s：空闲链路上速率在几十字节 / 秒抖动，按峰值归一化会
    // 把噪声放大成「满屏锯齿」；给个地板值让空闲时是一条贴底的平线。
    return max < 4096 ? 4096 : max * 1.2;
  }

  static String? _percentText(double? value) =>
      value == null ? null : '${value.round()}%';

  static String? _usedOfTotal(int? used, int? total) {
    if (used == null || total == null) return null;
    return '${formatBytes(used)} / ${formatBytes(total)}';
  }
}

class _SystemInfoCard extends StatelessWidget {
  const _SystemInfoCard({
    required this.theme,
    required this.l10n,
    required this.server,
    required this.metrics,
  });

  final ThemeData theme;
  final AppLocalizations l10n;
  final SshServer server;
  final ServerMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final system = [?metrics.osName, ?metrics.kernel].join(' ');
    final load = _loadText(metrics);
    final items = <(String, String?)>[
      (l10n.systemHostname, metrics.hostname ?? server.host),
      (l10n.systemOs, system.isEmpty ? null : system),
      (l10n.systemArch, metrics.arch),
      (
        l10n.systemUptime,
        metrics.uptime == null ? null : _formatUptime(l10n, metrics.uptime!),
      ),
      (l10n.systemLoadAverage, load),
      (
        l10n.systemCpuCores,
        metrics.cpuCores == null ? null : '${metrics.cpuCores}',
      ),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: theme.panelBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.systemInfo,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: theme.secondaryText,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 26,
            runSpacing: 11,
            children: [
              for (final item in items)
                if (item.$2 != null && item.$2!.isNotEmpty)
                  _InfoItem(theme: theme, label: item.$1, value: item.$2!),
            ],
          ),
        ],
      ),
    );
  }

  static String? _loadText(ServerMetrics metrics) {
    final values = [metrics.load1, metrics.load5, metrics.load15];
    if (values.every((value) => value == null)) return null;
    return values
        .map((value) => value == null ? '-' : value.toStringAsFixed(2))
        .join('  ');
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({
    required this.theme,
    required this.label,
    required this.value,
  });

  final ThemeData theme;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10.5, color: theme.secondaryText),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// 指标卡：标题 + 主数值 + 副说明 + 图表区。
class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.theme,
    required this.title,
    required this.color,
    required this.value,
    required this.chart,
    this.detail,
    this.trailing,
  });

  final ThemeData theme;
  final String title;
  final Color color;
  final String? value;
  final String? detail;
  final String? trailing;
  final Widget chart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: theme.panelBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: theme.secondaryText,
                ),
              ),
              const Spacer(),
              if (trailing != null && trailing!.isNotEmpty)
                Flexible(
                  child: Text(
                    trailing!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: theme.secondaryText,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value ?? '--',
                style: TextStyle(
                  fontSize: 21,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (detail != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.secondaryText,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(height: 54, child: chart),
        ],
      ),
    );
  }
}

/// 图表用的一条折线。
@immutable
class MetricSeries {
  const MetricSeries({
    required this.values,
    required this.color,
    this.fill = false,
  });

  final List<double?> values;
  final Color color;

  /// 是否在线下铺一层渐变面积（单指标卡片用，双线网络图不铺以免互相盖住）。
  final bool fill;
}

/// 迷你折线图：百分比的 CPU / 内存、字节速率的网络都用它。
///
/// 采样点不足两个时显示占位文案——只画一个点既看不出趋势，
/// 也容易被误读成「负载贴底」。
class MetricSparkline extends StatelessWidget {
  const MetricSparkline({
    super.key,
    required this.series,
    required this.theme,
    required this.hint,
    this.maxValue,
  });

  final List<MetricSeries> series;
  final ThemeData theme;
  final String hint;

  /// 纵轴上限；为空时按数据峰值自动取值（网络速率）。
  final double? maxValue;

  @override
  Widget build(BuildContext context) {
    final points = series.fold<int>(0, (count, item) {
      final visible = item.values.where((value) => value != null).length;
      return visible > count ? visible : count;
    });
    if (points < 2) {
      return Center(
        child: Text(
          hint,
          style: TextStyle(fontSize: 11, color: theme.secondaryText),
        ),
      );
    }
    return RepaintBoundary(
      child: CustomPaint(
        painter: _SparklinePainter(
          series: series,
          maxValue: maxValue,
          gridColor: theme.hairline,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.series,
    required this.maxValue,
    required this.gridColor,
  });

  final List<MetricSeries> series;
  final double? maxValue;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final top = 2.0;
    final bottom = size.height - 2;
    final chartHeight = bottom - top;
    final max = maxValue ?? _autoMax();
    if (max <= 0 || chartHeight <= 0) return;

    // 横向基线：两条淡线足够读出「画到哪儿了」，再多就成了网格噪声。
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final fraction in const [0.5, 1.0]) {
      final y = top + chartHeight * fraction;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (final item in series) {
      final path = Path();
      final fillPath = Path();
      var started = false;
      var lastPoint = Offset.zero;
      for (var i = 0; i < item.values.length; i++) {
        final value = item.values[i];
        if (value == null) {
          started = false;
          continue;
        }
        final x = item.values.length == 1
            ? size.width
            : size.width * i / (item.values.length - 1);
        final normalized = (value / max).clamp(0.0, 1.0);
        final y = bottom - chartHeight * normalized;
        final point = Offset(x, y);
        if (!started) {
          path.moveTo(point.dx, point.dy);
          fillPath.moveTo(point.dx, bottom);
          fillPath.lineTo(point.dx, point.dy);
          started = true;
        } else {
          // 二次贝塞尔用中点做控制点：折线会显出采样抖动的毛刺，
          // 平滑后的趋势线在这个尺寸上更耐看，也不会越过 0…max。
          final midX = (lastPoint.dx + point.dx) / 2;
          path.cubicTo(midX, lastPoint.dy, midX, point.dy, point.dx, point.dy);
          fillPath.cubicTo(
            midX,
            lastPoint.dy,
            midX,
            point.dy,
            point.dx,
            point.dy,
          );
        }
        lastPoint = point;
      }
      fillPath.lineTo(lastPoint.dx, bottom);
      fillPath.close();

      if (item.fill) {
        final fillPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              item.color.withValues(alpha: 0.22),
              item.color.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromLTWH(0, top, size.width, chartHeight));
        canvas.drawPath(fillPath, fillPaint);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = item.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      // 末端圆点：一眼看出「最新值在哪」。
      if (lastPoint != Offset.zero) {
        canvas.drawCircle(lastPoint, 2.4, Paint()..color = item.color);
      }
    }
  }

  double _autoMax() {
    var max = 0.0;
    for (final item in series) {
      for (final value in item.values) {
        if (value != null && value > max) max = value;
      }
    }
    return max <= 0 ? 1 : max;
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) {
    if (oldDelegate.maxValue != maxValue) return true;
    if (oldDelegate.gridColor != gridColor) return true;
    if (oldDelegate.series.length != series.length) return true;
    for (var i = 0; i < series.length; i++) {
      if (oldDelegate.series[i].values != series[i].values) return true;
      if (oldDelegate.series[i].color != series[i].color) return true;
    }
    return false;
  }
}

/// 磁盘用的环形占用图：磁盘容量变化慢，画时间序列几乎是一条直线，
/// 环形刻度更能说清「已经用了多少」。
class _DiskGauge extends StatelessWidget {
  const _DiskGauge({
    required this.theme,
    required this.percent,
    required this.usedBytes,
    required this.totalBytes,
    required this.l10n,
    required this.color,
  });

  final ThemeData theme;
  final double? percent;
  final int? usedBytes;
  final int? totalBytes;
  final AppLocalizations l10n;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = ((percent ?? 0) / 100).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 54,
          height: 54,
          child: CustomPaint(
            painter: _RingPainter(
              fraction: fraction,
              color: color,
              trackColor: theme.hairline,
            ),
            child: Center(
              child: Text(
                percent == null ? '--' : '${percent!.round()}%',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LegendRow(
                theme: theme,
                label: l10n.metricUsed,
                value: usedBytes == null ? '--' : formatBytes(usedBytes!),
                color: color,
              ),
              const SizedBox(height: 5),
              _LegendRow(
                theme: theme,
                label: l10n.metricTotal,
                value: totalBytes == null ? '--' : formatBytes(totalBytes!),
                color: theme.secondaryText,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.theme,
    required this.label,
    required this.value,
    required this.color,
  });

  final ThemeData theme;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 10.5, color: theme.secondaryText),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.color,
    required this.trackColor,
  });

  final double fraction;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - 7) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    if (fraction <= 0) return;
    canvas.drawArc(
      rect,
      -1.5707963,
      6.2831853 * fraction,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}

/// 时长文案：天 / 小时 / 分钟三档，文案走 arb（中英各自成句）。
String _formatUptime(AppLocalizations l10n, Duration uptime) {
  final days = uptime.inDays;
  final hours = uptime.inHours % 24;
  final minutes = uptime.inMinutes % 60;
  if (days > 0) return l10n.uptimeDaysHours(days, hours);
  if (hours > 0) return l10n.uptimeHoursMinutes(hours, minutes);
  return l10n.uptimeMinutes(minutes);
}
