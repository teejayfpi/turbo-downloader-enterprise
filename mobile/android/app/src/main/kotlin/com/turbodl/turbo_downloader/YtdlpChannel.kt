package com.turbodl.turbo_downloader

import android.util.Log
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Embedded yt-dlp for Android.
 *
 * The APK bundles CPython, yt-dlp, ffmpeg, and quickjs as native libraries
 * (youtubedl-android, GPL-3.0), so the full extractor runs on-device with no
 * external binary to install. The Dart layer owns the argument vectors and
 * parses yt-dlp's output; this bridge only runs the process and moves progress
 * back across the channel.
 *
 * A download runs on a worker thread and is observed by polling from Dart
 * rather than pushed: the worker never has to touch the UI thread, and the
 * poll is also where cancellation is delivered. The library's `destroy()`
 * covers yt-dlp's own child processes (ffmpeg), so a cancel leaves nothing
 * running.
 */
internal object YtdlpChannel {

    private const val TAG = "YtdlpChannel"

    /** A finished process's exit code and stderr, kept until Dart collects it. */
    private class Outcome(val exitCode: Int, val stderr: String, val canceled: Boolean)

    private val results = ConcurrentHashMap<String, Outcome>()
    private val workers = Executors.newCachedThreadPool()

    @Volatile
    private var initialized = false

    fun register(activity: MainActivity, channel: MethodChannel) {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> init(activity, result)
                "probe" -> probe(activity, call, result)
                "startDownload" -> startDownload(activity, channel, call, result)
                "pollDownload" -> poll(call, result)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Unpacks the bundled interpreter and ffmpeg on first use and returns the
     * yt-dlp version, or null when the engine cannot start. Unpacking takes a
     * few seconds the very first time; later calls are free. Runs on a worker
     * because the unzip would otherwise block the platform thread long enough
     * to risk an ANR.
     */
    private fun init(activity: MainActivity, result: MethodChannel.Result) {
        workers.execute {
            val version = ensureInit(activity)
            activity.runOnUiThread {
                if (version == null) {
                    result.error(
                        "YTDLP_INIT",
                        "The embedded download engine could not start.",
                        null,
                    )
                } else {
                    result.success(version)
                }
            }
        }
    }

    @Synchronized
    private fun ensureInit(activity: MainActivity): String? {
        if (initialized) return version(activity)
        return try {
            YoutubeDL.getInstance().init(activity)
            FFmpeg.init(activity)
            initialized = true
            version(activity)
        } catch (e: Exception) {
            Log.e(TAG, "embedded yt-dlp init failed", e)
            null
        }
    }

    /** The yt-dlp version, or a non-null sentinel so callers see "available". */
    private fun version(activity: MainActivity): String {
        return try {
            YoutubeDL.getInstance().version(activity) ?: "embedded"
        } catch (e: Exception) {
            "embedded"
        }
    }

    /** Runs `yt-dlp -J <url>` and returns its stdout JSON. */
    private fun probe(activity: MainActivity, call: MethodCall, result: MethodChannel.Result) {
        if (ensureInit(activity) == null) {
            result.error("YTDLP_INIT", "The embedded download engine could not start.", null)
            return
        }
        val args = call.argument<List<String>>("args")
        if (args.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "args is required", null)
            return
        }
        workers.execute {
            try {
                val response = YoutubeDL.getInstance()
                    .execute(requestFor(args), null, null)
                activity.runOnUiThread { result.success(response.out) }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    result.error("YTDLP_FAILED", e.message ?: "yt-dlp failed", stderrOf(e))
                }
            }
        }
    }

    /** Starts a download on a worker thread; the process id is returned at once. */
    private fun startDownload(
        activity: MainActivity,
        channel: MethodChannel,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (ensureInit(activity) == null) {
            result.error("YTDLP_INIT", "The embedded download engine could not start.", null)
            return
        }
        val args = call.argument<List<String>>("args")
        val processId = call.argument<String>("processId")
        if (args.isNullOrEmpty() || processId.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "args and processId are required", null)
            return
        }
        results.remove(processId)
        workers.execute {
            try {
                val response = YoutubeDL.getInstance().execute(
                    requestFor(args),
                    processId,
                ) { _, _, line ->
                    // One event per line, including the PROG lines the Dart side
                    // parses. Posting to the UI thread keeps the worker free to
                    // keep reading the process output.
                    activity.runOnUiThread {
                        channel.invokeMethod(
                            "progress",
                            mapOf("processId" to processId, "line" to line),
                        )
                    }
                }
                results[processId] = Outcome(response.exitCode, response.err, false)
            } catch (e: YoutubeDL.CanceledException) {
                results[processId] = Outcome(1, "", true)
            } catch (e: Exception) {
                results[processId] = Outcome(1, stderrOf(e), false)
            }
        }
        result.success(processId)
    }

    /** Returns the finished result, or null while it is still running. */
    private fun poll(call: MethodCall, result: MethodChannel.Result) {
        val processId = call.argument<String>("processId")
        if (processId.isNullOrEmpty()) {
            result.error("INVALID_ARGS", "processId is required", null)
            return
        }
        if (call.argument<Boolean>("cancel") == true) {
            try {
                YoutubeDL.getInstance().destroyProcessById(processId)
            } catch (e: Exception) {
                Log.w(TAG, "cancel failed", e)
            }
        }
        val outcome = results.remove(processId)
        if (outcome == null) {
            result.success(null)
            return
        }
        result.success(
            mapOf(
                "exitCode" to outcome.exitCode,
                "stderr" to outcome.stderr,
                "canceled" to outcome.canceled,
            ),
        )
    }

    /**
     * Turns the Dart argument vector into a request.
     *
     * The url is located by its scheme rather than by position: yt-dlp accepts
     * the url anywhere on the command line, and the two vectors Dart builds
     * disagree on where they put it (the probe puts it last, the download puts
     * it first). Assuming a position meant a download handed the whole option
     * list to yt-dlp as the url and the real url as an option, so nothing
     * downloaded. The remaining tokens are passed verbatim with `addCommands`,
     * the library's escape hatch for options it does not model; splitting them
     * into addOption() calls would lose the distinction between a flag and its
     * value and corrupt the command line.
     */
    private fun requestFor(args: List<String>): YoutubeDLRequest {
        val urlIndex = args.indexOfLast { isUrl(it) }.takeIf { it >= 0 } ?: (args.size - 1)
        val request = YoutubeDLRequest(args[urlIndex])
        request.addCommands(args.filterIndexed { index, _ -> index != urlIndex })
        return request
    }

    private fun isUrl(value: String): Boolean =
        value.startsWith("http://") || value.startsWith("https://")

    private fun stderrOf(e: Exception): String = e.message ?: ""
}
