package com.noshell

import android.content.ClipData
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.util.Log
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 下载落点在 Android 这一侧的两支实现（Dart 侧见 `lib/ssh/android_downloads_io.dart`）：
 *
 * - Android 10+ —— MediaStore：公共下载目录只能经它写，拿不到可写的绝对路径，
 *   所以走「建行 + 交 fd」。先 `insert` 一条 `IS_PENDING=1` 的记录（转正之前对
 *   别的应用不可见），把该记录的文件描述符以 `/proc/self/fd/N` 的形式交回 Dart，
 *   Dart 用 `dart:io` 照常往里灌数据（整个文件只落一份，不多拷一遍），收尾时把
 *   `IS_PENDING` 归零。失败 / 取消就删行删文件——`IS_PENDING` 天然就是「先写
 *   临时文件、成功再改名」里那层临时态。
 * - Android 9 及以下 —— 公共目录就是普通文件路径，缺的只有 `WRITE_EXTERNAL_STORAGE`
 *   （权限申请的弹框在 [MainActivity] 里，只有 Activity 能弹）。
 *
 * 通道方法：
 * - `mediaStoreAvailable`：这台设备能不能走 MediaStore 那支（版本 + 挂载状态）；
 * - `begin`：建行并返回可写的 fd 路径；
 * - `finish`：转正，返回该行最终的显示名（重名时系统会改成 `name (1).ext`）；
 * - `abort`：删行删文件，没建过行时是空操作；
 * - `share`：把已落地的文件以 `content://` 交给系统分享面板（不拷第二份）；
 * - `legacyPath`：Android 9 及以下那支的根目录，新系统上返回 null；
 * - `requestStoragePermission`：申请写公共目录的权限，返回是否拿到。
 *
 * 在途记录按**令牌**记账（Dart 侧每个落点现取一个序号，见
 * `lib/ssh/android_downloads_io.dart`），不按显示名：下载队列是每条会话一个，
 * 同一个文件名可以被两条会话同时下载，而按名字记账会让后一条的 `begin`
 * 把前一条正在写的那一行删掉——前一条继续往已删除的行里写，收尾时查不到
 * 自己的记录、转正成空操作，界面却报「下载完成」，文件其实已经不在了。
 */
class DownloadsChannel(private val activity: MainActivity) : MethodChannel.MethodCallHandler {

    private val resolver = activity.applicationContext.contentResolver

    /** 在途记录，键是落点令牌。 */
    private val pending = mutableMapOf<String, Pending>()

    /** 已转正的记录，键是落点令牌：分享时取回行地址，省得再查一遍目录。 */
    private val finished = mutableMapOf<String, Uri>()

