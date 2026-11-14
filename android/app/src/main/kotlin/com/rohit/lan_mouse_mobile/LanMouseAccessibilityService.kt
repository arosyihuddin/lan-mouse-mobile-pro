package com.rohit.lan_mouse_mobile

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Choreographer
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.min

/// Client-mode input injection.
///
/// Owns the floating cursor (an accessibility overlay window) and
/// translates desktop input operations into touch gestures via
/// [dispatchGesture] — the only system-wide injection a normal
/// Android app can perform. Consequences, by design:
/// - a click is a short stroke at the cursor, a right-click a long
///   press, and scrolling a swipe;
/// - drags use continued strokes (API 26+) so apps see one long
///   press-move-release sequence; on older versions a drag degrades
///   to a swipe between the press and release points.
class LanMouseAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile
        var instance: LanMouseAccessibilityService? = null
            private set

        private const val BTN_LEFT = 0x110
        private const val BTN_RIGHT = 0x111

        private const val DRAG_SLOP_PX = 24f
        private const val TAP_MS = 60L
        private const val LONG_PRESS_MS = 550L
        private const val DRAG_SEGMENT_MS = 25L
        private const val HOLD_HEARTBEAT_MS = 200L
        private const val SCROLL_MIN_SWIPE_PX = 120f
        private const val SCROLL_MAX_SWIPE_PX = 480f
        private const val SCROLL_PX_PER_UNIT = 6.0
        private const val SCROLL_NOTCH_PX = 240.0
        private const val SCROLL_MIN_INTERVAL_MS = 24L
        private const val EXIT_ARM_MARGIN_PX = 24f
        private const val EXIT_PUSH_THRESHOLD = 10.0
    }

    private var windowManager: WindowManager? = null
    private var cursorView: CursorView? = null
    private var cursorParams: WindowManager.LayoutParams? = null
    private var cursorSizePx = 0
    private var cursorShown = false

    private var screenW = 0
    private var screenH = 0
    private var cursorX = 0f
    private var cursorY = 0f

    private var leftDown = false
    private var downX = 0f
    private var downY = 0f
    private var downAt = 0L
    private var dragStroke: GestureDescription.StrokeDescription? = null
    private var lastStrokeX = 0f
    private var lastStrokeY = 0f

    private val holdHandler = Handler(Looper.getMainLooper())

    // While the button is held without moving, re-issue a
    // zero-move continuation every HOLD_HEARTBEAT_MS so the
    // system keeps the touch down indefinitely - this is what
    // turns a stationary hold into a real long-press (e.g. a
    // launcher icon waiting to be picked up).
    private val holdHeartbeat = object : Runnable {
        override fun run() {
            val stroke = dragStroke
            if (!leftDown || stroke == null) return
            val path = Path().apply { moveTo(lastStrokeX, lastStrokeY) }
            val next = stroke.continueStroke(path, 0, DRAG_SEGMENT_MS, true)
            dispatchGesture(
                GestureDescription.Builder().addStroke(next).build(), null, null,
            )
            dragStroke = next
            holdHandler.postDelayed(this, HOLD_HEARTBEAT_MS)
        }
    }

    private var scrollAccumXPx = 0.0
    private var scrollAccumYPx = 0.0
    private var lastScrollAt = 0L

    // Enter/exit-edge tracking. The Enter event's position says
    // where the desktop sits relative to this device (0 left,
    // 1 right, 2 top, 3 bottom); the pointer enters and leaves
    // through that same edge. Leaving is driven from here: when the
    // cursor, after having moved into the screen, reaches that edge
    // again while pushing outward, the desktop is asked (through
    // Dart) to release its capture — mirroring upstream's barrier
    // detection on desktop backends.
    private var enterPosition = 1
    private var exitArmed = false
    private var leaveSent = false
    private var edgePushAccum = 0.0

    // Motion is accumulated and applied once per display frame
    // (vsync): desktop frames can arrive in bursts, and applying
    // each separately makes the cursor step instead of glide.
    private var pendingDx = 0.0
    private var pendingDy = 0.0
    private var frameCallbackPosted = false
    private val frameCallback = Choreographer.FrameCallback {
        applyPendingMotion()
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        val metrics = resources.displayMetrics
        screenW = metrics.widthPixels
        screenH = metrics.heightPixels
        cursorX = screenW / 2f
        cursorY = screenH / 2f
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
    }

    override fun onDestroy() {
        cursorView?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (_: Exception) {
            }
        }
        cursorView = null
        cursorParams = null
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    // ---------------- session ----------------

    fun onEnter(position: Int) {
        // A repeated Enter while the pointer is already here (the
        // desktop repeats Enter until our Ack lands) must not
        // re-snap the cursor or reset the exit tracking.
        if (cursorShown) return
        endDrag()
        scrollAccumXPx = 0.0
        scrollAccumYPx = 0.0
        enterPosition = position
        exitArmed = false
        leaveSent = false
        edgePushAccum = 0.0
        // Appear at the edge the pointer crossed through, keeping
        // the other coordinate (relative-motion equivalent of the
        // desktop's absolute entry point).
        when (position) {
            0 -> cursorX = 0f
            1 -> cursorX = (screenW - 1).toFloat()
            2 -> cursorY = 0f
            3 -> cursorY = (screenH - 1).toFloat()
        }
        showCursor()
    }

    fun onLeave() {
        cancelPendingMotion()
        endDrag()
        hideCursor()
    }

    fun onSessionEnded() {
        endDrag()
        hideCursor()
    }

    // ---------------- pointer ----------------

    fun moveBy(dx: Double, dy: Double) {
        pendingDx += dx
        pendingDy += dy
        if (!frameCallbackPosted) {
            frameCallbackPosted = true
            Choreographer.getInstance().postFrameCallback(frameCallback)
        }
    }

    private fun applyPendingMotion() {
        frameCallbackPosted = false
        val dx = pendingDx
        val dy = pendingDy
        pendingDx = 0.0
        pendingDy = 0.0
        if (dx == 0.0 && dy == 0.0) return
        // Exit detection uses the UNclamped target: pushing against
        // the exit edge from inside (after having moved into the
        // screen) asks the desktop to release its capture. Even a
        // slow push overshoots the edge, so no flick is needed.
        if (!leaveSent) {
            val rawX = cursorX + dx
            val rawY = cursorY + dy
            val overshoot = when (enterPosition) {
                0 -> rawX < 0
                1 -> rawX > screenW - 1
                2 -> rawY < 0
                else -> rawY > screenH - 1
            }
            val dist = when (enterPosition) {
                0 -> cursorX
                1 -> (screenW - 1) - cursorX
                2 -> cursorY
                else -> (screenH - 1) - cursorY
            }
            if (dist > EXIT_ARM_MARGIN_PX) exitArmed = true
            // Sustained-push trigger: while pressed against the
            // exit edge, accumulate the outward motion — a slow,
            // steady push whose individual frames are tiny still
            // crosses once enough has accumulated.
            if (dist <= 1f) {
                val outwardDelta = when (enterPosition) {
                    0 -> if (dx < 0) -dx else 0.0
                    1 -> if (dx > 0) dx else 0.0
                    2 -> if (dy < 0) -dy else 0.0
                    else -> if (dy > 0) dy else 0.0
                }
                edgePushAccum += outwardDelta
            } else if (dist > 6f) {
                edgePushAccum = 0.0
            }
            if (exitArmed &&
                (overshoot || edgePushAccum >= EXIT_PUSH_THRESHOLD)
            ) {
                leaveSent = true
                ClientInputDispatcher.requestLeave()
            }
        }
        cursorX = (cursorX + dx.toFloat()).coerceIn(0f, (screenW - 1).toFloat())
        cursorY = (cursorY + dy.toFloat()).coerceIn(0f, (screenH - 1).toFloat())
        if (cursorShown) positionCursorView()
        if (leftDown) dragMove()
    }

    private fun cancelPendingMotion() {
        if (frameCallbackPosted) {
            Choreographer.getInstance().removeFrameCallback(frameCallback)
            frameCallbackPosted = false
        }
        pendingDx = 0.0
        pendingDy = 0.0
    }

    fun onButton(button: Int, down: Boolean) {
        when (button) {
            BTN_LEFT -> if (down) leftPressed() else leftReleased()
            BTN_RIGHT -> if (down) strokeAt(cursorX, cursorY, LONG_PRESS_MS)
            // Middle / back / forward have no touch equivalent.
        }
    }

    fun onScroll(axis: Int, value: Double) {
        // libei axis numbering: 0 = horizontal, 1 = vertical.
        if (axis == 1) {
            scrollAccumYPx += value * SCROLL_PX_PER_UNIT
        } else {
            scrollAccumXPx += value * SCROLL_PX_PER_UNIT
        }
        emitScroll()
    }

    fun onScrollDiscrete(axis: Int, value: Int) {
        // 120 units = one mouse-wheel notch.
        val px = value / 120.0 * SCROLL_NOTCH_PX
        if (axis == 1) {
            scrollAccumYPx += px
        } else {
            scrollAccumXPx += px
        }
        emitScroll()
    }

    // ---------------- cursor overlay ----------------

    private fun showCursor() {
        val wm = windowManager ?: return
        if (cursorView == null) {
            cursorSizePx = (30 * resources.displayMetrics.density).toInt()
            val params = WindowManager.LayoutParams(
                cursorSizePx,
                cursorSizePx,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT,
            ).apply { gravity = Gravity.TOP or Gravity.LEFT }
            val view = CursorView(this)
            try {
                wm.addView(view, params)
            } catch (_: Exception) {
                return
            }
            cursorView = view
            cursorParams = params
        }
        cursorShown = true
        cursorView?.visibility = View.VISIBLE
        positionCursorView()
    }

    private fun hideCursor() {
        cursorShown = false
        cursorView?.visibility = View.GONE
    }

    private fun positionCursorView() {
        val params = cursorParams ?: return
        params.x = (cursorX - cursorSizePx * CursorView.HOTSPOT_X_FRACTION).toInt()
        params.y = (cursorY - cursorSizePx * CursorView.HOTSPOT_Y_FRACTION).toInt()
        try {
            windowManager?.updateViewLayout(cursorView, params)
        } catch (_: Exception) {
        }
    }

    // ---------------- gestures ----------------

    private fun leftPressed() {
        if (leftDown) return
        leftDown = true
        downX = cursorX
        downY = cursorY
        downAt = SystemClock.uptimeMillis()
        dragStroke = null
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        // Put the touch down NOW as a continued stroke and keep it
        // down until release. The old model dispatched nothing on
        // press and reconstructed tap / long-press / swipe at
        // release time, so a stationary hold never existed on
        // screen while it was happening - a launcher had nothing
        // to pick up, and a hold-then-move looked like a swipe.
        val path = Path().apply { moveTo(cursorX, cursorY) }
        val stroke = GestureDescription.StrokeDescription(
            path, 0, DRAG_SEGMENT_MS, true,
        )
        dispatchGesture(
            GestureDescription.Builder().addStroke(stroke).build(), null, null,
        )
        dragStroke = stroke
        lastStrokeX = cursorX
        lastStrokeY = cursorY
        holdHandler.removeCallbacks(holdHeartbeat)
        holdHandler.postDelayed(holdHeartbeat, HOLD_HEARTBEAT_MS)
    }

    private fun dragMove() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val current = dragStroke
        if (current == null) {
            if (hypot(cursorX - downX, cursorY - downY) < DRAG_SLOP_PX) return
            val path = Path().apply {
                moveTo(downX, downY)
                lineTo(cursorX, cursorY)
            }
            val stroke = GestureDescription.StrokeDescription(path, 0, DRAG_SEGMENT_MS, true)
            dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
            dragStroke = stroke
        } else {
            if (abs(cursorX - lastStrokeX) < 4f && abs(cursorY - lastStrokeY) < 4f) return
            val path = Path().apply {
                moveTo(lastStrokeX, lastStrokeY)
                lineTo(cursorX, cursorY)
            }
            val next = current.continueStroke(path, 0, DRAG_SEGMENT_MS, true)
            dispatchGesture(GestureDescription.Builder().addStroke(next).build(), null, null)
            dragStroke = next
        }
        lastStrokeX = cursorX
        lastStrokeY = cursorY
    }

    private fun leftReleased() {
        if (!leftDown) return
        leftDown = false
        holdHandler.removeCallbacks(holdHeartbeat)
        val stroke = dragStroke
        dragStroke = null
        if (stroke != null) {
            finishDragStroke(stroke)
            return
        }
        val heldMs = SystemClock.uptimeMillis() - downAt
        val dist = hypot(cursorX - downX, cursorY - downY)
        when {
            dist >= DRAG_SLOP_PX ->
                swipe(downX, downY, cursorX, cursorY, 200)
            heldMs >= LONG_PRESS_MS ->
                strokeAt(cursorX, cursorY, LONG_PRESS_MS)
            else -> strokeAt(cursorX, cursorY, TAP_MS)
        }
    }

    private fun endDrag() {
        holdHandler.removeCallbacks(holdHeartbeat)
        val stroke = dragStroke
        dragStroke = null
        leftDown = false
        if (stroke != null) finishDragStroke(stroke)
    }

    private fun finishDragStroke(stroke: GestureDescription.StrokeDescription) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val path = Path().apply {
            moveTo(lastStrokeX, lastStrokeY)
            lineTo(cursorX, cursorY)
        }
        val fin = stroke.continueStroke(path, 0, 30, false)
        dispatchGesture(GestureDescription.Builder().addStroke(fin).build(), null, null)
    }

    private fun strokeAt(x: Float, y: Float, durationMs: Long) {
        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0, durationMs)
        dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    private fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long) {
        val path = Path().apply {
            moveTo(x1, y1)
            lineTo(x2, y2)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, durationMs)
        dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    private fun emitScroll() {
        val now = SystemClock.uptimeMillis()
        if (now - lastScrollAt < SCROLL_MIN_INTERVAL_MS) return
        if (abs(scrollAccumYPx) >= SCROLL_MIN_SWIPE_PX) {
            val amount = scrollAccumYPx.toFloat().coerceIn(-SCROLL_MAX_SWIPE_PX, SCROLL_MAX_SWIPE_PX)
            scrollAccumYPx -= amount
            lastScrollAt = now
            // Positive wheel value = scroll down = content moves up =
            // the finger swipes up, centered on the cursor so it also
            // works near the screen edges.
            val half = amount / 2f
            swipe(
                cursorX,
                (cursorY + half).coerceIn(0f, (screenH - 1).toFloat()),
                cursorX,
                (cursorY - half).coerceIn(0f, (screenH - 1).toFloat()),
                140,
            )
        } else if (abs(scrollAccumXPx) >= SCROLL_MIN_SWIPE_PX) {
            val amount = scrollAccumXPx.toFloat().coerceIn(-SCROLL_MAX_SWIPE_PX, SCROLL_MAX_SWIPE_PX)
            scrollAccumXPx -= amount
            lastScrollAt = now
            val half = amount / 2f
            swipe(
                (cursorX + half).coerceIn(0f, (screenW - 1).toFloat()),
                cursorY,
                (cursorX - half).coerceIn(0f, (screenW - 1).toFloat()),
                cursorY,
                140,
            )
        }
    }
}
