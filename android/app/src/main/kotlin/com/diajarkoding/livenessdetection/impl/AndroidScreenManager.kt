package com.diajarkoding.livenessdetection.impl

import android.app.Activity
import android.util.Log
import android.view.WindowManager
import com.diajarkoding.livenessdetection.core.IScreenManager
import java.lang.ref.WeakReference

/**
 * Android implementation of IScreenManager.
 * Controls screen brightness for low-light environments.
 */
class AndroidScreenManager(
    activity: Activity
) : IScreenManager {
    
    companion object {
        private const val TAG = "AndroidScreenManager"
        private const val MAX_BRIGHTNESS = 1.0f
    }
    
    private val activityRef = WeakReference(activity)
    private var originalBrightness: Float = -1f
    private var isBrightnessBoosted = false
    
    override fun getCurrentBrightness(): Float {
        val activity = activityRef.get() ?: return -1f
        
        val layoutParams = activity.window.attributes
        return if (layoutParams.screenBrightness < 0) {
            // System brightness - get from settings
            try {
                android.provider.Settings.System.getInt(
                    activity.contentResolver,
                    android.provider.Settings.System.SCREEN_BRIGHTNESS
                ) / 255f
            } catch (e: Exception) {
                0.5f // Default fallback
            }
        } else {
            layoutParams.screenBrightness
        }
    }
    
    override fun setBrightness(brightness: Float) {
        val activity = activityRef.get() ?: return
        
        val clampedBrightness = brightness.coerceIn(0f, 1f)
        
        activity.runOnUiThread {
            try {
                val layoutParams = activity.window.attributes
                layoutParams.screenBrightness = clampedBrightness
                activity.window.attributes = layoutParams
                Log.d(TAG, "Brightness set to $clampedBrightness")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to set brightness", e)
            }
        }
    }
    
    override fun boostBrightness() {
        if (isBrightnessBoosted) return
        
        // Save original brightness
        originalBrightness = getCurrentBrightness()
        
        // Set to maximum
        setBrightness(MAX_BRIGHTNESS)
        isBrightnessBoosted = true
        
        Log.d(TAG, "Brightness boosted from $originalBrightness to $MAX_BRIGHTNESS")
    }
    
    override fun restoreBrightness() {
        if (!isBrightnessBoosted) return
        
        if (originalBrightness >= 0) {
            setBrightness(originalBrightness)
        } else {
            // Reset to system default
            val activity = activityRef.get() ?: return
            activity.runOnUiThread {
                val layoutParams = activity.window.attributes
                layoutParams.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                activity.window.attributes = layoutParams
            }
        }
        
        isBrightnessBoosted = false
        Log.d(TAG, "Brightness restored to $originalBrightness")
    }
    
    override fun isBoosted(): Boolean = isBrightnessBoosted
}
