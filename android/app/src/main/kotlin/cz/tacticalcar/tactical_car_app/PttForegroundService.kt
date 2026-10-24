package cz.tacticalcar.tactical_car_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import android.view.KeyEvent

/**
 * Keeps PTT alive with the screen off: a microphone-type foreground service
 * (required for background mic access since Android 11), an ongoing
 * notification with a PTT toggle, and a MediaSession so the button of a
 * Bluetooth headset toggles PTT.
 */
class PttForegroundService : Service() {
    companion object {
        const val ACTION_UPDATE = "cz.tacticalcar.ptt.UPDATE"
        const val ACTION_TOGGLE = "cz.tacticalcar.ptt.TOGGLE"
        const val EXTRA_CHANNEL = "channel"
        const val EXTRA_STATUS = "status"
        private const val CHANNEL_ID = "ptt"
        private const val NOTIFICATION_ID = 4711
    }

    private var mediaSession: MediaSession? = null
    private var channel = "-"
    private var status = ""

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "PTT spojení", NotificationManager.IMPORTANCE_LOW)
                    .apply { setShowBadge(false) },
            )
        }
        mediaSession = MediaSession(this, "TacticalPtt").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
                    val event = keyEvent(mediaButtonIntent)
                    // Headset buttons usually send a click, not a hold:
                    // treat each press as toggle.
                    if (event != null &&
                        event.action == KeyEvent.ACTION_DOWN &&
                        event.repeatCount == 0 &&
                        event.keyCode in listOf(
                            KeyEvent.KEYCODE_HEADSETHOOK,
                            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
                            KeyEvent.KEYCODE_MEDIA_PLAY,
                            KeyEvent.KEYCODE_MEDIA_PAUSE,
                        )
                    ) {
                        PttBridge.emit("toggle")
                        return true
                    }
                    return super.onMediaButtonEvent(mediaButtonIntent)
                }
            })
            setPlaybackState(
                PlaybackState.Builder()
                    .setActions(
                        PlaybackState.ACTION_PLAY_PAUSE or
                            PlaybackState.ACTION_PLAY or
                            PlaybackState.ACTION_PAUSE,
                    )
                    .setState(PlaybackState.STATE_PLAYING, 0, 1f)
                    .build(),
            )
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_TOGGLE -> PttBridge.emit("toggle")
            else -> {
                channel = intent?.getStringExtra(EXTRA_CHANNEL) ?: channel
                status = intent?.getStringExtra(EXTRA_STATUS) ?: status
            }
        }
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(
                    NOTIFICATION_ID,
                    buildNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                )
            } else {
                startForeground(NOTIFICATION_ID, buildNotification())
            }
        } catch (error: RuntimeException) {
            // SecurityException / ForegroundServiceStartNotAllowedException.
            PttBridge.emit("service_error:${error.javaClass.simpleName}")
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        mediaSession?.release()
        mediaSession = null
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            flags,
        )
        val toggle = PendingIntent.getService(
            this,
            1,
            Intent(this, PttForegroundService::class.java).setAction(ACTION_TOGGLE),
            flags,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("PTT $channel")
            .setContentText(status)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_CALL)
            .setContentIntent(open)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, android.R.drawable.ic_btn_speak_now),
                    "PTT",
                    toggle,
                ).build(),
            )
            .build()
    }

    private fun keyEvent(intent: Intent): KeyEvent? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
        }
}
