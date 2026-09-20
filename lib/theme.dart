import 'package:flutter/material.dart';

import 'models.dart';

/// 与 ZCode / Codex 类似的开发者工具配色：低饱和深灰 + 蓝色强调色。
abstract final class AppPalette {
  static const pageDark = Color(0xFF0F1114);
  static const panelDark = Color(0xFF171B21);
  static const terminalDark = Color(0xFF0A0C0F);

  static const pageLight = Color(0xFFF6F7F9);
  static const panelLight = Color(0xFFFFFFFF);

  // 状态色：深色取 GitHub dark 的亮色值，浅色取 GitHub light 的深色值。
  // 深色那组直接铺在白底上只有 2.5:1 左右（连非文字元素的 3:1 都不到），
  // 所以浅色主题必须换用为白底设计的深色值。
  static const success = Color(0xFF3FB950);
  static const warning = Color(0xFFD29922);
  static const danger = Color(0xFFF85149);
  static const idle = Color(0xFF8B949E);

  static const successLight = Color(0xFF1A7F37);
  static const warningLight = Color(0xFF9A6700);
  static const dangerLight = Color(0xFFCF222E);
  static const idleLight = Color(0xFF57606A);

  static const seed = Color(0xFF4C8DFF);
}

/// 面板 / 分隔线 / 悬浮等语义色的载体。
///
/// 这些颜色不能只按 [ThemeData.brightness] 现算：主题切换由 [AnimatedTheme]
/// 驱动，而 [ThemeData.lerp] 对 brightness 做的是 t < 0.5 的硬切换，现算值会在
/// 动画中点整体跳一下，看起来就是「卡顿」。放进 [ThemeExtension] 后由扩展自己
/// 的 [lerp] 插值，就能和 ColorScheme 一起逐帧平滑过渡。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.pageBackground,
    required this.panelBackground,
    required this.hairline,
    required this.hoverOverlay,
  });

  final Color pageBackground;
  final Color panelBackground;
  final Color hairline;
  final Color hoverOverlay;

  static const dark = AppColors(
    pageBackground: AppPalette.pageDark,
    panelBackground: AppPalette.panelDark,
    hairline: Color(0x14FFFFFF),
    hoverOverlay: Color(0x0DFFFFFF),
  );

  static const light = AppColors(
    pageBackground: AppPalette.pageLight,
    panelBackground: AppPalette.panelLight,
    hairline: Color(0x14000000),
    hoverOverlay: Color(0x07000000),
  );

  static AppColors of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  @override
  AppColors copyWith({
    Color? pageBackground,
    Color? panelBackground,
    Color? hairline,
    Color? hoverOverlay,
  }) {
    return AppColors(
      pageBackground: pageBackground ?? this.pageBackground,
      panelBackground: panelBackground ?? this.panelBackground,
      hairline: hairline ?? this.hairline,
      hoverOverlay: hoverOverlay ?? this.hoverOverlay,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      panelBackground: Color.lerp(panelBackground, other.panelBackground, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      hoverOverlay: Color.lerp(hoverOverlay, other.hoverOverlay, t)!,
    );
  }
}

/// 统一的面板 / 分隔线 / 悬浮等语义色，避免组件里散落硬编码颜色。
extension AppThemeX on ThemeData {
  /// 语义色板；ThemeData 未注册扩展时按亮度取常量兜底，取值永不抛错。
  AppColors get appColors => extension<AppColors>() ?? AppColors.of(brightness);

  Color get pageBackground => appColors.pageBackground;

  Color get panelBackground => appColors.panelBackground;

  Color get hairline => appColors.hairline;

  Color get hoverOverlay => appColors.hoverOverlay;

  /// 侧边栏整行入口（主机行、分组头、底部「设置」）的悬停底色。
  /// [hoverOverlay] 只有 2~5% 的灰度差，单独铺在整行上几乎看不出来；这一档
  /// 与图标按钮（Material 默认 8% onSurface）同强度，保证「能点」一眼可见。
  /// 这几个整行入口都走 [InkWell.hoverColor]，只画一层；不要再叠自绘底色，
  /// 两层错位会在行的两侧露出一圈深浅不一的边。
  Color get rowHover => colorScheme.onSurface.withValues(alpha: 0.08);

  Color get selectedOverlay => colorScheme.primary.withValues(
    alpha: brightness == Brightness.dark ? 0.20 : 0.12,
  );

  Color get secondaryText => colorScheme.onSurface.withValues(alpha: 0.62);

