package com.receiptnest.mobile

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.time.ZoneId

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.receiptnest.mobile/device"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getTimeZone" -> result.success(ZoneId.systemDefault().id)
                else -> result.notImplemented()
            }
        }
    }
}
