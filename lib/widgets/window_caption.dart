import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme.dart';

/// 自绘窗口标题条高度：顶部这一条「标题区」的高度。
/// 既是窗口按钮所在行的高度，也是侧边栏头部与内容区顶部对齐的基准。
/// 取 48 而不是贴着图标的 40：两侧内容与窗口上下沿都留出约 9px 呼吸感，
/// 视觉上才不像「贴边糊上去的」。
const double kWindowCaptionHeight = 48.0;

/// 窗口按钮（最小化 / 最大化 / 关闭）的命中区尺寸。
/// 比字形大一圈，悬停时整块变色，鼠标也更容易点中。
const Size kWindowCaptionButtonSize = Size(46, 32);

/// 窗口按钮组与窗口右边缘的间距：与面板的左右内边距同一套节奏。
const double kWindowCaptionButtonInset = 8.0;

/// 标题条左侧内容与窗口左边缘的间距，和侧边栏头部同一套内边距。
const double kWindowCaptionLeadingInset = 12.0;

/// 无论左侧内容多宽都要留出的拖拽区宽度：窗口得拖得动。
const double _minDragWidth = 48.0;

/// 是否使用 Flutter 自绘标题条（Windows / Linux 隐藏原生标题栏后）。
/// macOS 由原生红绿灯承担同样职责，移动端与 web 无窗口概念。
bool get usesCustomWindowCaption {
  if (kIsWeb) return false;
  final platform = defaultTargetPlatform;
  return platform == TargetPlatform.windows || platform == TargetPlatform.linux;
}

/// 是否为 macOS 这类「红绿灯浮在内容左上角」的平台。
///
/// 原生侧（见 MainFlutterWindow）把标题栏透明化、并用空工具栏把顶部条带
/// 撑到 52pt：红绿灯悬在条带内（中心 y≈27pt），条带以下才是普通可交互
/// 内容。布局上顶部一行要与红绿灯齐平，其余内容从条带之下排起。
bool get usesFloatingTrafficLights {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.macOS;
}

/// 内容区顶部避让量。
///
/// Windows/Linux 的自绘标题条已经是内容区里的真实一行（见 [WindowCaptionBar]），
/// 垂直空间被它占掉，内容不需要再避让；只有 macOS 的红绿灯是浮在内容上方的，
/// 才必须留出 [kWindowCaptionHeight]。
double windowTopInset(double fallback) =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
    ? kWindowCaptionHeight
    : fallback;

/// 把一块区域变成窗口拖拽热区，供自绘标题条与侧边栏头部这类「空白也能拖」的
/// 地方复用。只接管拖拽：子控件里的点击、悬停照旧走正常手势竞技。
class WindowDragRegion extends StatelessWidget {
  const WindowDragRegion({super.key, required this.child, this.onDoubleTap});

  final Widget child;

  /// 双击动作：标题条传「最大化 / 还原」，侧边栏头部等次要区域可不传。
  final GestureTapCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    if (!usesCustomWindowCaption) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: onDoubleTap,
      child: child,
    );
  }
}

/// Windows/Linux 的自绘窗口标题条：右侧最小化/最大化/关闭，其余是拖拽热区。
///
/// 它是详情面板里的**真实一行**（由详情面板自己拼在顶部），不是浮在内容
/// 之上的浮层——这样侧边栏才能整块顶到窗口最上沿，详情面板的头部（服务器名、
/// 状态、操作按钮）也能直接排进这一行，内容整体上移，顶部不再多出一条空白。
///
/// [leading] 排在拖拽热区**之外**：它是普通控件，点击不会被拖拽手势吞掉；
/// 也因此详情面板的操作按钮都放在左侧，不会和右端的窗口按钮抢位置。
class WindowCaptionBar extends StatefulWidget {
  const WindowCaptionBar({super.key, this.leading});

  /// 标题条左侧内容：详情面板的头部，或收起侧边栏后的展开按钮。
  final Widget? leading;

  @override
  State<WindowCaptionBar> createState() => _WindowCaptionBarState();
}

