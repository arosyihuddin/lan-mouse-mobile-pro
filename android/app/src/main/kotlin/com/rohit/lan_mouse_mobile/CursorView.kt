package com.rohit.lan_mouse_mobile

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.view.View

/// The floating pointer drawn over other apps while a desktop
/// controls this device in client mode. A classic arrow, drawn in a
/// 24-unit coordinate space; its tip sits at (5, 2) in that space.
class CursorView(context: Context) : View(context) {

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
    }
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.BLACK
        style = Paint.Style.STROKE
        strokeWidth = 1.6f
        strokeJoin = Paint.Join.ROUND
    }
    private val arrow = Path().apply {
        moveTo(5f, 2f)
        lineTo(5f, 19f)
        lineTo(9.5f, 15.5f)
        lineTo(12f, 21.5f)
        lineTo(14.8f, 20.2f)
        lineTo(12.3f, 14.3f)
        lineTo(17.5f, 14.3f)
        close()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val scale = width / 24f
        canvas.save()
        canvas.scale(scale, scale)
        // Shadow pass for contrast on light backgrounds.
        canvas.save()
        canvas.translate(0.7f, 0.9f)
        val shadowPaint = Paint(fillPaint).apply {
            color = Color.argb(90, 0, 0, 0)
        }
        canvas.drawPath(arrow, shadowPaint)
        canvas.restore()
        canvas.drawPath(arrow, fillPaint)
        canvas.drawPath(arrow, strokePaint)
        canvas.restore()
    }

    companion object {
        /// Hotspot (arrow tip) position as a fraction of the view size.
        const val HOTSPOT_X_FRACTION = 5f / 24f
        const val HOTSPOT_Y_FRACTION = 2f / 24f
    }
}
