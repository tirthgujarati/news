package com.tirth.newsapp

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Runs the Flash engine (Dart, `flashMain`) in its own background Flutter
 * engine, so headlines are judged and alerts sent with the app closed.
 * Telegram notifications are queued until the engine says it's ready.
 */
object FlashHub {
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var ready = false
    private val queue = ArrayDeque<Map<String, Any?>>()
    private val main = Handler(Looper.getMainLooper())

    /** Called when flash.json changes, so the open app can reload. */
    var onChanged: (() -> Unit)? = null

    val running: Boolean get() = engine != null

    fun ensureStarted(context: Context) {
        main.post { start(context.applicationContext) }
    }

    private fun start(ctx: Context) {
        if (engine != null) return
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(ctx)
        loader.ensureInitializationComplete(ctx, null)
        val e = FlutterEngine(ctx)
        ApexNative.register(e, ctx, activity = null)
        val ch = MethodChannel(e.dartExecutor.binaryMessenger, "apex/flash")
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    ready = true
                    flush()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        engine = e
        channel = ch
        e.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "flashMain")
        )
    }

    /** A Telegram notification for the engine. */
    fun deliver(context: Context, item: Map<String, Any?>) {
        main.post {
            start(context.applicationContext)
            queue.addLast(item)
            if (queue.size > 200) queue.removeFirst()
            flush()
        }
    }

    /** Tells the engine to read its settings again (watch mode switched). */
    fun settingsChanged() {
        main.post { if (ready) channel?.invokeMethod("settings", null) }
    }

    private fun flush() {
        if (!ready) return
        val ch = channel ?: return
        while (queue.isNotEmpty()) ch.invokeMethod("telegram", queue.removeFirst())
    }

    fun changed() {
        main.post { onChanged?.invoke() }
    }
}
