package com.rohit.lan_mouse_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ClientInputDispatcher.activity = this
        ClientInputDispatcher.appContext = applicationContext
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "lan_mouse_mobile/client_input",
        )
        ClientInputDispatcher.channel = channel
        channel.setMethodCallHandler { call, result ->
            ClientInputDispatcher.handle(call, result)
        }
    }
}
