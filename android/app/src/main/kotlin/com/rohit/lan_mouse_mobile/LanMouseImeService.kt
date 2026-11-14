package com.rohit.lan_mouse_mobile

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.inputmethodservice.InputMethodService
import android.os.SystemClock
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.LinearLayout
import android.widget.TextView

/// The keyboard half of client mode.
///
/// Android only lets an app put text and key events into other apps
/// when it is the active input method, so received desktop keys are
/// handled here: printable characters are committed as text (US
/// layout, honoring the desktop's shift/caps state), editing and
/// navigation keys are sent as real key events, and Ctrl+letter
/// combinations go out as key events with the Ctrl meta bit — enough
/// for copy/paste/select-all in most apps.
///
/// When this IME is not the selected keyboard, received keys simply
/// have nowhere to go; the client-mode screen says so.
class LanMouseImeService : InputMethodService() {

    companion object {
        @Volatile
        var instance: LanMouseImeService? = null
            private set

        // evdev scancode -> (unshifted, shifted), US layout.
        private val PUNCT: Map<Int, Pair<Char, Char>> = mapOf(
            2 to ('1' to '!'), 3 to ('2' to '@'), 4 to ('3' to '#'),
            5 to ('4' to '$'), 6 to ('5' to '%'), 7 to ('6' to '^'),
            8 to ('7' to '&'), 9 to ('8' to '*'), 10 to ('9' to '('),
            11 to ('0' to ')'), 12 to ('-' to '_'), 13 to ('=' to '+'),
            26 to ('[' to '{'), 27 to (']' to '}'),
            39 to (';' to ':'), 40 to ('\'' to '"'), 41 to ('`' to '~'),
            43 to ('\\' to '|'),
            51 to (',' to '<'), 52 to ('.' to '>'), 53 to ('/' to '?'),
            57 to (' ' to ' '),
        )

        // evdev scancode -> Android key code, for keys that must be
        // delivered as events rather than text.
        private val SPECIAL_KEYS: Map<Int, Int> = mapOf(
            1 to KeyEvent.KEYCODE_ESCAPE,
            14 to KeyEvent.KEYCODE_DEL,
            15 to KeyEvent.KEYCODE_TAB,
            28 to KeyEvent.KEYCODE_ENTER,
            102 to KeyEvent.KEYCODE_MOVE_HOME,
            107 to KeyEvent.KEYCODE_MOVE_END,
            103 to KeyEvent.KEYCODE_DPAD_UP,
            108 to KeyEvent.KEYCODE_DPAD_DOWN,
            105 to KeyEvent.KEYCODE_DPAD_LEFT,
            106 to KeyEvent.KEYCODE_DPAD_RIGHT,
            104 to KeyEvent.KEYCODE_PAGE_UP,
            109 to KeyEvent.KEYCODE_PAGE_DOWN,
            111 to KeyEvent.KEYCODE_FORWARD_DEL,
            110 to KeyEvent.KEYCODE_INSERT,
            59 to KeyEvent.KEYCODE_F1,
            60 to KeyEvent.KEYCODE_F2,
            61 to KeyEvent.KEYCODE_F3,
            62 to KeyEvent.KEYCODE_F4,
            63 to KeyEvent.KEYCODE_F5,
            64 to KeyEvent.KEYCODE_F6,
            65 to KeyEvent.KEYCODE_F7,
            66 to KeyEvent.KEYCODE_F8,
            67 to KeyEvent.KEYCODE_F9,
            68 to KeyEvent.KEYCODE_F10,
            87 to KeyEvent.KEYCODE_F11,
            88 to KeyEvent.KEYCODE_F12,
        )

        // evdev number row -> Android digit keycodes, for
        // Ctrl+1..0 style shortcuts (plain digit typing uses the
        // character path).
        private val DIGIT_KEYS: Map<Int, Int> = mapOf(
            2 to KeyEvent.KEYCODE_1,
            3 to KeyEvent.KEYCODE_2,
            4 to KeyEvent.KEYCODE_3,
            5 to KeyEvent.KEYCODE_4,
            6 to KeyEvent.KEYCODE_5,
            7 to KeyEvent.KEYCODE_6,
            8 to KeyEvent.KEYCODE_7,
            9 to KeyEvent.KEYCODE_8,
            10 to KeyEvent.KEYCODE_9,
            11 to KeyEvent.KEYCODE_0,
        )
    }

