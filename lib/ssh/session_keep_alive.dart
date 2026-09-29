import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'session_manager.dart';

/// 本次运行是否具备「后台保活」能力：只有 Android 有前台服务这条路。
///
/// iOS 没有等价机制——`beginBackgroundTask` 只买得到几十秒收尾时间，
/// `BGProcessingTask` 是机会式的、不能持续跑；桌面与 web 也没有「后台被
/// 系统回收」这回事。所以这里为 false 时整条链路不接线，平台通道一次都不碰。
bool get keepAliveSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// 平台侧保活开关。真机实现见 [PlatformKeepAliveHost]，测试注入假实现。
abstract interface class KeepAliveHost {
  /// 拉起（或就地更新）保活服务；[title] / [body] 是已本地化的通知文案。
  ///
  /// 返回平台是否真的把它拉起来了：Android 12+ 禁止从后台启动前台服务，
  /// 自动重连正好发生在后台时这一下会被系统拒绝（见 [SessionKeepAlive._sync]
  /// 的重试约定）。
  Future<bool> start({required String title, required String body});

  /// 收掉保活服务。
  Future<void> stop();
}

/// 真机实现：走 `MainActivity` 注册的 MethodChannel，落到
/// `SessionKeepAliveService`（前台服务 + 常驻通知 + partial wakelock）。
final class PlatformKeepAliveHost implements KeepAliveHost {
  const PlatformKeepAliveHost();

  static const MethodChannel _channel = MethodChannel('com.noshell/keep_alive');

  @override
  Future<bool> start({required String title, required String body}) async {
    try {
      final started = await _channel.invokeMethod<bool>('start', {
        'title': title,
        'body': body,
      });
      return started ?? false;
    } on PlatformException catch (error) {
      // 通道在、调用失败（权限 / 类型对不上等）。保活起不来不该影响会话本身。
      debugPrint('keep-alive start failed: ${error.code} ${error.message}');
      return false;
    } on MissingPluginException {
      // 宿主没有注册这份通道（非 Android 端误接线、或测试环境）。
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException catch (error) {
      debugPrint('keep-alive stop failed: ${error.code} ${error.message}');
    } on MissingPluginException {
      // 同 start：没有实现就没有要收的东西。
    }
  }
}

/// 把「有会话活着」翻成平台侧的前台服务开关。
///
/// 只在 **0 → 1 / 1 → 0** 那一刻打平台通道：会话层的通知很频繁（连上、断开、
/// 切当前会话都会通知），逐次转发只会反复刷同一条通知。
///
/// 构造即挂上监听，[dispose] 时摘掉并收服务。
final class SessionKeepAlive {
  SessionKeepAlive({
    required this.sessions,
    required this.texts,
    KeepAliveHost? host,
  }) : _host = host ?? const PlatformKeepAliveHost() {
    sessions.addListener(_sync);
  }

  final SessionManager sessions;

  /// 通知文案的取词回调。保活由会话层通知驱动，这里没有 `BuildContext`，
  /// 所以由持有语言偏好的应用根（`main.dart`）按当前语言生成。
  final ({String title, String body}) Function() texts;

  final KeepAliveHost _host;

  bool _running = false;

  /// 平台侧此刻是否已经被要求保持运行（测试与诊断用）。
  bool get isRunning => _running;

  /// 会话集合发生变化：需要保活就拉起，不需要就收掉。
  void _sync() {
    if (sessions.holdsLiveSessions) {
      if (_running) return;
      // 先记状态再发通道：通知是同步连发的，等 Future 回来再记会重复拉起。
      _running = true;
      unawaited(_start());
    } else {
      if (!_running) return;
      _running = false;
      unawaited(_host.stop());
    }
  }

  Future<void> _start() async {
    final text = texts();
    final started = await _host.start(title: text.title, body: text.body);
    // 拉不起来（Android 12+ 拒绝从后台启动前台服务）就把状态放回去：留着
    // true 等于把「没在保活」记成「已在保活」，下一次会话通知再试一次。
    // 期间会话若已全部关闭（_running 被 _sync 置回 false），不要覆盖它。
    if (!started && _running) _running = false;
  }

  void dispose() {
    sessions.removeListener(_sync);
    if (!_running) return;
    _running = false;
    unawaited(_host.stop());
  }
}
