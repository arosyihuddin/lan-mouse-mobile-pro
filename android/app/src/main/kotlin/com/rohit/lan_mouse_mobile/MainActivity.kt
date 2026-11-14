package com.rohit.lan_mouse_mobile

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

/// The Flutter engine is cached and NOT destroyed with this
/// activity. The client-mode listener lives in the Dart isolate
/// (its DTLS session is driven through flutter_rust_bridge), so
/// when Android destroys the activity - e.g. the user swipes the
/// app from Recents - a default FlutterActivity would tear the
/// engine down with it and the desktop connection would die even
/// though the process (and its foreground service) lives on.
/// With a cached engine the isolate, the listener and the session
/// survive; reopening the app reattaches to the same engine.
class MainActivity : FlutterActivity() {

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        var engine = FlutterEngineCache.getInstance().get(ENGINE_ID)
        if (engine == null) {
            engine = FlutterEngine(context.applicationContext)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault(),
            )
            GeneratedPluginRegistrant.registerWith(engine)
            FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        }
        return engine
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

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

    companion object {
        private const val ENGINE_ID = "lan_mouse_engine"
    }
}
