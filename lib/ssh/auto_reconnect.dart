/// 断线自动重连的退避节奏与计划快照，与平台无关（web 也要能编译）。
library;

/// 指数退避：第 [delayFor] 次尝试等 `initial × factor^(n-1)`，封顶 [max]。
/// 默认 2s → 4s → 8s → 16s → 32s → 60s（60s 起）——服务器重启的典型
/// 时间尺度是秒到分钟级，前期密集试探、后期放慢脚步，不打爆双方。
final class ReconnectBackoff {
  const ReconnectBackoff({
    this.initial = const Duration(seconds: 2),
    this.max = const Duration(seconds: 60),
    this.factor = 2,
  });

  /// 第一次尝试前等的时间；也是服务器刚掉线时最值得再敲一次门的间隔。
  final Duration initial;

  /// 退避上限：服务器长时间不回来时，重连不再继续放慢。
  final Duration max;

  /// 每多失败一次，间隔放大的倍数；必须大于 1，否则不构成退避。
  final double factor;

  /// 第 [attempt] 次尝试（从 1 计）之前要等多久。
  Duration delayFor(int attempt) {
    if (attempt <= 1) return initial;
    var delay = initial;
    for (var i = 1; i < attempt; i++) {
      final next = delay * factor;
      // 一旦到顶就不再乘：Duration 上限约 8.6 天，永久重试也不会溢出。
      if (next >= max) return max;
      delay = next;
    }
    return delay;
  }
}

/// 某台主机的待执行重连计划：第 [attempt] 次（从 1 计）将在
/// [delay] 之后发起。界面据此展示「将在 N 秒后重连」。
final class ReconnectPlan {
  const ReconnectPlan({required this.attempt, required this.delay});

  final int attempt;
  final Duration delay;

  @override
  bool operator ==(Object other) =>
      other is ReconnectPlan &&
      other.attempt == attempt &&
      other.delay == delay;

  @override
  int get hashCode => Object.hash(attempt, delay);
}
