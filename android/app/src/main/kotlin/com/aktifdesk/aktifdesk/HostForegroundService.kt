package com.aktifdesk.aktifdesk

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
 * Keeps the remote-host process alive with a persistent notification while a
 * control session (or waiting for one) is active. Does not capture the screen.
 */
class HostForegroundService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
        acquireCpuWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForegroundCompat()
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                val waiting = intent?.getBooleanExtra(EXTRA_WAITING, true) ?: true
                try {
                    startAsForeground(waiting)
                } catch (_: Exception) {
                    // Isolate FGS / notification failures so the Flutter UI stays up.
                }
                return START_STICKY
            }
        }
    }

    override fun onDestroy() {
        releaseCpuWakeLock()
        super.onDestroy()
    }

    private fun startAsForeground(waiting: Boolean) {
        val notification = buildNotification(waiting)
        if (Build.VERSION.SDK_INT >= 29) {
            try {
                startForeground(
                    NOTIF_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } catch (_: Exception) {
                @Suppress("DEPRECATION")
                startForeground(NOTIF_ID, notification)
            }
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIF_ID, notification)
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= 24) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        val ch = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.host_notification_channel),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "AktifDesk uzaktan host oturumu"
            setShowBadge(false)
        }
        nm.createNotificationChannel(ch)
    }

    private fun buildNotification(waiting: Boolean): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        launch.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        val pi = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val text = if (waiting) {
            getString(R.string.host_notification_waiting)
        } else {
            getString(R.string.host_notification_text)
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle(getString(R.string.host_notification_title))
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pi)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    @Suppress("DEPRECATION")
    private fun acquireCpuWakeLock() {
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            val lock = wakeLock ?: pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "aktifdesk:host-fg",
            ).also {
                it.setReferenceCounted(false)
                wakeLock = it
            }
            if (!lock.isHeld) lock.acquire(60 * 60 * 1000L)
        } catch (_: Exception) {
        }
    }

    private fun releaseCpuWakeLock() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        wakeLock = null
    }

    companion object {
        const val CHANNEL_ID = "aktifdesk_host"
        const val NOTIF_ID = 47100
        const val ACTION_START = "com.aktifdesk.aktifdesk.HOST_FG_START"
        const val ACTION_STOP = "com.aktifdesk.aktifdesk.HOST_FG_STOP"
        const val EXTRA_WAITING = "waiting"

        fun start(context: Context, waiting: Boolean = true) {
            val i = Intent(context, HostForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_WAITING, waiting)
            }
            try {
                if (Build.VERSION.SDK_INT >= 26) {
                    context.startForegroundService(i)
                } else {
                    context.startService(i)
                }
            } catch (_: Exception) {
            }
        }

        fun update(context: Context, waiting: Boolean) {
            start(context, waiting)
        }

        fun stop(context: Context) {
            val i = Intent(context, HostForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            try {
                context.startService(i)
            } catch (_: Exception) {
            }
        }
    }
}
