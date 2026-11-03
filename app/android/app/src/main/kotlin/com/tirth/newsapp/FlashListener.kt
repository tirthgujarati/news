package com.tirth.newsapp

import android.app.Notification
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Reads Telegram's notifications (with the access you grant in Settings)
 * the moment they arrive, and hands channel posts to the Flash engine.
 * No polling: Telegram's own push does the fast part.
 */
class FlashListener : NotificationListenerService() {

    companion object {
        /** The official app, its web build, and Telegram X. */
        val TELEGRAM = setOf("org.telegram.messenger", "org.telegram.messenger.web", "org.thunderdog.challegram")

        @Volatile
        var instance: FlashListener? = null
    }

    /** Recently delivered (channel + text), so a re-posted notification isn't sent twice. */
    private val seen = LinkedHashSet<String>()

    override fun onListenerConnected() {
        instance = this
        FlashHub.ensureStarted(this)
    }

    override fun onListenerDisconnected() {
        instance = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName !in TELEGRAM) return
        val n = sbn.notification
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val ex = n.extras
        val title = (ex.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)
            ?: ex.getCharSequence(Notification.EXTRA_TITLE))?.toString() ?: return

        // Telegram uses MessagingStyle: one notification lists the recent posts.
        val posts = mutableListOf<Pair<String, Long>>()
        val messages = ex.getParcelableArray(Notification.EXTRA_MESSAGES, Bundle::class.java)
        if (messages != null && messages.isNotEmpty()) {
            for (m in messages) {
                val text = m.getCharSequence("text")?.toString() ?: continue
                posts.add(text to m.getLong("time", sbn.postTime))
            }
        } else {
            val text = (ex.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: ex.getCharSequence(Notification.EXTRA_TEXT))?.toString() ?: return
            posts.add(text to sbn.postTime)
        }

        for ((text, time) in posts) {
            val id = "$title|$text"
            if (!seen.add(id)) continue
            if (seen.size > 300) seen.remove(seen.first())
            FlashHub.deliver(
                this,
                mapOf("title" to title, "text" to text, "at" to time, "key" to sbn.key)
            )
        }
    }
}
