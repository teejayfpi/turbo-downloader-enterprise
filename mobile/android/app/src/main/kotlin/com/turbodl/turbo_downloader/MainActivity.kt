package com.turbodl.turbo_downloader

import android.Manifest
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
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

        // A second, independent channel set: credentials, notifications, and
        // device state. Kept out of the files channel so a failure to read one
        // capability cannot disable the others.
        PlatformChannels.register(this, flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "publishDownload" -> {
                        val path = call.argument<String>("path")
                        val filename = call.argument<String>("filename") ?: "download"
                        // Relative folder under Downloads to file into, e.g.
                        // "Turbo/Videos". Null falls back to the Downloads root.
                        val subfolder = call.argument<String>("subfolder")
                        if (path == null) {
                            result.error("INVALID_ARGS", "path is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(publish(path, filename, subfolder))
                        } catch (e: Exception) {
                            result.error("PUBLISH_FAILED", e.message, null)
                        }
                    }
                    // Android 10+ needs no permission; older versions must grant
                    // legacy storage before the shared Downloads folder is
                    // writable. Replies once the user answers the prompt.
                    "ensureStorage" -> ensureStorage(result)
                    // Hands a finished file to another app via the system share
                    // sheet. Opens a chooser; the user picks the destination.
                    "shareFile" -> {
                        val path = call.argument<String>("path")
                        val filename = call.argument<String>("filename") ?: ""
                        if (path == null) {
                            result.error("INVALID_ARGS", "path is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            share(path, filename)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SHARE_FAILED", e.message, null)
                        }
                    }
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
     *
     * [subfolder] nests the file, e.g. "Turbo/Videos", so media and documents
     * are kept apart under a single Turbo folder. Returns the public path, or
     * null when the platform cannot provide one.
     */
    private fun publish(sourcePath: String, filename: String, subfolder: String?): String? {
        val source = File(sourcePath)
        if (!source.exists()) return null
        val relative = normalizeSubfolder(subfolder)

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            // Legacy path: write straight into the public Downloads directory.
            val base = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS
            )
            val dir = if (relative.isEmpty()) base else File(base, relative)
            if (!dir.exists()) dir.mkdirs()
            val dest = File(dir, filename)
            source.copyTo(dest, overwrite = true)
            return dest.absolutePath
        }

        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, filename)
            put(MediaStore.Downloads.MIME_TYPE, mimeFor(filename))
            if (relative.isNotEmpty()) {
                put(MediaStore.Downloads.RELATIVE_PATH, "Download/$relative")
            }
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

    /**
     * Shares a saved file through the system chooser. The file is exposed with
     * a content:// URI through the app's FileProvider so no storage permission
     * leaks to the receiving app.
     */
    private fun share(path: String, filename: String) {
        val file = File(path)
        if (!file.exists()) return
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeFor(if (filename.isNotEmpty()) filename else file.name)
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_TITLE, file.name)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val chooser = Intent.createChooser(intent, "Share ${file.name}").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(chooser)
    }

    /** Keeps only safe path segments, dropping any attempt to escape the root. */
    private fun normalizeSubfolder(subfolder: String?): String {
        if (subfolder.isNullOrBlank()) return ""
        return subfolder
            .split('/', '\\')
            .map { it.trim() }
            .filter { it.isNotEmpty() && it != "." && it != ".." }
            .joinToString("/")
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
            "ts" -> "video/mp2t"
            "mov" -> "video/quicktime"
            "avi" -> "video/x-msvideo"
            "mp3" -> "audio/mpeg"
            "m4a" -> "audio/mp4"
            "opus" -> "audio/opus"
            "wav" -> "audio/wav"
            "flac" -> "audio/flac"
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
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
