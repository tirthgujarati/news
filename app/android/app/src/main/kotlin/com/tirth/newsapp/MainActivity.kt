package com.tirth.newsapp

import android.content.Intent
import android.os.Process
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var flashUi: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Lets the app measure tap-to-readable time for Settings ("Opened in").
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "apex/startup")
            .setMethodCallHandler { call, result ->
                if (call.method == "msSinceProcessStart") {
                    result.success(SystemClock.elapsedRealtime() - Process.getStartElapsedRealtime())
                } else {
                    result.notImplemented()
                }
            }
        ApexNative.register(flutterEngine, this, this)
        // The background Flash engine pings here when it saves new results.
        val ui = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "apex/flashui")
        flashUi = ui
        FlashHub.onChanged = { ui.invokeMethod("changed", null) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // A Flash notification was tapped while the app was open.
        intent.getStringExtra(Alerts.EXTRA_EVENT)?.let { flashUi?.invokeMethod("open", it) }
    }

    override fun onDestroy() {
        FlashHub.onChanged = null
        super.onDestroy()
    }
}
