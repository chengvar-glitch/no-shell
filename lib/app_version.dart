import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 版本号的兜底值（形如 `x.y.z` 或预发布的 `x.y.z-标签`，不含构建号）。
///
/// 它**不是**版本号的来源，只是读不到平台信息时的垫底：真正的版本号由
/// [loadAppVersion] 在启动时从宿主包信息读出。发版时这个值与
/// `pubspec.yaml` 的 `version:` 一起改——两者不一致时以 pubspec 为准
/// （那才是实际打进包里的），这里只是「万一平台通道不可用」的显示值。
const String kFallbackAppVersion = '4.4.0';

/// 当前版本号（`x.y.z`，不含构建号）；界面展示与版本比较都用它。
///
/// 之所以是可变全局而不是常量：`package_info_plus` 是异步的平台通道，
/// 而调用方（「关于」对话框、设置页信息行）都在同步的 `build` 里。
/// 启动时 [_load] 写一次，此后只读；测试可直接赋值来造版本场景。
String appVersion = kFallbackAppVersion;

/// 启动时读出真实版本号；平台通道不可用（组件测试、嵌入场景）时保留兜底值。
///
/// 读不到必须留下痕迹：静默退回常量，正是「界面长期显示 4.0.1、
/// 而 pubspec 早已 4.1.3」这个 bug 当初没被发现的原因。
Future<void> loadAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final version = info.version.trim();
    if (version.isNotEmpty) appVersion = version;
  } catch (error) {
    if (kDebugMode) {
      debugPrint('app_version: 读不到包信息，版本号退回 $kFallbackAppVersion（$error）');
    }
  }
}
