package com.example.liveness_detection.core

/**
 * Interface for screen brightness management.
 * Used for low-light environment handling.
 */
interface IScreenManager {
    
    /**
     * Get current screen brightness.
     * @return Brightness value 0.0 to 1.0
     */
    fun getCurrentBrightness(): Float
    
    /**
     * Set screen brightness.
     * @param brightness Value from 0.0 to 1.0
     */
    fun setBrightness(brightness: Float)
    
    /**
     * Boost brightness to maximum (1.0).
     * Saves current brightness for later restoration.
     */
    fun boostBrightness()
    
    /**
     * Restore brightness to value before boost.
     */
    fun restoreBrightness()
    
    /**
     * Check if brightness is currently boosted.
     */
    fun isBoosted(): Boolean
}
