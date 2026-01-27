package com.example.liveness_detection.logic

import android.graphics.RectF
import android.util.Log
import com.example.liveness_detection.core.FaceLandmarks
import com.example.liveness_detection.core.ILandmarkExtractor
import kotlin.math.abs

/**
 * Result of anti-spoof check.
 */
sealed class AntiSpoofResult {
    data object Pass : AntiSpoofResult()
    data class Suspicious(val reason: String, val confidence: Float) : AntiSpoofResult()
    data class Spoof(val reason: String) : AntiSpoofResult()
}

/**
 * Passive liveness guard using geometric consistency checks.
 * 
 * Key insight: In a real 3D face, when the face moves closer/farther,
 * the bounding box size and inter-ocular distance change proportionally.
 * In a 2D screen (spoof), this ratio often becomes inconsistent due to
 * lens distortion and flat surface behavior.
 */
class AntiSpoofGuard(
    private val landmarkExtractor: ILandmarkExtractor
) {
    companion object {
        private const val TAG = "AntiSpoofGuard"
        
        // Minimum samples needed for analysis
        private const val MIN_SAMPLES = 10
        
        // Maximum allowed variance in box-to-IOD ratio
        private const val MAX_RATIO_VARIANCE = 0.15f
        
        // Minimum movement required for analysis (bbox change)
        private const val MIN_MOVEMENT_THRESHOLD = 0.05f
        
        // Suspicion threshold before marking as spoof
        private const val SUSPICION_THRESHOLD = 0.7f
    }
    
    // History of measurements for geometric consistency check
    private val measurements = mutableListOf<Measurement>()
    
    data class Measurement(
        val boundingBoxArea: Float,
        val interOcularDistance: Float,
        val timestamp: Long
    )
    
    /**
     * Add a new frame measurement for analysis.
     */
    fun addMeasurement(
        boundingBox: RectF,
        landmarks: FaceLandmarks
    ) {
        val boxArea = boundingBox.width() * boundingBox.height()
        val iod = landmarkExtractor.calculateInterOcularDistance(landmarks)
        
        if (iod > 0) {
            measurements.add(Measurement(
                boundingBoxArea = boxArea,
                interOcularDistance = iod,
                timestamp = System.currentTimeMillis()
            ))
            
            // Keep only recent measurements (last 30)
            if (measurements.size > 30) {
                measurements.removeAt(0)
            }
        }
    }
    
    /**
     * Analyze collected measurements for spoofing indicators.
     * 
     * The key check: In a real face, ratio of (BoundingBox Area) to 
     * (Inter-Ocular Distance²) should remain relatively constant
     * as the face moves toward/away from camera.
     */
    fun analyze(): AntiSpoofResult {
        if (measurements.size < MIN_SAMPLES) {
            Log.d(TAG, "Not enough samples for analysis: ${measurements.size}/$MIN_SAMPLES")
            return AntiSpoofResult.Pass // Not enough data yet
        }
        
        // Check if there's enough movement in the data
        val minBox = measurements.minOfOrNull { it.boundingBoxArea } ?: 0f
        val maxBox = measurements.maxOfOrNull { it.boundingBoxArea } ?: 0f
        val movementRange = if (maxBox > 0) (maxBox - minBox) / maxBox else 0f
        
        if (movementRange < MIN_MOVEMENT_THRESHOLD) {
            Log.d(TAG, "Not enough movement for analysis: $movementRange")
            return AntiSpoofResult.Pass // Face didn't move enough to analyze
        }
        
        // Calculate consistency ratio for each measurement
        // Ratio = BoundingBoxArea / (InterOcularDistance²)
        // This should be relatively constant for a real 3D face
        val ratios = measurements.map { m ->
            m.boundingBoxArea / (m.interOcularDistance * m.interOcularDistance)
        }
        
        val meanRatio = ratios.average().toFloat()
        val variance = ratios.map { abs(it - meanRatio) / meanRatio }.average().toFloat()
        
        Log.d(TAG, "Geometric analysis - Mean ratio: $meanRatio, Variance: $variance")
        
        return when {
            variance > MAX_RATIO_VARIANCE * 2 -> {
                Log.w(TAG, "SPOOF DETECTED - High variance: $variance")
                AntiSpoofResult.Spoof("Unnatural geometric behavior detected")
            }
            variance > MAX_RATIO_VARIANCE -> {
                Log.w(TAG, "Suspicious behavior - Variance: $variance")
                AntiSpoofResult.Suspicious(
                    "Unusual movement pattern",
                    variance / (MAX_RATIO_VARIANCE * 2)
                )
            }
            else -> {
                Log.d(TAG, "Geometric check passed")
                AntiSpoofResult.Pass
            }
        }
    }
    
    /**
     * Quick check for obvious 2D indicators.
     * Returns true if definitely a spoof, false if needs more analysis.
     */
    fun quickSpoofCheck(landmarks: FaceLandmarks): Boolean {
        // Check for unnaturally flat z-coordinates
        // In a real face, there's significant z-depth variation
        val zValues = landmarks.landmarks.map { it.z }
        val zRange = (zValues.maxOrNull() ?: 0f) - (zValues.minOrNull() ?: 0f)
        
        // If z-range is near zero, likely a flat image
        if (zRange < 0.01f) {
            Log.w(TAG, "Quick spoof check: Flat z-profile detected")
            return true
        }
        
        return false
    }
    
    /**
     * Reset all measurements.
     */
    fun reset() {
        measurements.clear()
        Log.d(TAG, "AntiSpoofGuard reset")
    }
    
    /**
     * Get current sample count.
     */
    fun getSampleCount(): Int = measurements.size
}
