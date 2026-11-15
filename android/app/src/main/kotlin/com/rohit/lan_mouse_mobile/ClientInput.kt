package com.rohit.lan_mouse_mobile

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.net.wifi.WifiManager
import android.os.PowerManager
import android.view.inputmethod.InputMethodManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Routes the Dart client-mode channel (`lan_mouse_mobile/client_input`)
/// to the injection services. Input operations are no-ops when the
/// relevant service is not running (accessibility off, or our IME
/// not selected), so the Dart side never has to care.
object ClientInputDispatcher {

    /// Set by MainActivity; needed to open Android settings screens.
    var activity: Activity? = null

    /// The same channel, kept so the Android side can call INTO
    /// Dart (currently: 'requestLeave' from the accessibility
    /// service when the cursor hits the exit edge).
    var channel: MethodChannel? = null

    /// Application context for secure-settings writes (IME
    /// auto-switching); set by MainActivity.
    var appContext: Context? = null

    private const val OUR_IME_ID =
        "com.rohit.lan_mouse_mobile/.LanMouseImeService"
    private var previousIme: String? = null

    /// Makes the Lan Mouse keyboard the active IME while the
    /// desktop's pointer is here, remembering the previous one.
    /// Needs WRITE_SECURE_SETTINGS (grantable via adb for this
    /// sideloaded app); without it this silently does nothing and
    /// switching stays manual.
    fun switchImeToOurs() {
        val ctx = appContext ?: return
        try {
            val current = Settings.Secure.getString(
                ctx.contentResolver,
                Settings.Secure.DEFAULT_INPUT_METHOD,
            )
            if (current == OUR_IME_ID) return
            previousIme = current
            Settings.Secure.putString(
                ctx.contentResolver,
                Settings.Secure.DEFAULT_INPUT_METHOD,
                OUR_IME_ID,
            )
        } catch (e: SecurityException) {
            // Permission not granted: manual switching only.
        }
    }

    /// Restores the keyboard that was active before [switchImeToOurs].
    /// If nothing was recorded (e.g. the user had already selected
    /// our IME by hand, or the app restarted mid-session), fall back
    /// to Gboard when it is enabled, otherwise to the first other
    /// enabled keyboard — otherwise the phone would stay on the Lan
    /// Mouse keyboard forever after the pointer leaves.
    fun restorePreviousIme() {
        val ctx = appContext ?: return
        val prev = previousIme ?: findFallbackIme(ctx)
        previousIme = null
        if (prev == null || prev == OUR_IME_ID) return
        try {
            Settings.Secure.putString(
                ctx.contentResolver,
                Settings.Secure.DEFAULT_INPUT_METHOD,
                prev,
            )
        } catch (e: SecurityException) {
            // Permission not granted: nothing was switched either.
        }
    }

    private fun findFallbackIme(ctx: Context): String? {
        val enabled = try {
            Settings.Secure.getString(
                ctx.contentResolver,
                Settings.Secure.ENABLED_INPUT_METHODS,
            )
        } catch (_: Exception) {
            null
        } ?: return null
        val ids = enabled.split(':')
            .map { it.substringBefore(';').trim() }
            .filter { it.isNotEmpty() && it != OUR_IME_ID }
        return ids.firstOrNull { it.contains("inputmethod.latin") }
            ?: ids.firstOrNull()
    }

    fun requestLeave() {
        channel?.invokeMethod("requestLeave", null)
    }

    /// The foreground service notification's Stop action: asks
    /// Dart to end the listening session.
    fun requestStopListening() {
        channel?.invokeMethod("requestStopListening", null)
    }

    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null

