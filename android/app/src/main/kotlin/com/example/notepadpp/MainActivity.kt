package com.example.notepadpp

import android.content.ClipData
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.io.FileOutputStream

/// Entry point that also acts as a "Open with" / "Share with" handler.
///
/// When the user picks this app from a file manager's "打开方式" or from
/// WeChat's "分享 -> 发送到", the system fires [Intent.ACTION_VIEW],
/// [Intent.ACTION_SEND] or [Intent.ACTION_SEND_MULTIPLE]. This activity:
///   1. Resolves the incoming [Uri] (file:// or content://) to a path the
///      Flutter layer can read. content:// URIs are first copied into the
///      app's cache directory because Flutter / dart:io cannot open the
///      shared FDs directly.
///   2. Hands the resolved path(s) to Flutter over a [MethodChannel]
///      (`app.share/openPath`) and an [EventChannel] for late arrivals.
///
/// Both cold-start and already-running (singleTop / onNewIntent) cases are
/// handled.
class MainActivity : FlutterActivity() {

    private val methodChannelName = "app.share/openPath"
    private val eventChannelName = "app.share/pathStream"

    private var methodChannel: MethodChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    // Paths received before the Flutter engine subscribed to the event
    // channel (cold start case) — delivered as soon as a listener attaches.
    private val pendingPaths = mutableListOf<String>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, methodChannelName
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingPaths" -> {
                        result.success(pendingPaths.toList())
                        pendingPaths.clear()
                    }
                    "shareCurrentApk" -> result.success(shareCurrentApk())
                    else -> result.notImplemented()
                }
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger, eventChannelName
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                if (pendingPaths.isNotEmpty()) {
                    events?.success(pendingPaths.toList())
                    pendingPaths.clear()
                }
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val action = intent?.action ?: return
        val resolved = when (action) {
            Intent.ACTION_VIEW, Intent.ACTION_EDIT -> resolveUri(intent.data)
            Intent.ACTION_SEND -> {
                val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                resolveUri(uri)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                    ?: return
                uris.flatMap { resolveUri(it) }
            }
            else -> return
        }

        if (resolved.isEmpty()) return

        if (eventSink != null) {
            eventSink?.success(resolved)
        } else {
            pendingPaths.addAll(resolved)
        }
    }

    /// Returns an absolute path Flutter can read. content:// URIs are
    /// streamed into the cache dir; file:// URIs are returned as-is.
    private fun resolveUri(uri: Uri?): List<String> {
        if (uri == null) return emptyList()
        return when (uri.scheme) {
            ContentResolver.SCHEME_FILE -> {
                val path = uri.path ?: return emptyList()
                listOf(path)
            }
            ContentResolver.SCHEME_CONTENT -> {
                listOf(copyContentUriToCache(uri)).filterNotNull()
            }
            else -> emptyList()
        }
    }

    private fun copyContentUriToCache(uri: Uri): String? {
        return try {
            val displayName = queryDisplayName(uri) ?: "shared_file"
            val ext = displayName.substringAfterLast('.', "")
            val base = displayName.substringBeforeLast('.', displayName)
            // Avoid overwriting an identically named file in the cache.
            var outFile = File(cacheDir, "$base.$ext")
            var n = 1
            while (outFile.exists()) {
                outFile = File(cacheDir, "${base}_$n.$ext")
                n++
            }
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(outFile).use { output ->
                    input.copyTo(output)
                }
            }
            outFile.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    /// Copy the installed base APK into the cache and hand it to the system
    /// share sheet. The existing FileProvider grants the receiving app
    /// temporary read access without exposing the original file path.
    private fun shareCurrentApk(): Boolean {
        return try {
            val sourceApk = File(applicationInfo.sourceDir)
            val versionName = packageManager.getPackageInfo(packageName, 0).versionName
            val sharedApk = File(cacheDir, "文件查看器_$versionName.apk")
            sourceApk.inputStream().use { input ->
                sharedApk.outputStream().use { output -> input.copyTo(output) }
            }

            val apkUri = FileProvider.getUriForFile(
                this, "${packageName}.fileprovider", sharedApk
            )
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "application/vnd.android.package-archive"
                putExtra(Intent.EXTRA_STREAM, apkUri)
                putExtra(Intent.EXTRA_SUBJECT, sharedApk.name)
                clipData = ClipData.newUri(contentResolver, sharedApk.name, apkUri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(shareIntent, "分享 APK"))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) cursor.getString(idx) else null
                } else null
            }
        } catch (_: Exception) {
            null
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventSink = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
