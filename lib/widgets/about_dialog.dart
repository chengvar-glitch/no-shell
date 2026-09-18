import 'package:flutter/material.dart';

import 'window_caption.dart';

/// 「关于」对话框：内容与 [showAboutDialog] 一致，只是顺手把 macOS 上
/// 许可页那条 AppBar 的返回键从红绿灯底下挪出来。
///
/// 许可页由 [AboutDialog] 内部那个「查看许可」按钮经 `showLicensePage` 推出，
/// 外面插不进手；能插手的只有主题——`showLicensePage` 推路由时用
/// [InheritedTheme.capture] 把对话框这一层的主题原样带进许可页，所以在这里
/// 包一层带 [kMacOSTrafficLightsLeadingWidth] 的 [Theme]，许可页的 AppBar
/// 就跟着让开红绿灯。桌面骨架里也只有这条全屏路由自带 AppBar（侧边栏、
/// 详情面板、设置都是自己排的行），补在这一处就够了。
///
/// 非 macOS 原样弹 [AboutDialog]，与 [showAboutDialog] 行为完全一致——其他
/// 桌面端的标题栏由自绘标题条占着，返回键落在内容区里，没人遮挡。
void showAppAboutDialog({
  required BuildContext context,
  required String applicationName,
  required String applicationVersion,
  Widget? applicationIcon,
}) {
  showDialog<void>(
    context: context,
    builder: (context) {
      final dialog = AboutDialog(
        applicationName: applicationName,
        applicationVersion: applicationVersion,
        applicationIcon: applicationIcon,
      );
      if (!usesFloatingTrafficLights) return dialog;
      final theme = Theme.of(context);
      return Theme(
        data: theme.copyWith(
          appBarTheme: theme.appBarTheme.copyWith(
            leadingWidth: kMacOSTrafficLightsLeadingWidth,
          ),
        ),
        child: dialog,
      );
    },
  );
}
