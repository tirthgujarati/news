package com.tirth.newsapp

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * "apex/native": what the Dart side needs from Android. Registered on the app
 * engine (with the activity, for permission prompts) and on the background
 * Flash engine (without).
 */
object ApexNative {
    fun register(engine: FlutterEngine, ctx: Context, activity: Activity?) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "apex/native").setMethodCallHandler { call, result ->
            val app = ctx.applicationContext
            when (call.method) {
                "secret" -> result.success(Secrets.get(app, call.argument<String>("name")!!))
                "setSecret" -> {
                    Secrets.set(app, call.argument<String>("name")!!, call.argument<String>("value"))
                    result.success(null)
                }
                "alert" -> {
                    Alerts.show(
                        app,
                        call.argument<Int>("id")!!,
                        call.argument<Boolean>("loud")!!,
                        call.argument<String>("title")!!,
                        call.argument<String>("text")!!,
                        call.argument<String>("eventId")!!
                    )
                    result.success(null)
                }
                "cancelAlert" -> {
                    Alerts.cancel(app, call.argument<Int>("id")!!)
                    result.success(null)
                }
                "dismissSource" -> {
                    try {
                        FlashListener.instance?.cancelNotification(call.argument<String>("key")!!)
                    } catch (_: Exception) {
                    }
                    result.success(null)
                }
                "changed" -> {
                    FlashHub.changed()
                    result.success(null)
                }
                "status" -> {
                    val nm = app.getSystemService(NotificationManager::class.java)
                    val pm = app.getSystemService(PowerManager::class.java)
                    val telegram = FlashListener.TELEGRAM.any {
                        try {
                            app.packageManager.getPackageInfo(it, 0); true
                        } catch (_: Exception) {
                            false
                        }
                    }
                    result.success(
                        mapOf(
                            "listener" to nm.isNotificationListenerAccessGranted(
                                ComponentName(app, FlashListener::class.java)
                            ),
                            "notifications" to nm.areNotificationsEnabled(),
                            "battery" to pm.isIgnoringBatteryOptimizations(app.packageName),
                            "telegram" to telegram,
                            "engine" to FlashHub.running
                        )
                    )
                }
                "openListenerSettings" -> {
                    app.startActivity(
                        Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                            .putExtra(
                                Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                                ComponentName(app, FlashListener::class.java).flattenToString()
                            )
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                }
                "requestNotifications" -> {
                    activity?.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7)
                    result.success(null)
                }
                "openBatterySettings" -> {
                    app.startActivity(
                        Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                            .setData(Uri.parse("package:${app.packageName}"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                }
                "startEngine" -> {
                    FlashHub.ensureStarted(app)
                    result.success(null)
                }
                "setWatch" -> {
                    if (call.argument<Boolean>("on") == true) WatchService.start(app) else WatchService.stop(app)
                    result.success(null)
                }
                "settingsChanged" -> {
                    FlashHub.settingsChanged()
                    result.success(null)
                }
                "takeLaunchEvent" -> {
                    val id = activity?.intent?.getStringExtra(Alerts.EXTRA_EVENT)
                    activity?.intent?.removeExtra(Alerts.EXTRA_EVENT)
                    result.success(id)
                }
                else -> result.notImplemented()
            }
        }
    }
}
