package cz.tacticalcar.tactical_car_app.car

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.RemoteInput

/** Reply / mark-as-read from the message notification (phone or car). */
class MessageActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val groupId = intent.getStringExtra(MessageNotifier.EXTRA_GROUP) ?: return
        when (intent.action) {
            MessageNotifier.ACTION_REPLY -> {
                val text = RemoteInput.getResultsFromIntent(intent)
                    ?.getCharSequence(MessageNotifier.REPLY_KEY)
                    ?.toString()
                    ?.trim()
                if (!text.isNullOrEmpty()) {
                    CarBridge.emitReply(groupId, text)
                    MessageNotifier.appendOwnReply(context, groupId, text)
                }
            }
            MessageNotifier.ACTION_MARK_READ -> MessageNotifier.markRead(context, groupId)
        }
    }
}
