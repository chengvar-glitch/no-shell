import 'package:flutter/widgets.dart';

/// 详情里「当前 Tab 是否可见」的共享通道。
///
/// 详情面板的 Tab 内容是常驻保活的（终端、SFTP 切走不销毁），因此组件
/// 不能靠 `initState` / `dispose` 判断自己还在不在屏幕上。概览页的服务器
/// 负载采样要跟着可见性起停——没人看的图表不该一直去远端跑命令——所以
/// Tab 外壳把当前可见性经这层 InheritedWidget 传下去。
///
/// 桌面端由 `_DetailTabView` 包装，移动端由 `_TabActivity` 包装；
/// 没套这一层的地方（测试、独立使用）默认为可见。
class TabVisibilityScope extends InheritedWidget {
  const TabVisibilityScope({
    super.key,
    required this.visible,
    required super.child,
  });

  final bool visible;

  /// 当前 Tab 是否可见；没有外层 scope 时视为可见。
  static bool visibleOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<TabVisibilityScope>()
          ?.visible ??
      true;

  @override
  bool updateShouldNotify(TabVisibilityScope oldWidget) =>
      oldWidget.visible != visible;
}