    private data class Pending(val uri: Uri, val descriptor: ParcelFileDescriptor, val name: String)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "mediaStoreAvailable" -> result.success(mediaStoreAvailable())
                "begin" -> result.success(
                    begin(
                        call.argument<String>("token").orEmpty(),
                        call.argument<String>("name").orEmpty(),
                    ),
                )
                "finish" -> result.success(finish(call.argument<String>("token").orEmpty()))
                "abort" -> result.success(abort(call.argument<String>("token").orEmpty()))
                "share" -> result.success(
                    share(
                        call.argument<String>("token").orEmpty(),
                        call.argument<String>("name").orEmpty(),
                        call.argument<String>("title"),
                    ),
                )
                "legacyPath" -> result.success(activity.legacyDownloadsDirectory())
                "hasStoragePermission" -> result.success(activity.hasStoragePermission())
                "requestStoragePermission" -> activity.requestStoragePermission { granted ->
                    result.success(granted)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            // 如实回报：Dart 侧据此退回应用目录，或把这次下载标成失败——
            // 绝不假装写成功，用户按提示去找却找不到才是最难查的故障。
            Log.w(TAG, "downloads channel failed: ${call.method}", error)
            result.error("downloads_failed", error.message, null)
        }
    }

    /**
     * 静态条件。还不够：能不能真写进去还取决于 OEM 策略（Android 10 上有
     * 设备要求 WRITE_EXTERNAL_STORAGE），所以 Dart 侧还会真建一条记录试一次。
     */
    private fun mediaStoreAvailable(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            Environment.getExternalStorageState() == Environment.MEDIA_MOUNTED

    /** 建一条 pending 行并打开写入句柄，返回 `/proc/self/fd/N`。 */
    private fun begin(token: String, name: String): String? {
        if (!mediaStoreAvailable()) throw IllegalStateException("public downloads unavailable")
        if (token.isEmpty() || name.isEmpty()) {
            throw IllegalArgumentException("empty download token or file name")
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeTypeOf(name))
            put(MediaStore.MediaColumns.RELATIVE_PATH, RELATIVE_PATH)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("media store refused the insert")
        val descriptor = try {
            resolver.openFileDescriptor(uri, "w")
                ?: throw IllegalStateException("media store gave no descriptor")
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
        // 这里**不**清理同名的在途记录：那正是两条会话同时下同名文件时
        // 后一条杀掉前一条的地方。同名由系统改成 `name (1).ext`（finish 会
        // 把真实名回报给界面），而进程被杀留下的 pending 行本来就查不到
        // （账目在内存里），交回系统 7 天后自收。
        pending[token] = Pending(uri, descriptor, name)
        return "/proc/self/fd/${descriptor.fd}"
    }

    /**
     * 转正：关掉描述符（Dart 那份 dup 在 `IOSink.close()` 时已经关了），
     * 把 `IS_PENDING` 归零，返回该行最终的显示名。
     */
    private fun finish(token: String): String? {
        val entry = pending[token] ?: return null
        closeQuietly(entry.descriptor)
        // 记账留到 update 之后：它要是抛了，那条记录还挂在账上，紧接着的
        // abort（Dart 侧的失败路径会调）才删得掉它，不留一条看不见的残留。
        resolver.update(
            entry.uri,
            ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
            null,
            null,
        )
        pending.remove(token)
        val actual = displayNameOf(entry.uri)
        // 按令牌记账：分享紧跟着下载完成发生，拿的还是同一个暗号。
        rememberFinished(token, entry.uri)
        // 查不到实际显示名时退回本次请求的名字（不是令牌：这是给用户看的）。
        return actual ?: entry.name
    }

    /** 清理半成品。没建过行（begin 抛错、任务还没轮到就取消）时是空操作。 */
    private fun abort(token: String): Boolean {
        val entry = pending.remove(token) ?: return true
        closeQuietly(entry.descriptor)
        resolver.delete(entry.uri, null, null)
        return true
    }

    /**
     * 把已落地的文件交给系统分享面板：直接发 `content://` 地址并附上读授权，
     * 接收方从下载目录里读原件——不用先把文件读出来再往临时目录写一份，
     * 大文件也不怕。
     */
    private fun share(token: String, name: String, title: String?): Boolean {
        // 先按令牌找（正常路径）；令牌不在账上时退回按显示名查一次，
        // 例如账目已被 FINISHED_LIMIT 挤掉。
        val uri = finished[token] ?: findByName(name) ?: return false
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = resolver.getType(uri) ?: "application/octet-stream"
            putExtra(Intent.EXTRA_STREAM, uri)
            // 有些接收方只看 ClipData 里的 uri，两个都给上。
            clipData = ClipData.newRawUri(null, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val chooser = Intent.createChooser(intent, title).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        activity.startActivity(chooser)
        return true
    }

    private fun rememberFinished(token: String, uri: Uri) {
        finished[token] = uri
        // 只留最近几条：分享总是紧跟着下载完成发生，攒多了没用。
        while (finished.size > FINISHED_LIMIT) {
            finished.remove(finished.keys.first())
        }
    }

    private fun findByName(name: String): Uri? {
        resolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.MediaColumns._ID),
            "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND " +
                "${MediaStore.MediaColumns.RELATIVE_PATH} = ?",
            arrayOf(name, RELATIVE_PATH),
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                return ContentUris.withAppendedId(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    cursor.getLong(0),
                )
            }
        }
        return null
    }

    private fun closeQuietly(descriptor: ParcelFileDescriptor) {
        try {
            descriptor.close()
        } catch (error: Exception) {
            Log.w(TAG, "close media store descriptor failed", error)
        }
    }

    private fun displayNameOf(uri: Uri): String? {
        resolver.query(
            uri,
            arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val column = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                if (column >= 0) return cursor.getString(column)
            }
        }
        return null
    }

    /** MediaStore 要一条 MIME 才肯建行；认不出来按二进制流记账。 */
    private fun mimeTypeOf(name: String): String {
        val extension = name.substringAfterLast('.', "").lowercase()
        val guessed = if (extension.isEmpty()) {
            null
        } else {
            MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
        }
        return guessed ?: "application/octet-stream"
    }

    companion object {
        const val CHANNEL = "com.noshell/downloads"
        private const val TAG = "NoShell"
        private const val RELATIVE_PATH = "Download/"
        private const val FINISHED_LIMIT = 8
    }
}
