package com.aktifdesk.aktifdesk

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Build
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Injects remote taps / swipes / global actions on the owner's phone without root.
 * Enabled only when the user turns on AktifDesk in Accessibility settings.
 */
class RemoteAccessibilityService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Gestures are driven by MethodChannel; events are ignored.
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    private fun screenSize(): Pair<Int, Int> {
        return try {
            if (Build.VERSION.SDK_INT >= 30) {
                val metrics = display?.getRealMetricsCompat()
                if (metrics != null) return metrics
            }
            @Suppress("DEPRECATION")
            val dm = resources.displayMetrics
            Pair(dm.widthPixels, dm.heightPixels)
        } catch (_: Exception) {
            val dm = resources.displayMetrics
            Pair(dm.widthPixels, dm.heightPixels)
        }
    }

    @Suppress("DEPRECATION")
    private fun Display.getRealMetricsCompat(): Pair<Int, Int>? {
        return try {
            if (Build.VERSION.SDK_INT >= 31) {
                val b = this.mode?.physicalWidth ?: return null
                val h = this.mode?.physicalHeight ?: return null
                if (b > 0 && h > 0) Pair(b, h) else null
            } else {
                val m = android.util.DisplayMetrics()
                getRealMetrics(m)
                Pair(m.widthPixels, m.heightPixels)
            }
        } catch (_: Exception) {
            null
        }
    }

    /** [nx]/[ny] are normalized 0..1 (or absolute px if [absolute] is true). */
    fun tap(nx: Double, ny: Double, absolute: Boolean = false): Boolean {
        val (w, h) = screenSize()
        if (w <= 0 || h <= 0) return false
        val x = if (absolute) nx.toFloat() else (nx.coerceIn(0.0, 1.0) * w).toFloat()
        val y = if (absolute) ny.toFloat() else (ny.coerceIn(0.0, 1.0) * h).toFloat()
        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0, 50)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        return dispatchGesture(gesture, null, null)
    }

    fun swipe(
        nx1: Double,
        ny1: Double,
        nx2: Double,
        ny2: Double,
        durationMs: Long = 300,
        absolute: Boolean = false,
    ): Boolean {
        val (w, h) = screenSize()
        if (w <= 0 || h <= 0) return false
        val x1 = if (absolute) nx1.toFloat() else (nx1.coerceIn(0.0, 1.0) * w).toFloat()
        val y1 = if (absolute) ny1.toFloat() else (ny1.coerceIn(0.0, 1.0) * h).toFloat()
        val x2 = if (absolute) nx2.toFloat() else (nx2.coerceIn(0.0, 1.0) * w).toFloat()
        val y2 = if (absolute) ny2.toFloat() else (ny2.coerceIn(0.0, 1.0) * h).toFloat()
        val dur = durationMs.coerceIn(50, 5000)
        val path = Path().apply {
            moveTo(x1, y1)
            lineTo(x2, y2)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, dur)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        return dispatchGesture(gesture, null, null)
    }

    fun globalKey(action: String): Boolean {
        val code = when (action.lowercase()) {
            "back" -> GLOBAL_ACTION_BACK
            "home" -> GLOBAL_ACTION_HOME
            "recents", "recent", "overview" -> GLOBAL_ACTION_RECENTS
            "notifications" -> GLOBAL_ACTION_NOTIFICATIONS
            "quick_settings", "quicksettings" -> GLOBAL_ACTION_QUICK_SETTINGS
            "power", "power_dialog" -> GLOBAL_ACTION_POWER_DIALOG
            "lock" -> if (Build.VERSION.SDK_INT >= 28) GLOBAL_ACTION_LOCK_SCREEN else return false
            "split" -> if (Build.VERSION.SDK_INT >= 24) GLOBAL_ACTION_TOGGLE_SPLIT_SCREEN else return false
            else -> return false
        }
        return try {
            performGlobalAction(code)
        } catch (_: Exception) {
            false
        }
    }

    /** Best-effort: paste / set text on focused editable node. */
    fun typeText(text: String): Boolean {
        if (text.isEmpty()) return false
        return try {
            val root = rootInActiveWindow ?: return false
            val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: root
            val args = android.os.Bundle()
            args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        } catch (_: Exception) {
            false
        }
    }

    companion object {
        @Volatile
        var instance: RemoteAccessibilityService? = null

        fun isRunning(): Boolean = instance != null
    }
}