    private var shiftOn = false
    private var ctrlOn = false
    private var altOn = false
    private var capsLock = false

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onCreateInputView(): View {
        // A slim bar, not a full keyboard: an InputMethodService is
        // a software keyboard by definition, so its window always
        // exists while it is active (a zero-height view still
        // renders as a dark strip on some ROMs). Only a real HID
        // device (e.g. a Bluetooth keyboard) is classified as a
        // physical keyboard and shows no window at all.
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setBackgroundColor(0xFF22222C.toInt())
            setPadding(36, 28, 36, 28)
        }
        val label = TextView(this).apply {
            text = if (java.util.Locale.getDefault().language == "id") {
                "Lan Mouse Pro Keyboard — ketik dari PC. Ketuk untuk mengganti keyboard."
            } else {
                "Lan Mouse Pro Keyboard — type from your PC. Tap to switch keyboards."
            }
            setTextColor(0xFFF2F2F7.toInt())
            textSize = 14f
        }
        bar.addView(label)
        bar.setOnClickListener {
            val imm = getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
            imm.showInputMethodPicker()
        }
        return bar
    }

    fun onModifiers(depressed: Int, locked: Int) {
        // This desktop's KeyboardModifiers events arrive empty
        // (depressed/locked always 0), so an all-zero update must not
        // clear the state tracked from the modifier key events in
        // handleKey. A non-zero update (a healthy desktop) still
        // syncs; releases are covered by the key events themselves.
        if (depressed == 0 && locked == 0) return
        shiftOn = (depressed and 0x01) != 0
        capsLock = (locked and 0x02) != 0
        ctrlOn = (depressed and 0x04) != 0
        altOn = (depressed and 0x08) != 0
    }

    /// Clears held-modifier state at session boundaries: a modifier
    /// released after the pointer has left would otherwise stick.
    fun resetModifiers() {
        ctrlOn = false
        shiftOn = false
        altOn = false
    }

    /// Clipboard access for ClipboardSync. As the selected input
    /// method this service may read and write the system clipboard
    /// even while another app is in front (Android 10+ restriction).
    fun setClipboardText(text: String) {
        val cm = getSystemService(
            Context.CLIPBOARD_SERVICE,
        ) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("lan-mouse", text))
    }

    fun getClipboardText(): String? {
        val cm = getSystemService(
            Context.CLIPBOARD_SERVICE,
        ) as ClipboardManager
        val clip = cm.primaryClip ?: return null
        if (clip.itemCount == 0) return null
        return clip.getItemAt(0).coerceToText(this)?.toString()
    }

    private fun currentMeta(): Int {
        var meta = 0
        if (ctrlOn) meta = meta or KeyEvent.META_CTRL_ON
        if (shiftOn) meta = meta or KeyEvent.META_SHIFT_ON
        if (altOn) meta = meta or KeyEvent.META_ALT_ON
        return meta
    }

    private fun keycodeFor(key: Int): Int? {
        SPECIAL_KEYS[key]?.let { return it }
        letterFor(key)?.let { return KeyEvent.KEYCODE_A + (it - 'a') }
        return DIGIT_KEYS[key]
    }

    fun handleKey(key: Int, down: Boolean) {
        // Modifier state is tracked from the modifier key events
        // themselves (evdev 29/97 ctrl, 42/54 shift, 56/100 alt,
        // 58 caps lock): they always arrive, while this desktop's
        // KeyboardModifiers events arrive empty (see onModifiers).
        when (key) {
            29, 97 -> ctrlOn = down
            42, 54 -> shiftOn = down
            56, 100 -> altOn = down
            58 -> if (down) capsLock = !capsLock
        }
        val shifted = shiftOn || capsLock
        val ic = currentInputConnection ?: return
        // Anything that maps to a real Android keycode goes out as
        // a key event carrying the live modifier state whenever
        // Ctrl or Alt is held (shortcuts: Ctrl+A/C/V, Ctrl+Backspace
        // for delete-word, Ctrl+arrows, Ctrl+1..0, Alt+Tab) — and
        // special keys always go as key events, so Shift+arrows
        // select text and Shift+Tab moves focus backwards, like a
        // real keyboard. Plain typing keeps the commitText path.
        if (SPECIAL_KEYS.containsKey(key) || ctrlOn || altOn) {
            val code = keycodeFor(key) ?: return
            val action = if (down) KeyEvent.ACTION_DOWN else KeyEvent.ACTION_UP
            val now = SystemClock.uptimeMillis()
            ic.sendKeyEvent(KeyEvent(now, now, action, code, 0, currentMeta()))
            return
        }
        if (!down) return
        val ch = charFor(key, shifted) ?: return
        ic.commitText(ch.toString(), 1)
    }

    private fun letterFor(key: Int): Char? = when (key) {
        16 -> 'q'; 17 -> 'w'; 18 -> 'e'; 19 -> 'r'; 20 -> 't'
        21 -> 'y'; 22 -> 'u'; 23 -> 'i'; 24 -> 'o'; 25 -> 'p'
        30 -> 'a'; 31 -> 's'; 32 -> 'd'; 33 -> 'f'; 34 -> 'g'
        35 -> 'h'; 36 -> 'j'; 37 -> 'k'; 38 -> 'l'
        44 -> 'z'; 45 -> 'x'; 46 -> 'c'; 47 -> 'v'; 48 -> 'b'
        49 -> 'n'; 50 -> 'm'
        else -> null
    }

    /// US-layout character for an evdev scancode.
    private fun charFor(key: Int, shift: Boolean): Char? {
        val letter = letterFor(key)
        if (letter != null) return if (shift) letter.uppercaseChar() else letter
        val pair = PUNCT[key] ?: return null
        return if (shift) pair.second else pair.first
    }
}