  Color statusColor(ServerStatus status) {
    final dark = brightness == Brightness.dark;
    return switch (status) {
      ServerStatus.connected =>
        dark ? AppPalette.success : AppPalette.successLight,
      ServerStatus.connecting =>
        dark ? AppPalette.warning : AppPalette.warningLight,
      ServerStatus.error => dark ? AppPalette.danger : AppPalette.dangerLight,
      ServerStatus.idle => dark ? AppPalette.idle : AppPalette.idleLight,
    };
  }
}

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  /// 按亮度缓存：构建 ThemeData 开销不小，主题切换是低频操作，
  /// 命中缓存即可零成本重建 MaterialApp。
  ///
  /// 界面字体固定用平台默认（不提供自定义）：界面字体是原生观感的一部分，
  /// 而中文字形只有系统字体覆盖得全；需要统一的等宽字形的是终端，不是界面。
  static final _cache = <Brightness, ThemeData>{};

  /// 清掉缓存。只给测试用：`ThemeData` 里含平台相关的 visualDensity 等取值，
  /// 同一进程里先建的用例会把结果固化给后面的用例，几何断言因此会随
  /// 用例顺序漂移（见 test/widget_test.dart 的说明）。
  @visibleForTesting
  static void resetCache() => _cache.clear();

  static ThemeData _build(Brightness brightness) =>
      _cache.putIfAbsent(brightness, () => _create(brightness));

  static ThemeData _create(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colors = AppColors.of(brightness);
    final scheme = ColorScheme.fromSeed(
      seedColor: AppPalette.seed,
      brightness: brightness,
    );
    final hairline = colors.hairline;

    final data = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      // 注册语义色扩展，主题切换时随 ColorScheme 一起插值（见 AppColors）。
      extensions: [colors],
      scaffoldBackgroundColor: colors.pageBackground,
      splashFactory: NoSplash.splashFactory,
      dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        minThumbLength: 40,
        radius: const Radius.circular(3),
        thumbColor: WidgetStatePropertyAll(
          scheme.onSurface.withValues(alpha: 0.22),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurface.withValues(alpha: 0.55),
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        // 标签栏与内容之间不再画横线：选中态的指示条已经界定了标签栏范围，
        // 多一根通栏 hairline 只会把内容区切成两块。
        dividerHeight: 0,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        // 选中 / 未选中的**字重必须一致**（只靠颜色 + 指示器区分选中态）：
        // 两者字重不同时 M3 的 TabBar 会用 AnimatedDefaultTextStyle 逐帧插值
        // 标签样式，每一帧的插值样式都会让标签段落重新排版，在本机
        // （Linux + Impeller）实测每次切换单帧阻塞 1.5~2.1s（release 构建
        // 同样复现，raster 仅 0~2ms，帧耗时全在布局阶段的 RenderParagraph
        // 上），表现就是「连上 SSH 后切三个 Tab 非常卡」；字重统一后同一
        // 路径单帧回落到 4~6ms。颜色插值本身不触发这个问题。
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppPalette.panelDark : AppPalette.panelLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFF232A33)
            : const Color(0xFF1F242C),
        contentTextStyle: const TextStyle(
          fontSize: 13,
          color: Color(0xFFE6EDF3),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? AppPalette.panelDark : AppPalette.panelLight,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        position: PopupMenuPosition.over,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: TextStyle(fontSize: 13, color: scheme.onSurface),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A313B) : const Color(0xFF2B313A),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(fontSize: 11.5, color: Color(0xFFE6EDF3)),
        waitDuration: const Duration(milliseconds: 450),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          // 分段控件与设置行的标签同一套字号（默认 labelLarge 的 14 偏大）。
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
          ),
          // 圆角与输入框 / 下拉统一为 10（M3 默认是球场形），
          // 高度沿用默认的 40，正对齐同排的下拉框。
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
          ),
          // 纯文字分段的段内边距：语言那三段并排时，默认的 12/16 会把
          // 「English」在窄屏上挤成两行。带图标的分段由框架自行计算内边距，
          // 不受这里影响（见 SegmentedButton 对 icon 分支的处理）。
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        isDense: true,
        filled: true,
        // 标签一律浮在边框上：默认 auto 会在「空且未聚焦」时把标签缩进
        // 框内当占位符，与已聚焦 / 已有值的字段（标签在边框上）同屏时
        // 一半在上一半在下，观感散架。统一浮起后框内只剩提示文案。
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.primary, width: 1.2),
        ),
      ),
    );
    return data;
  }
}
