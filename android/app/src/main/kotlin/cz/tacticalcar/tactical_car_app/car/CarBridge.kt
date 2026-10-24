package cz.tacticalcar.tactical_car_app.car

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * `tactical/car` (method): updateTargets, notifyMessage, clearMessages.
 * `tactical/car_events` (event): replies dictated in the car,
 * `{type: "reply", groupId, text}`. Replies arriving while Flutter is not
 * listening are queued.
 */
object CarBridge : EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private val pending = mutableListOf<Map<String, Any>>()

    fun attach(messenger: BinaryMessenger, context: Context) {
        val appContext = context.applicationContext
        EventChannel(messenger, "tactical/car_events").setStreamHandler(this)
        MethodChannel(messenger, "tactical/car").setMethodCallHandler { call, result ->
            when (call.method) {
                "updateTargets" -> {
                    val items = (call.arguments as? List<*>).orEmpty().mapNotNull { item ->
                        val map = item as? Map<*, *> ?: return@mapNotNull null
                        CarTarget(
                            title = map["title"] as? String ?: return@mapNotNull null,
                            kind = map["kind"] as? String ?: "",
                            latitude = (map["latitude"] as? Number)?.toDouble() ?: return@mapNotNull null,
                            longitude = (map["longitude"] as? Number)?.toDouble() ?: return@mapNotNull null,
                            distanceKm = (map["distanceKm"] as? Number)?.toDouble() ?: 0.0,
                            bearingDeg = (map["bearingDeg"] as? Number)?.toDouble() ?: 0.0,
                            priority = map["priority"] == true,
                        )
                    }
                    CarDataStore.update(items)
                    result.success(null)
                }
                "notifyMessage" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args != null) {
                        MessageNotifier.show(
                            appContext,
                            groupId = args["groupId"] as? String ?: "alpha",
                            groupName = args["groupName"] as? String ?: "ALPHA",
                            sender = args["sender"] as? String ?: "?",
                            body = args["body"] as? String ?: "",
                            timestamp = (args["timestamp"] as? Number)?.toLong()
                                ?: System.currentTimeMillis(),
                        )
                    }
                    result.success(null)
                }
                "clearMessages" -> {
                    MessageNotifier.clearAll(appContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun emitReply(groupId: String, text: String) {
        val event = mapOf("type" to "reply", "groupId" to groupId, "text" to text)
        mainHandler.post {
            val current = sink
            if (current == null) pending += event else current.success(event)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        pending.forEach { events.success(it) }
        pending.clear()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }
}
