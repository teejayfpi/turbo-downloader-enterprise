package com.turbodl.turbo_downloader

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Platform bridges the Dart layer calls through method channels:
 *
 *  - `turbo_downloader/secure`  — Keystore-backed credential vault
 *  - `turbo_downloader/notify`  — download notifications
 *  - `turbo_downloader/device`  — connectivity and power state
 *
 * Each is registered from [MainActivity.configureFlutterEngine]. If a channel
 * is missing the Dart side degrades gracefully (it treats a MissingPlugin as
 * "not available"), so a registration failure never takes the app down.
 */
internal object PlatformChannels {

    fun register(activity: MainActivity, engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "turbo_downloader/secure")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "secureWrite" -> {
                            val key = call.argument<String>("key")
                            val value = call.argument<String>("value")
                            if (key == null || value == null) {
                                result.error("INVALID_ARGS", "key/value required", null)
                            } else {
                                SecureVault.write(activity, key, value)
                                result.success(true)
                            }
                        }
                        "secureRead" ->
                            result.success(
                                SecureVault.read(activity, call.argument<String>("key")),
                            )
                        "secureDelete" ->
                            result.success(
                                SecureVault.delete(activity, call.argument<String>("key")),
                            )
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("SECURE_FAILED", e.message, null)
                }
            }

        MethodChannel(messenger, "turbo_downloader/notify")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "ensureChannel" -> {
                            Notifier.ensureChannel(activity)
                            result.success(true)
                        }
                        "notify" -> {
                            Notifier.show(
                                activity,
                                call.argument<String>("title") ?: "Turbo",
                                call.argument<String>("body") ?: "",
                                call.argument<Boolean>("ongoing") ?: false,
                                call.argument<Int>("progress") ?: -1,
                            )
                            result.success(true)
                        }
                        "progress" -> {
                            Notifier.progress(
                                activity,
                                call.argument<Int>("active") ?: 0,
                                call.argument<Int>("percent") ?: 0,
                            )
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("NOTIFY_FAILED", e.message, null)
                }
            }

        MethodChannel(messenger, "turbo_downloader/device")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "state" -> result.success(DeviceState.read(activity))
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("DEVICE_FAILED", e.message, null)
                }
            }
    }
}

/**
 * Credential storage backed by the **Android Keystore**.
 *
 * A single AES-256 key is generated inside the Keystore and never leaves it.
 * Values are encrypted with AES/GCM and only the ciphertext plus its IV are
 * written to app-private preferences, so a backup of the app data cannot yield
 * a usable credential without the hardware-bound key.
 */
private object SecureVault {
    private const val KEYSTORE = "AndroidKeyStore"
    private const val ALIAS = "turbo.secure.key"
    private const val PREFS = "turbo_secure"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val TAG_BITS = 128

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (ks.getEntry(ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    fun write(context: Context, key: String, value: String) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val ciphertext = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val payload = "${Base64.encodeToString(cipher.iv, Base64.NO_WRAP)}:" +
            Base64.encodeToString(ciphertext, Base64.NO_WRAP)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(key, payload).apply()
    }

    fun read(context: Context, key: String?): String? {
        if (key == null) return null
        val payload = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(key, null) ?: return null
        return try {
            val parts = payload.split(":", limit = 2)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                key(),
                GCMParameterSpec(TAG_BITS, Base64.decode(parts[0], Base64.NO_WRAP)),
            )
            String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8)
        } catch (e: Exception) {
            null
        }
    }

    fun delete(context: Context, key: String?): Boolean {
        if (key == null) return false
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val existed = prefs.contains(key)
        prefs.edit().remove(key).apply()
        return existed
    }
}

/** Download notifications: a channel, completion alerts, and progress. */
private object Notifier {
    private const val CHANNEL_ID = "turbo_downloads"
    private const val CHANNEL_NAME = "Downloads"
    private const val COMPLETE_ID = 7302
    private const val PROGRESS_ID = 7303

    /** Preferences used only to remember that the permission was requested. */
    private const val PREFS = "turbo_notify"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Finished downloads and transfer progress."
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }
        // Android 13+ needs the runtime permission before anything is shown.
        // Ask once: after a denial the system stops showing the dialog, so a
        // repeated request would just be a no-op without a flag.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED &&
            context is MainActivity
        ) {
            val asked = context
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean("notifyAsked", false)
            if (!asked) {
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .edit().putBoolean("notifyAsked", true).apply()
                context.requestPermissions(
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    PERMISSION_REQUEST,
                )
            }
        }
    }

    private fun allowed(context: Context): Boolean =
        NotificationManagerCompat.from(context).areNotificationsEnabled()

    fun show(
        context: Context,
        title: String,
        body: String,
        ongoing: Boolean,
        progress: Int,
    ) {
        if (!allowed(context)) return
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(ongoing)
            .setAutoCancel(!ongoing)
            .setPriority(NotificationCompat.PRIORITY_LOW)
        if (progress in 0..100) {
            builder.setProgress(100, progress, false)
        }
        try {
            NotificationManagerCompat.from(context).notify(COMPLETE_ID, builder.build())
        } catch (_: SecurityException) {
            // Permission revoked between the check and the post; ignore.
        }
    }

    fun progress(context: Context, active: Int, percent: Int) {
        if (!allowed(context)) return
        val manager = NotificationManagerCompat.from(context)
        if (active <= 0) {
            manager.cancel(PROGRESS_ID)
            return
        }
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(
                if (active == 1) "Downloading" else "$active downloads running",
            )
            .setProgress(100, percent.coerceIn(0, 100), false)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
        try {
            manager.notify(PROGRESS_ID, builder.build())
        } catch (_: SecurityException) {
            // Ignore; the in-app banner still reports progress.
        }
    }

    const val PERMISSION_REQUEST = 7304
}

/** Connects to the system's connectivity and battery state. */
private object DeviceState {
    fun read(context: Context): Map<String, Any> {
        val connectivity =
            context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
        val onWifi = caps != null &&
            (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET))

        val battery = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val level = battery.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        return mapOf<String, Any>(
            "wifi" to onWifi,
            "charging" to battery.isCharging,
            "battery" to if (level in 0..100) level else -1,
        )
    }
}
