package com.turbodl.turbo_downloader

import android.Manifest
import android.content.ContentResolver
import android.content.ContentValues
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val channelName = "turbo_downloader/files"

    /** Holds the in-flight storage-permission reply until the user answers. */
    private var storageResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "publishDownload" -> {
                        val path = call.argument<String>("path")
                        val filename = call.argument<String>("filename") ?: "download"
                        if (path == null) {
                            result.error("INVALID_ARGS", "path is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(publish(path, filename))
                        } catch (e: Exception) {
                            result.error("PUBLISH_FAILED", e.message, null)
                        }
                    }
                    // Android 10+ needs no permission; older versions must grant
                    // legacy storage before the shared Downloads folder is
                    // writable. Replies once the user answers the prompt.
                    "ensureStorage" -> ensureStorage(result)
                    // Keeps the process alive for on-device downloads with the
                    // screen off. `active` is the number of running transfers.
                    "background" -> {
                        val active = call.argument<Int>("active") ?: 0
                        try {
                            DownloadService.setActive(applicationContext, active)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SERVICE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun ensureStorage(result: MethodChannel.Result) {
        val alreadyGranted = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED
        if (alreadyGranted) {
            result.success(true)
            return
        }
        // Only one permission dialog can be outstanding at a time; a second
        // request reports failure so the caller keeps the file app-private.
        if (storageResult != null) {
            result.success(false)
            return
        }
        storageResult = result
        requestPermissions(
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            STORAGE_REQUEST
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == STORAGE_REQUEST) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            storageResult?.success(granted)
            storageResult = null
        }
    }

    /**
     * Copies a finished download into the shared Downloads collection so it is
     * visible to other apps and survives the app's own cache being cleared.
     * Returns the public path, or null when the platform cannot provide one.
     */
    private fun publish(sourcePath: String, filename: String): String? {
        val source = File(sourcePath)
        if (!source.exists()) return null

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            // Legacy path: write straight into the public Downloads directory.
            val dir = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS
            )
            if (!dir.exists()) dir.mkdirs()
            val dest = File(dir, filename)
            source.copyTo(dest, overwrite = true)
            return dest.absolutePath
        }

        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, filename)
            put(MediaStore.Downloads.MIME_TYPE, mimeFor(filename))
            put(MediaStore.Downloads.IS_PENDING, 1)
        }

        val resolver = applicationContext.contentResolver
        val collection =
            MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val item = resolver.insert(collection, values) ?: return null

        resolver.openOutputStream(item).use { output ->
            if (output == null) {
                resolver.delete(item, null, null)
                return null
            }
            source.inputStream().use { input -> input.copyTo(output) }
        }

        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(item, values, null, null)

        return queryPath(resolver, item) ?: filename
    }

    /** Resolves the on-disk path MediaStore assigned, which the UI can display. */
    private fun queryPath(resolver: ContentResolver, item: Uri): String? {
        val projection = arrayOf(MediaStore.Downloads.DATA)
        return try {
            resolver.query(item, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(MediaStore.Downloads.DATA)
                    if (index >= 0) cursor.getString(index) else null
                } else {
                    null
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun mimeFor(filename: String): String {
        val ext = filename.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "mp4", "m4v" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "webm" -> "video/webm"
            "mov" -> "video/quicktime"
            "mp3" -> "audio/mpeg"
            "m4a" -> "audio/mp4"
            "opus" -> "audio/opus"
            "wav" -> "audio/wav"
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "gif" -> "image/gif"
            "pdf" -> "application/pdf"
            "zip" -> "application/zip"
            "apk" -> "application/vnd.android.package-archive"
            else -> "application/octet-stream"
        }
    }

    companion object {
        private const val STORAGE_REQUEST = 7301
    }
}
