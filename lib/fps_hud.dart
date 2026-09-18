// 开发自测专用的 FPS 悬浮表：release 构建整段被 tree-shake，用户包零残留。
// 启用方式：debug / profile 构建追加 --dart-define=NOSHELL_FPS_HUD=true。
// 文案刻意不经 AppLocalizations：这不是面向用户的功能，不进任何发布产物。
import 'dart:async';
import 'dart:ui' show FontFeature, FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 编译期总开关：release 恒为 false（!kReleaseMode 先短路），配合调用点的
/// `if (kFpsHudEnabled)` 常量分支，FpsHud 相关代码在用户包里一行不剩。
const bool kFpsHudEnabled =
    !kReleaseMode && bool.fromEnvironment('NOSHELL_FPS_HUD');

/// 60Hz 的一帧预算（16.6ms）；超它即视为 jank（丢一帧），与 DevTools 同口径。
const Duration kFpsFrameBudget = Duration(microseconds: 16600);

/// 帧率统计：订阅 [SchedulerBinding] 的帧耗时回调，滑动窗口内给均值与最差值。
///
/// 空闲时 Flutter 不产生帧（无输出、无动画就没有 vsync 提交），fps 为 null
/// 而不是 0——「没有帧」与「帧很慢」是两回事，混在一起会误读。
class FpsMeter {
  FpsMeter({this.windowSize = 120}) {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  /// 统计窗口帧数：约两秒的帧（60Hz）。
  final int windowSize;

  final _timings = <FrameTiming>[];

  void _onTimings(List<FrameTiming> timings) {
    _timings.addAll(timings);
    if (_timings.length > windowSize) {
      _timings.removeRange(0, _timings.length - windowSize);
    }
  }

  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  /// 测试专用：等价于引擎帧回调，走同一段窗口逻辑。
  @visibleForTesting
  void debugFeed(List<FrameTiming> timings) => _onTimings(timings);

  /// 窗口内可见帧率。帧数不足两帧（刚清空或空闲无帧）返回 null。
  ///
  /// 口径是相邻首帧与末帧的 vsyncStart 间隔除以帧数差：不受窗口残留影响，
  /// 中途掉帧（间隔变大）会把均值拉低，正是想要的语义。
  double? get fps {
    if (_timings.length < 2) return null;
    final first = _timings.first.timestampInMicroseconds(FramePhase.vsyncStart);
    final last = _timings.last.timestampInMicroseconds(FramePhase.vsyncStart);
    final spanUs = last - first;
    if (spanUs <= 0) return null;
    return (_timings.length - 1) * 1e6 / spanUs;
  }

  /// jank 帧数：totalSpan（vsync 到光栅完成的全程）超预算的帧。
  int get jankCount =>
      _timings.where((t) => t.totalSpan > kFpsFrameBudget).length;

  int get sampleCount => _timings.length;

  /// 最差帧的全程耗时；窗口为空返回 null。
  Duration? get worstSpan {
    if (_timings.isEmpty) return null;
    var worst = _timings.first.totalSpan;
    for (final t in _timings) {
      if (t.totalSpan > worst) worst = t.totalSpan;
    }
    return worst;
  }

  /// 窗口内最差的 UI 线程（build/layout/paint）耗时。
  Duration? get worstBuild {
    if (_timings.isEmpty) return null;
    var worst = _timings.first.buildDuration;
    for (final t in _timings) {
      if (t.buildDuration > worst) worst = t.buildDuration;
    }
    return worst;
  }

  /// 窗口内最差的光栅线程耗时。
  Duration? get worstRaster {
    if (_timings.isEmpty) return null;
    var worst = _timings.first.rasterDuration;
    for (final t in _timings) {
      if (t.rasterDuration > worst) worst = t.rasterDuration;
    }
    return worst;
  }

  /// 清空窗口（换测试场景时手动重置用）。
  void reset() => _timings.clear();
}

/// 悬浮表本体：半透明贴右下角，不接指针、自带 RepaintBoundary，
/// 每 500ms 刷新一次读数——不能逐帧重建，否则表自己就成了帧负载。
class FpsHud extends StatefulWidget {
  const FpsHud({super.key, this.meter});

  /// 测试注入用；缺省自建一个与 State 同生命周期的实例。
  final FpsMeter? meter;

  @override
  State<FpsHud> createState() => _FpsHudState();
}

class _FpsHudState extends State<FpsHud> {
  FpsMeter? _owned;
  Timer? _ticker;

  FpsMeter get _meter => widget.meter ?? _owned!;

  @override
  void initState() {
    super.initState();
    // 注入的 meter 生命周期归调用方；HUD 只负责自己新建的那个。
    // 若写成 `widget.meter ?? FpsMeter()`，注入实例会被误当成自有资产，
    // dispose 时连带注销对方的帧回调，调用方再注销一次就触发断言。
    _owned = widget.meter == null ? FpsMeter() : null;
    // 周期读数而非监听帧回调：HUD 若逐帧 setState，测得的正是它自己。
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() {});
      // 同步打一行到 stdout：无头取证用（终端宿主拿不到屏幕录制权限时，
      // 日志是唯一可靠的读数通道）。文件本身被 release 剔除，不影响用户。
      debugPrint(
        'FPSHUD ts=${DateTime.now().millisecondsSinceEpoch} '
        'fps=${_meter.fps?.toStringAsFixed(1) ?? '-'} '
        'jank=${_meter.jankCount}/${_meter.sampleCount} '
        'worst=${_ms(_meter.worstSpan)}ms '
        'b=${_ms(_meter.worstBuild)} r=${_ms(_meter.worstRaster)}',
      );
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _owned?.dispose();
    super.dispose();
  }

  String _ms(Duration? d) =>
      d == null ? '-' : (d.inMicroseconds / 1000).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final meter = _meter;
    final fps = meter.fps;
    final fpsLabel = fps == null ? '--' : fps.round().toString();
    // 无头取证用：home 路由之上是否压着路由（凭据 / 指纹弹窗）。
    final modal = ModalRoute.of(context)?.isCurrent == false;
    debugPrint('FPSHUD modal=$modal');
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomRight,
        child: RepaintBoundary(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'FPS $fpsLabel  jank ${meter.jankCount}/${meter.sampleCount}\n'
              'worst ${_ms(meter.worstSpan)}ms '
              '(b ${_ms(meter.worstBuild)} / r ${_ms(meter.worstRaster)})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                height: 1.35,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
