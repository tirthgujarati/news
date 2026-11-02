package com.tirth.newsapp

import android.os.Process
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
    }
}
