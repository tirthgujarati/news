package com.tirth.newsapp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent

/** Flash notifications (HOT with sound, WATCH silent) and new editions. */
object Alerts {
    const val HOT = "flash_hot"
    const val WATCH = "flash_watch"
    const val SERVICE = "flash_service"
    const val EDITIONS = "editions"
    private const val EDITION_ID = 9001
    const val EXTRA_EVENT = "flash_event"

    fun createChannels(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(HOT, "HOT news", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Market-moving news, with sound"
                enableVibration(true)
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(WATCH, "Watch news", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Worth knowing, no sound"
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(EDITIONS, "New editions", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "When the morning, midday and evening editions arrive"
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(SERVICE, "Market watcher", NotificationManager.IMPORTANCE_MIN).apply {
                description = "Shown while apex watches the markets in the background"
            }
        )
    }

    private fun openApp(ctx: Context, eventId: String?, requestCode: Int): PendingIntent {
        val intent = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (eventId != null) putExtra(EXTRA_EVENT, eventId)
        }
        return PendingIntent.getActivity(
            ctx, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun show(ctx: Context, id: Int, loud: Boolean, title: String, text: String, eventId: String) {
        createChannels(ctx)
        val n = Notification.Builder(ctx, if (loud) HOT else WATCH)
            .setSmallIcon(R.drawable.ic_stat_flash)
            .setContentTitle(title)
            .setContentText(text.lineSequence().firstOrNull() ?: "")
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(openApp(ctx, eventId, id))
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_MESSAGE)
            // Later updates (Claude, then Opus) replace the text without a new sound.
            .setOnlyAlertOnce(!loud)
            .setGroup("flash")
            .build()
        ctx.getSystemService(NotificationManager::class.java).notify(id, n)
    }

    /** "Midday Edition is ready" (replaces the previous one). */
    fun edition(ctx: Context, title: String, text: String) {
        createChannels(ctx)
        val n = Notification.Builder(ctx, EDITIONS)
            .setSmallIcon(R.drawable.ic_stat_flash)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(openApp(ctx, null, EDITION_ID))
            .setAutoCancel(true)
            .build()
        ctx.getSystemService(NotificationManager::class.java).notify(EDITION_ID, n)
    }

    fun cancel(ctx: Context, id: Int) {
        ctx.getSystemService(NotificationManager::class.java).cancel(id)
    }

    fun serviceNotification(ctx: Context): Notification {
        createChannels(ctx)
        return Notification.Builder(ctx, SERVICE)
            .setSmallIcon(R.drawable.ic_stat_flash)
            .setContentTitle("apex is watching the markets")
            .setContentText("Squawk channels and prices, for Flash alerts")
            .setContentIntent(openApp(ctx, null, 0))
            .setOngoing(true)
            .build()
    }
}
