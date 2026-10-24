package cz.tacticalcar.tactical_car_app.car

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.app.RemoteInput

/**
 * Incoming mesh messages as MessagingStyle notifications with reply and
 * mark-as-read actions: the format Android Auto reads aloud and answers
 * by voice. One conversation per communication group.
 */
object MessageNotifier {
    const val CHANNEL_ID = "mesh_messages"
    const val ACTION_REPLY = "cz.tacticalcar.car.REPLY"
    const val ACTION_MARK_READ = "cz.tacticalcar.car.MARK_READ"
    const val EXTRA_GROUP = "groupId"
    const val REPLY_KEY = "reply"

    private val conversations = mutableMapOf<String, NotificationCompat.MessagingStyle>()
    private val self = Person.Builder().setName("Já").setKey("self").build()

    fun show(
        context: Context,
        groupId: String,
        groupName: String,
        sender: String,
        body: String,
        timestamp: Long,
    ) {
        ensureChannel(context)
        val style = conversations.getOrPut(groupId) {
            NotificationCompat.MessagingStyle(self)
                .setConversationTitle(groupName)
                .setGroupConversation(true)
        }
        style.addMessage(body, timestamp, Person.Builder().setName(sender).setKey(sender).build())
        post(context, groupId, style)
    }

    fun appendOwnReply(context: Context, groupId: String, text: String) {
        val style = conversations[groupId] ?: return
        style.addMessage(text, System.currentTimeMillis(), self)
        post(context, groupId, style)
    }

    fun markRead(context: Context, groupId: String) {
        conversations.remove(groupId)
        NotificationManagerCompat.from(context).cancel(notificationId(groupId))
    }

    fun clearAll(context: Context) {
        conversations.keys.toList().forEach { markRead(context, it) }
    }

    private fun post(context: Context, groupId: String, style: NotificationCompat.MessagingStyle) {
        val replyIntent = PendingIntent.getBroadcast(
            context,
            notificationId(groupId),
            Intent(context, MessageActionReceiver::class.java)
                .setAction(ACTION_REPLY)
                .putExtra(EXTRA_GROUP, groupId),
            // RemoteInput fills the intent, so it must stay mutable.
            PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0),
        )
        val readIntent = PendingIntent.getBroadcast(
            context,
            notificationId(groupId) + 1,
            Intent(context, MessageActionReceiver::class.java)
                .setAction(ACTION_MARK_READ)
                .putExtra(EXTRA_GROUP, groupId),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val reply = NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_send,
            "Odpovědět",
            replyIntent,
        )
            .addRemoteInput(RemoteInput.Builder(REPLY_KEY).setLabel("Odpověď").build())
            .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_REPLY)
            .setShowsUserInterface(false)
            .build()
        val markRead = NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_close_clear_cancel,
            "Přečteno",
            readIntent,
        )
            .setSemanticAction(NotificationCompat.Action.SEMANTIC_ACTION_MARK_AS_READ)
            .setShowsUserInterface(false)
            .build()
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setStyle(style)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .addAction(reply)
            .addInvisibleAction(markRead)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(notificationId(groupId), notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS not granted; messages stay in the app.
        }
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Zprávy týmu", NotificationManager.IMPORTANCE_HIGH),
            )
        }
    }

    private fun notificationId(groupId: String) = 5000 + (groupId.hashCode() and 0xfff) * 2
}
