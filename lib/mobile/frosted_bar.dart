import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 移动端毛玻璃顶栏：滚动内容从顶栏下穿过时被高斯模糊并叠半透明表面色，
/// 玻璃下缘再压一段渐隐（[FrostedBody] 自动叠加），避免与内容形成硬边。
///
/// 页面骨架需配合 `Scaffold(extendBodyBehindAppBar: true)` 使用，
/// 滚动列表的初始顶部内边距取 [topInset]。
class FrostedBar extends StatelessWidget implements PreferredSizeWidget {
  const FrostedBar({super.key, this.title, this.actions, this.bottom});

  final Widget? title;
  final List<Widget>? actions;

  /// 放进玻璃区的底部件（如详情页的 TabBar），一并参与毛玻璃模糊。
  final PreferredSizeWidget? bottom;

  /// 玻璃下缘渐隐条高度。
  static const double fadeHeight = 24;

  /// 顶栏总高（状态栏 + 工具栏 [+ bottom]），滚动列表的初始顶部内边距。
  static double topInset(BuildContext context, {PreferredSizeWidget? bottom}) {
    return MediaQuery.paddingOf(context).top +
        kToolbarHeight +
        (bottom?.preferredSize.height ?? 0);
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: AppBar(
          title: title,
          actions: actions,
          bottom: bottom,
          backgroundColor: Theme.of(context).colorScheme.surface
              .withValues(alpha: 0.55),
          // 磨砂感全部交给 BackdropFilter，去掉 M3 的滚动染色与阴影，
          // 保证玻璃观感不随滚动状态突变。
          forceMaterialTransparency: true,
        ),
      ),
    );
  }
}

/// 毛玻璃顶栏下的页面主体：内容全屏铺开、可从玻璃下穿过，
/// 玻璃下缘自动叠一段表面色渐隐。滚动列表的初始顶部内边距
/// 由调用方经 [FrostedBar.topInset] 塞进列表 padding。
class FrostedBody extends StatelessWidget {
  const FrostedBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          top: FrostedBar.topInset(context),
          left: 0,
          right: 0,
          height: FrostedBar.fadeHeight,
          child: const _FadeEdge(),
        ),
      ],
    );
  }
}

/// 玻璃下缘的渐隐遮罩：表面色从上到下渐变到透明，盖在滚动内容上方。
class _FadeEdge extends StatelessWidget {
  const _FadeEdge();

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [surface, surface.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
