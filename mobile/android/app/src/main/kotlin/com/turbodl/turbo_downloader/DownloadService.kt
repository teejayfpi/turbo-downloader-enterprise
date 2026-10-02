package com.turbodl.turbo_downloader

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps the process alive while the phone is downloading, so a transfer is not
 * killed when the app is backgrounded or the screen turns off. The service does
 * no work itself: the Dart engine holds the connections, it just stops Android
 * from freezing the process.
 */
class DownloadService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val active = 1
        val notification = buildNotification(this, active)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val active = intent?.getIntExtra("active", 1) ?: 1
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(this, active))
        return START_NOT_STICKY
    }

    companion object {
        private const val CHANNEL_ID = "turbo_downloads"
        private const val NOTIFICATION_ID = 4201

        /** Starts the foreground service, or refreshes its notification. */
        fun setActive(context: Context, active: Int) {
            val intent = Intent(context, DownloadService::class.java)
                .putExtra("active", active)
            if (active <= 0) {
                context.stopService(intent)
                return
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, DownloadService::class.java))
        }

        fun buildNotification(context: Context, active: Int): Notification {
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Downloads",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Shown while files are downloading"
                    setShowBadge(false)
                }
                manager.createNotificationChannel(channel)
            }

            val open = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            val pending = android.app.PendingIntent.getActivity(
                context,
                0,
                open,
                android.app.PendingIntent.FLAG_IMMUTABLE or
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT
            )

            val text = if (active == 1) "1 download in progress" else
                "$active downloads in progress"

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }

            return builder
                .setContentTitle("Turbo is downloading")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setOngoing(true)
                .setContentIntent(pending)
                .build()
        }
    }
}
