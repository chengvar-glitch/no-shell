import 'package:flutter/material.dart';

/// 应用内品牌标：直接用启动图标本身（`icon/art.svg` → `render.py` 生成的 PNG），
/// 侧边栏头部、设置弹窗头部与「关于」共用同一份，避免各处再画一遍
/// 「渐变块 + 终端字形」，在应用里看起来像通用占位图标而不是这个应用。
///
/// 图标自带圆角与底板，这里不再叠加圆角裁剪或描边，免得二次裁切。
final class AppIconMark extends StatelessWidget {
  const AppIconMark({super.key, this.size = 30});

  /// 显示边长（逻辑像素）。
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'icon/png/icon-128.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
  }
}
