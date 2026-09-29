package com.noshell

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * 有 SSH 会话时挂着的后台保活服务（由 Dart 侧 `SessionKeepAlive` 开关）。
 *
 * 为什么需要它：Android 上 Flutter 的 Dart isolate 在应用退到后台后照常运行，
 * 但进程只是「后台缓存」——内存吃紧就被回收，息屏久置进入 Doze 后网络也会被
 * 掐；套接字一断，会话就没了。前台服务把进程提到 `IMPORTANCE_FOREGROUND_SERVICE`，
 * 再持一把 partial wakelock 让息屏后 CPU 仍能处理远端输出（两者都随服务
 * 一起收，不会在没会话时空转）。
 *
 * 三处刻意的选择：
 * - 前台服务类型是 `specialUse`（子类型 ssh_session，见 Manifest）：交互动
 *   终端会话既不是 `dataSync` 那种「一段数据传输」，也不是与蓝牙 / USB 外设
 *   打交道的 `connectedDevice`。更实际的理由是 Android 15 起 `dataSync` 在
 *   24 小时内累计只能跑 6 小时，到点系统强制收走——长会话正好会被它砍掉。
 *   代价：上架 Google Play 需要在 Play Console 里填这个类型的用途说明。
 * - `START_NOT_STICKY` + `android:stopWithTask="true"`：服务只在「有会话」时
 *   才有意义。进程被杀 / 用户从最近任务划掉之后，Flutter 引擎随之销毁、会话
 *   全没了，让系统再拉起一个空服务（还挂着通知）纯属误导。
 * - 通知不可省：前台服务必须有常驻通知，它就是「后台在保活」的可见凭据。
 */
class SessionKeepAliveService : Service() {

    companion object {
        private const val CHANNEL_ID = "noshell.sessions"
        private const val NOTIFICATION_ID = 0x5E55
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_BODY = "body"
        private const val WAKE_LOCK_TAG = "NoShell:sessions"

        /** 拉起（或就地更新）保活服务；[title] / [body] 为已本地化的通知文案。 */
        fun start(context: Context, title: String, body: String) {
            val intent = Intent(context, SessionKeepAliveService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_BODY, body)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /** 收掉保活服务（最后一条会话关闭 / 应用退出时）。 */
        fun stop(context: Context) {
            context.stopService(Intent(context, SessionKeepAliveService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE).orEmpty().ifEmpty { "NoShell" }
        val body = intent?.getStringExtra(EXTRA_BODY).orEmpty()
        // startForegroundService 之后必须马上 startForeground（否则系统抛
        // ForegroundServiceDidNotStartInTimeException），这里第一件事就是它。
        promoteToForeground(title, body)
        acquireWakeLock()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        // 服务销毁时前台通知一并撤掉；不撤的话它会以普通通知的身份留在
        // 通知栏里，用户看到「后台保活」却已经没有会话了。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    private fun promoteToForeground(title: String, body: String) {
        val notification = buildNotification(title, body)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            } else {
                0
            }
            startForeground(NOTIFICATION_ID, notification, type)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(title: String, body: String): Notification {
        ensureChannel(title, body)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(R.drawable.ic_stat_session)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_SERVICE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // 默认行为会把前台服务通知延迟 10 秒才展示；这里是「后台在保活」
            // 的凭据，用户应该立刻看得见。
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        // 点通知回到已经开着的那一份（MainActivity 是 singleTop），
        // 不新建任务、不重启引擎——重启引擎等于把所有会话断掉。
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        if (launch != null) {
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            builder.setContentIntent(
                PendingIntent.getActivity(
                    this,
                    0,
                    launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
        }
        return builder.build()
    }

    /** 渠道名 / 说明用应用下发的本地化文案；渠道建过就不再改（系统不允许）。 */
    private fun ensureChannel(title: String, body: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            title,
            // LOW：不进状态栏图标区、不响不震，但常驻在通知栏里可见可静音。
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.description = body
        channel.setShowBadge(false)
        manager.createNotificationChannel(channel)
    }

    /**
     * partial wakelock：息屏后 CPU 仍要为这条连接服务（收远端输出、回 keepalive）。
     * 只在服务存活期间持有，服务一停就释放。注意它**不能**让应用豁免 Doze——
     * 设备长时间静止后系统仍会限制网络，那是 Android 的既定行为。
     */
    private fun acquireWakeLock() {
        if (wakeLock != null) return
        val power = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }
}
