package com.rohit.lan_mouse_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.os.IBinder
import java.util.Locale

/// Keeps the client-mode listener alive while the app is in the
/// background. Android may kill a plain background process (and
/// swiping the app from Recents definitely can), which would take
/// the UDP listener, the accessibility service and the IME down
/// with it. As a foreground service the process is protected for
/// as long as the user is listening; the persistent notification
/// is the visible trade-off, and its Stop action ends the session
/// through the dispatcher.
///
/// The service owns no session state: starting and stopping are
/// driven from Dart (fgStart / fgStop channel calls in
/// [ClientInputDispatcher.handle]).
class LanMouseForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            if (isIndonesian()) "Mode client" else "Client mode",
            NotificationManager.IMPORTANCE_LOW,
        )
        nm.createNotificationChannel(channel)
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        if (intent?.action == ACTION_STOP) {
            // Ask Dart to stop listening; its shutdown calls fgStop,
            // which stops this service through the normal path. If
            // Dart is unreachable, still drop the foreground state
            // so the notification cannot outlive the session.
            ClientInputDispatcher.requestStopListening()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            startForeground(NOTIF_ID, notification)
        }
        return START_STICKY
    }

    private fun buildNotification(): Notification {
        val id = isIndonesian()
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, LanMouseForegroundService::class.java)
                .setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Lan Mouse Pro")
            .setContentText(
                if (id) {
                    "Mendengarkan - desktop dapat mengendalikan perangkat ini"
                } else {
                    "Listening - the desktop can control this device"
                },
            )
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(
                        this,
                        android.R.drawable.ic_menu_close_clear_cancel,
                    ),
                    if (id) "Berhenti" else "Stop",
                    stopIntent,
                ).build(),
            )
            .build()
    }

    private fun isIndonesian(): Boolean =
        Locale.getDefault().language == "id"

    companion object {
        private const val CHANNEL_ID = "lan_mouse_client"
        private const val NOTIF_ID = 4242
        const val ACTION_STOP = "com.rohit.lan_mouse_mobile.FGS_STOP"

        fun start(context: Context) {
            val intent = Intent(context, LanMouseForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(
                Intent(context, LanMouseForegroundService::class.java),
            )
        }
    }
}
