package com.noshell

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 除了标准的 Flutter 宿主，只多做一件事：把「后台保活」的开关经
 * [KEEP_ALIVE_CHANNEL] 接到 [SessionKeepAliveService]（Dart 侧见
 * `lib/ssh/session_keep_alive.dart`）。
 *
 * 通道方法：
 * - `start`（参数 `title` / `body`，已本地化）：拉起或更新前台服务；
 * - `stop`：收掉前台服务。
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "NoShell"
        private const val KEEP_ALIVE_CHANNEL = "com.noshell/keep_alive"
        private const val REQUEST_NOTIFICATIONS = 0x5E01
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KEEP_ALIVE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val title = call.argument<String>("title").orEmpty()
                        val body = call.argument<String>("body").orEmpty()
                        requestNotificationPermissionIfNeeded()
                        try {
                            SessionKeepAliveService.start(this, title, body)
                            result.success(true)
                        } catch (error: Exception) {
                            // Android 12+ 禁止从后台启动前台服务：自动重连可能
                            // 正好发生在应用已在后台时，这一下会抛
                            // ForegroundServiceStartNotAllowedException
                            // （IllegalStateException 的子类）；Android 14+ 类型 /
                            // 权限对不上时抛 SecurityException。两种情况都如实
                            // 回报 false——保活拉不起来不该把重连本身带崩，
                            // Dart 侧会留着状态等下一次会话通知重试。
                            Log.w(TAG, "keep-alive start rejected", error)
                            result.success(false)
                        }
                    }
                    "stop" -> {
                        SessionKeepAliveService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Android 13 起常驻通知要用户授权。拒绝也不影响前台服务本身——通知被
     * 压掉，服务照跑（系统会在「应用 → 正在运行」里如实列出它）；所以这里
     * 只是「顺手问一次」，不问的话用户连自己的连接被保活都不知道。
     */
    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) return
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
    }
}