    /// Holds the radio and CPU awake for a listening session.
    fun acquireLocks() {
        val ctx = appContext ?: return
        try {
            if (wifiLock == null) {
                val wm = ctx.applicationContext
                    .getSystemService(Context.WIFI_SERVICE) as WifiManager
                @Suppress("DEPRECATION")
                wifiLock = wm.createWifiLock(
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY,
                    "lan_mouse_listen",
                ).apply { setReferenceCounted(false) }
            }
            if (wifiLock?.isHeld != true) wifiLock?.acquire()
        } catch (e: Exception) {
            // Lock unsupported on this device: best effort only.
        }
        try {
            if (wakeLock == null) {
                val pm = ctx.applicationContext
                    .getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "lan_mouse:listen",
                ).apply { setReferenceCounted(false) }
            }
            if (wakeLock?.isHeld != true) {
                wakeLock?.acquire(6 * 60 * 60 * 1000L)
            }
        } catch (e: Exception) {
            // Best effort only.
        }
    }

    /// Releases the locks taken by [acquireLocks].
    fun releaseLocks() {
        try {
            if (wifiLock?.isHeld == true) wifiLock?.release()
        } catch (e: Exception) {
            // Already released.
        }
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (e: Exception) {
            // Already released.
        }
    }

    /// Android 13+ hides the foreground-service notification
    /// unless POST_NOTIFICATIONS is granted; the service still
    /// protects the process without it, but the user should get
    /// the visible Stop affordance. Asked once per session start;
    /// the system itself rate-limits repeat prompts.
    private fun ensureNotificationPermission() {
        val act = activity ?: return
        if (android.os.Build.VERSION.SDK_INT < 33) return
        val granted = androidx.core.content.ContextCompat
            .checkSelfPermission(
                act,
                android.Manifest.permission.POST_NOTIFICATIONS,
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!granted) {
            androidx.core.app.ActivityCompat.requestPermissions(
                act,
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                4243,
            )
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        val service = LanMouseAccessibilityService.instance
        when (call.method) {
            "move" -> service?.moveBy(
                call.argument<Double>("dx") ?: 0.0,
                call.argument<Double>("dy") ?: 0.0,
            )
            "button" -> service?.onButton(
                call.argument<Int>("button") ?: 0,
                call.argument<Boolean>("down") ?: false,
            )
            "scroll" -> service?.onScroll(
                call.argument<Int>("axis") ?: 1,
                call.argument<Double>("value") ?: 0.0,
            )
            "scrollDiscrete" -> service?.onScrollDiscrete(
                call.argument<Int>("axis") ?: 1,
                call.argument<Int>("value") ?: 0,
            )
            "key" -> {
                val k = call.argument<Int>("key") ?: 0
                val d = call.argument<Boolean>("down") ?: false
                LanMouseImeService.instance?.handleKey(k, d)
            }
            "modifiers" -> {
                val depressed = call.argument<Int>("depressed") ?: 0
                val locked = call.argument<Int>("locked") ?: 0
                ClientInputState.modifiersDepressed = depressed
                ClientInputState.modifiersLocked = locked
                LanMouseImeService.instance?.onModifiers(depressed, locked)
            }
            "enter" -> {
                service?.onEnter(call.argument<Int>("position") ?: 1)
                switchImeToOurs()
                LanMouseImeService.instance?.resetModifiers()
                ClipboardSync.discover()
            }
            "leave" -> {
                service?.onLeave()
                restorePreviousIme()
                LanMouseImeService.instance?.resetModifiers()
                ClipboardSync.pushCurrentClipboard()
            }
            "sessionEnded" -> {
                service?.onSessionEnded()
                restorePreviousIme()
                LanMouseImeService.instance?.resetModifiers()
            }
            "acquireLocks" -> acquireLocks()
            "releaseLocks" -> releaseLocks()
            "clipboardStart" -> ClipboardSync.start()
            "clipboardStop" -> ClipboardSync.stop()
            "fgStart" -> {
                appContext?.let { LanMouseForegroundService.start(it) }
                ensureNotificationPermission()
            }
            "fgStop" -> appContext?.let {
                LanMouseForegroundService.stop(it)
            }
            "isAccessibilityEnabled" -> {
                result.success(service != null)
                return
            }
            "openAccessibilitySettings" -> openSettings(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            "openInputMethodSettings" -> openSettings(Settings.ACTION_INPUT_METHOD_SETTINGS)
            "showInputMethodPicker" -> {
                val imm = activity?.getSystemService(Context.INPUT_METHOD_SERVICE)
                    as? InputMethodManager
                imm?.showInputMethodPicker()
            }
            else -> {
                result.notImplemented()
                return
            }
        }
        result.success(null)
    }

    private fun openSettings(action: String) {
        val intent = Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        activity?.startActivity(intent)
    }
}
