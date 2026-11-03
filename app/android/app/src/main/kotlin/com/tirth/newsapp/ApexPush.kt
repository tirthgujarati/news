package com.tirth.newsapp

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Pushes from GitHub (tools/notify.py) through Firebase Cloud Messaging:
 * "edition" when a new edition is published, "flash" when the Opus flash
 * desk has written its answer. Only works once the app was built with the
 * Firebase config (google-services.json); without it, nothing arrives.
 */
class ApexPushService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val d = message.data
        when (d["type"]) {
            "edition" -> Alerts.edition(this, d["title"] ?: "New edition", d["text"] ?: "")
            // The engine reads the answer now instead of at its next check.
            "flash" -> d["issue"]?.toIntOrNull()?.let { FlashHub.deskReady(this, it) }
        }
    }

    override fun onNewToken(token: String) {
        // Topics are kept across new tokens; nothing to send anywhere.
    }
}

object Push {
    private const val EDITIONS = "editions"
    private const val FLASH = "flash"

    /** True when the app was built with the Firebase config. */
    fun available(ctx: Context): Boolean = try {
        FirebaseApp.getApps(ctx).isNotEmpty()
    } catch (_: Exception) {
        false
    }

    /** Opus answers always; editions when [editions] is on. */
    fun subscribe(ctx: Context, editions: Boolean) {
        if (!available(ctx)) return
        try {
            val m = FirebaseMessaging.getInstance()
            m.subscribeToTopic(FLASH)
            if (editions) m.subscribeToTopic(EDITIONS) else m.unsubscribeFromTopic(EDITIONS)
        } catch (_: Exception) {
        }
    }
}
