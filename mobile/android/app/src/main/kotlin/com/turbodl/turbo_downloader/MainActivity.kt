package com.turbodl.turbo_downloader

import android.Manifest
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
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

        // The embedded yt-dlp engine (CPython + yt-dlp + ffmpeg). Registered on
        // its own channel: a failure to start it must not affect the built-in
        // HTTP engine, and the Dart side treats a missing channel as "no
        // yt-dlp", which is the same state as a desktop without the binary.
        YtdlpChannel.register(
            this,
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "turbo_downloader/ytdlp"
            )
        )

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
            // Legacy storage is not indexed automatically; tell the media
            // scanner so gallery and music apps pick the file up.
            scanLegacyFile(dest)
            return dest.absolutePath
        }

        val mime = mimeFor(filename)
        // Videos, audio, and images go into their own media collections, which
        // is what the gallery, Photos, and music apps read. Filing a video only
        // under `Downloads` leaves it invisible to them, which is exactly the
        // "my download does not show up as media" report. Everything else has
        // no media collection and belongs in Downloads.
        val mediaCollection = mediaCollectionFor(mime)
        val collection = mediaCollection
            ?: MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            // Media collections file under their conventional root (Movies,
            // Music, Pictures) so a gallery is not asked to scan the volume
            // root; everything else keeps the caller's Turbo subfolder under
            // Downloads.
            val relativePath = if (mediaCollection != null) {
                "${mediaRootFor(mime)}/$TURBO_FOLDER"
            } else {
                "Download/$relative"
            }
            if (relativePath.isNotEmpty()) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            }
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        val resolver = applicationContext.contentResolver
        val item = resolver.insert(collection, values) ?: return null

        resolver.openOutputStream(item).use { output ->
            if (output == null) {
                resolver.delete(item, null, null)
                return null
            }
            source.inputStream().use { input -> input.copyTo(output) }
        }

        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        resolver.update(item, values, null, null)

        return queryPath(resolver, item) ?: filename
    }

    /**
     * The MediaStore collection that owns [mime], or null when it is not media.
     * Each collection is where the corresponding system app looks: `Video` for
     * the gallery and movie apps, `Audio` for music players, `Images` for the
     * photo gallery. A null result means the file belongs in `Downloads`.
     */
    private fun mediaCollectionFor(mime: String): Uri? = when {
        mime.startsWith("video/") ->
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        mime.startsWith("audio/") ->
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        mime.startsWith("image/") ->
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        else -> null
    }

    /**
     * The conventional top-level folder a media [mime] belongs under, matching
     * the volume layout Android itself uses: `Movies` for video, `Music` for
     * audio, `Pictures` for images.
     */
    private fun mediaRootFor(mime: String): String = when {
        mime.startsWith("video/") -> Environment.DIRECTORY_MOVIES
        mime.startsWith("audio/") -> Environment.DIRECTORY_MUSIC
        else -> Environment.DIRECTORY_PICTURES
    }

    /** Asks the legacy media scanner to index a file written outside MediaStore. */
    private fun scanLegacyFile(file: File) {
        try {
            MediaScannerConnection.scanFile(
                applicationContext,
                arrayOf(file.absolutePath),
                null,
                null
            )
        } catch (_: Exception) {
            // Indexing is best effort; the file is already saved.
        }
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
        // The generic column works for every collection (Video, Audio, Images,
        // Downloads); the collection-specific constants do not.
        val projection = arrayOf(MediaStore.MediaColumns.DATA)
        return try {
            resolver.query(item, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
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

        /** Subfolder all downloads are filed under, matching FileStore.turboFolder. */
        private const val TURBO_FOLDER = "Turbo"
    }
}