class _WindowCaptionBarState extends State<WindowCaptionBar>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    // 非 Windows/Linux 不渲染标题条；且 macOS 上引擎启动早期调用
    // isMaximized，插件原生侧 mainWindow 未就绪强解包会崩溃，必须门控。
    if (!usesCustomWindowCaption) return;
    windowManager.addListener(this);
    _syncMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted && maximized != _maximized) {
      setState(() => _maximized = maximized);
    }
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  void _toggleMaximize() {
    if (_maximized) {
      windowManager.unmaximize();
    } else {
      windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!usesCustomWindowCaption) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final leading = widget.leading;
    return SizedBox(
      height: kWindowCaptionHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 左侧内容最多占到这里：给窗口按钮和一段可拖拽的空白让路。
          final maxLeading =
              constraints.maxWidth -
              kWindowCaptionButtonSize.width * 3 -
              kWindowCaptionButtonInset -
              kWindowCaptionLeadingInset -
              _minDragWidth;
          return Row(
            // stretch：拖拽热区没有子控件，只有被撑满整条高度才收得到手势；
            // 用默认的 center，它会被压成 0 高，整条标题栏就只剩右侧按钮可点。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (leading != null)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.max(0, maxLeading),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: kWindowCaptionLeadingInset,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: leading,
                    ),
                  ),
                ),
              // 空白处吞掉点击与拖拽，语义与系统标题栏一致。
              Expanded(
                child: WindowDragRegion(
                  key: const ValueKey('window-caption-drag'),
                  onDoubleTap: _toggleMaximize,
                  child: const SizedBox.expand(),
                ),
              ),
              // 按钮组整体从右边缘内缩，悬停块不会顶到窗口角上；
              // 外层 stretch + 内层 Row 默认 center，按钮在标题区里垂直居中。
              Padding(
                padding: const EdgeInsets.only(
                  right: kWindowCaptionButtonInset,
                ),
                child: Row(
                  children: [
                    _CaptionButton(
                      icon: Icons.minimize,
                      // 最小化只画一根细横线，13 与系统标题栏的字形粗细接近。
                      iconSize: 13,
                      tooltip: l10n.windowMinimize,
                      onTap: windowManager.minimize,
                    ),
                    _CaptionButton(
                      icon: _maximized
                          ? Icons.filter_none_rounded
                          : Icons.crop_square_rounded,
                      iconSize: 12,
                      tooltip: _maximized
                          ? l10n.windowRestore
                          : l10n.windowMaximize,
                      onTap: _toggleMaximize,
                    ),
                    _CaptionButton(
                      icon: Icons.close_rounded,
                      iconSize: 14,
                      tooltip: l10n.windowClose,
                      danger: true,
                      onTap: windowManager.close,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.iconSize,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// 字形尺寸：窗口按钮的字号比正文小得多，按系统标题栏的观感逐个定。
  final double iconSize;

  /// 关闭按钮悬停时铺满 danger 色，贴近系统标题栏的关闭语义。
  final bool danger;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _hovered || _pressed;
    // 关闭按钮悬停即整块铺红；其余按钮用与 M3 图标按钮一致的浅色浮层
    // （hoverOverlay 太淡，做标题栏反馈不够明确），按下再压深一档。
    final Color background;
    if (widget.danger) {
      background = _pressed
          ? Color.alphaBlend(
              Colors.black.withValues(alpha: 0.16),
              AppPalette.danger,
            )
          : (_hovered ? AppPalette.danger : Colors.transparent);
    } else {
      background = theme.colorScheme.onSurface.withValues(
        alpha: _pressed
            ? 0.14
            : _hovered
            ? 0.08
            : 0,
      );
    }
    final iconColor = widget.danger && active
        ? Colors.white
        : (_hovered ? theme.colorScheme.onSurface : theme.secondaryText);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            width: kWindowCaptionButtonSize.width,
            height: kWindowCaptionButtonSize.height,
            // 无 alignment 时 Container 把紧约束直接传给 Icon，
            // 字形会被画在左上角而不是居中，三个按钮看起来歪斜。
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(widget.icon, size: widget.iconSize, color: iconColor),
          ),
        ),
      ),
    );
  }
}
