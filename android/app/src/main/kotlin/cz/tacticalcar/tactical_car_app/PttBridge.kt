package cz.tacticalcar.tactical_car_app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter <-> native glue for push-to-talk:
 * - `tactical/ptt_native` (method): start/update/stop the foreground
 *   service, enable volume-key PTT.
 * - `tactical/ptt_buttons` (event): "down" / "up" (hold, app in front)
 *   and "toggle" (headset button or notification action, any state).
 */
object PttBridge : EventChannel.StreamHandler {
    private const val METHOD_CHANNEL = "tactical/ptt_native"
    private const val EVENT_CHANNEL = "tactical/ptt_buttons"
    private const val PERMISSION_REQUEST = 4712

    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var appContext: Context? = null
    private var pendingStart: Intent? = null

    /** PTT joined: hardware keys are routed to PTT only then. */
    @Volatile
    var active = false
        private set

    @Volatile
    var volumeKeyPtt = false
        private set

    fun attach(messenger: BinaryMessenger, activity: Activity) {
        appContext = activity.applicationContext
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(this)
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start", "update" -> {
                    val intent = serviceIntent(activity, call.arguments as? Map<*, *>)
                    if (call.method == "start" || !active) {
                        startService(activity, intent)
                    } else {
                        activity.startService(intent)
                    }
                    result.success(null)
                }
                "stop" -> {
                    active = false
                    pendingStart = null
                    activity.stopService(Intent(activity, PttForegroundService::class.java))
                    result.success(null)
                }
                "setVolumeKeyPtt" -> {
                    volumeKeyPtt = call.arguments == true
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun emit(event: String) {
        mainHandler.post { sink?.success(event) }
    }

    /** Hold-to-talk from keys while the activity has focus. */
    fun handleKey(event: KeyEvent): Boolean {
        if (!active) return false
        val isPttKey = when (event.keyCode) {
            KeyEvent.KEYCODE_HEADSETHOOK, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> true
            KeyEvent.KEYCODE_VOLUME_DOWN -> volumeKeyPtt
            else -> false
        }
        if (!isPttKey) return false
        when (event.action) {
            KeyEvent.ACTION_DOWN -> if (event.repeatCount == 0) emit("down")
            KeyEvent.ACTION_UP -> emit("up")
        }
        return true
    }

    fun onPermissionsResult(activity: Activity) {
        val intent = pendingStart ?: return
        pendingStart = null
        if (hasMicrophone(activity)) {
            startService(activity, intent)
        } else {
            emit("service_error:microphone_permission")
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun startService(activity: Activity, intent: Intent) {
        // Android 14 refuses a microphone foreground service without the
        // runtime permission, so ask first and start from the result.
        val missing = mutableListOf<String>()
        if (!hasMicrophone(activity)) missing += Manifest.permission.RECORD_AUDIO
        if (Build.VERSION.SDK_INT >= 33 &&
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            missing += Manifest.permission.POST_NOTIFICATIONS
        }
        if (missing.isNotEmpty()) {
            pendingStart = intent
            activity.requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST)
            if (missing.contains(Manifest.permission.RECORD_AUDIO)) return
        }
        active = true
        if (Build.VERSION.SDK_INT >= 26) {
            activity.startForegroundService(intent)
        } else {
            activity.startService(intent)
        }
    }

    private fun hasMicrophone(context: Context) =
        context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun serviceIntent(context: Context, args: Map<*, *>?) =
        Intent(context, PttForegroundService::class.java).apply {
            action = PttForegroundService.ACTION_UPDATE
            putExtra(PttForegroundService.EXTRA_CHANNEL, args?.get("channel") as? String ?: "-")
            putExtra(PttForegroundService.EXTRA_STATUS, args?.get("status") as? String ?: "")
        }
}
