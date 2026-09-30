package com.noshell

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 除了标准的 Flutter 宿主，只多做两件事：
 *
 * - 把「后台保活」的开关经 [KEEP_ALIVE_CHANNEL] 接到 [SessionKeepAliveService]
 *   （Dart 侧见 `lib/ssh/session_keep_alive.dart`）。通道方法：`start`
 *   （参数 `title` / `body`，已本地化）拉起或更新前台服务、`stop` 收掉它。
 * - 把「下载落到系统公共下载目录」经 [DownloadsChannel.CHANNEL] 接到 MediaStore
 *   （Dart 侧见 `lib/ssh/android_downloads_io.dart`），方法表与实现都在
 *   [DownloadsChannel] 里；存储权限的申请走本类（只有 Activity 能弹框），
 *   由 [requestStoragePermission] 转交给 DownloadsChannel。
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "NoShell"
        private const val KEEP_ALIVE_CHANNEL = "com.noshell/keep_alive"
        private const val REQUEST_NOTIFICATIONS = 0x5E01
        private const val REQUEST_STORAGE = 0x5E02
    }

    /** 正在等结果的存储权限申请（同时只会有一个：下载队列是串行的）。 */
    private var storageCallback: ((Boolean) -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DownloadsChannel.CHANNEL,
        ).setMethodCallHandler(DownloadsChannel(this))
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
     * 写公共「下载」目录所需的存储权限（Android 9 及以下才要）。
     *
     * 只在用户真的点了下载、且那台设备非它不可时才问：Android 10 起写下载目录
     * 经 MediaStore，本来就不需要任何存储权限，问一下只是白弹一个框。已授权
     * 时 [requestPermissions] 会立刻回调 granted，不会重复打扰。
     */
    fun requestStoragePermission(onResult: (Boolean) -> Unit) {
        // 新系统上这条权限不参与写入，直接算「有」——Dart 侧不必分版本。
        if (hasStoragePermission()) {
            onResult(true)
            return
        }
        if (storageCallback != null) {
            // 上一次还没回来（正常路径下不会发生）：先把它当作被拒，别让它永远挂着。
            storageCallback?.invoke(false)
        }
        storageCallback = onResult
        requestPermissions(
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            REQUEST_STORAGE,
        )
    }

    /** 写公共下载目录的权限是否已到手（Android 10+ 上这条不参与写入，算「有」）。 */
    fun hasStoragePermission(): Boolean =
        Build.VERSION.SDK_INT > Build.VERSION_CODES.P ||
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_STORAGE) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        storageCallback?.invoke(granted)
        storageCallback = null
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

    /**
     * Android 9 及以下那支下载落点的根目录；新系统上没有它的事（返回 null）。
     * [DownloadsChannel] 也用它判「这台设备还有没有 Direct path 这条路」。
     */
    fun legacyDownloadsDirectory(): String? {
        if (Build.VERSION.SDK_INT > Build.VERSION_CODES.P) return null
        if (Environment.getExternalStorageState() != Environment.MEDIA_MOUNTED) return null
        return Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS,
        ).absolutePath
    }
}
