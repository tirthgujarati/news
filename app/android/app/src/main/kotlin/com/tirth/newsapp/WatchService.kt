package com.tirth.newsapp

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder

/**
 * "Faster when closed": keeps apex running with a small ongoing
 * notification, so the Flash engine can read the channels' public pages and
 * watch prices even without Telegram's notifications.
 */
class WatchService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(1, Alerts.serviceNotification(this), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        FlashHub.ensureStarted(this)
        FlashHub.settingsChanged()
        return START_STICKY
    }

    companion object {
        fun start(ctx: Context) {
            ctx.startForegroundService(Intent(ctx, WatchService::class.java))
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, WatchService::class.java))
            FlashHub.settingsChanged()
        }
    }
}
