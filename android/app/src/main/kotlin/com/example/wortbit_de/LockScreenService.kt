package com.example.wortbit_de

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground service that keeps the app alive in the background and
 * listens for ACTION_SCREEN_ON to bring up the flashcard on the lockscreen.
 */
class LockScreenService : Service() {

    companion object {
        const val CHANNEL_ID   = "wortbit_lockscreen_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_STOP  = "com.example.wortbit_de.STOP_SERVICE"
    }

    // ── Receiver: fires every time the screen turns on ──────────────────────
    private val screenOnReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == Intent.ACTION_SCREEN_ON) {
                showOnLockScreen(context)
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())

        // Register screen-on listener (cannot be declared in manifest for ACTION_SCREEN_ON)
        val filter = IntentFilter(Intent.ACTION_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenOnReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(screenOnReceiver, filter)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY   // Restart automatically if killed by system
    }

    override fun onDestroy() {
        try { unregisterReceiver(screenOnReceiver) } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Bring MainActivity to front over the lockscreen ──────────────────────
    private fun showOnLockScreen(context: Context) {
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK        or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            putExtra("from_lockscreen", true)
        }
        startActivity(launchIntent)
    }

    // ── Persistent foreground notification ───────────────────────────────────
    private fun buildNotification(): Notification {
        val stopIntent = Intent(this, LockScreenService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPi = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
        val openPi = PendingIntent.getActivity(
            this, 1, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_edit)
            .setContentTitle("Wortbit DE đang chạy")
            .setContentText("Từ vựng sẽ hiện khi bạn mở màn hình 📖")
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openPi)
            .addAction(android.R.drawable.ic_delete, "Tắt", stopPi)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Wortbit Lockscreen",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Hiển thị từ vựng trên màn hình khoá"
                setShowBadge(false)
                enableVibration(false)
                enableLights(false)
            }
            getSystemService(NotificationManager::class.java)
                ?.createNotificationChannel(channel)
        }
    }
}
