package com.diajarkoding.livenessdetection.logic

import android.graphics.RectF
import android.util.Log
import com.diajarkoding.livenessdetection.core.FaceLandmarks
import com.diajarkoding.livenessdetection.core.ILandmarkExtractor
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
    
    // Texture analysis: track landmark symmetry consistency
    private val symmetryScores = mutableListOf<Float>()
    
    // Temporal consistency: track how landmarks change between frames
    private var previousLandmarks: FaceLandmarks? = null
    private val temporalConsistencyScores = mutableListOf<Float>()
    
    data class Measurement(
        val boundingBoxArea: Float,
        val interOcularDistance: Float,
        val timestamp: Long,
        val landmarkSymmetry: Float = 0f
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
            // Calculate facial symmetry score
            val symmetry = calculateFacialSymmetry(landmarks)
            symmetryScores.add(symmetry)
            if (symmetryScores.size > 30) symmetryScores.removeAt(0)
            
            // Calculate temporal consistency
            previousLandmarks?.let { prev ->
                val consistency = calculateTemporalConsistency(prev, landmarks)
                temporalConsistencyScores.add(consistency)
                if (temporalConsistencyScores.size > 30) temporalConsistencyScores.removeAt(0)
            }
            previousLandmarks = landmarks
            
            measurements.add(Measurement(
                boundingBoxArea = boxArea,
                interOcularDistance = iod,
                timestamp = System.currentTimeMillis(),
                landmarkSymmetry = symmetry
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
        
        // --- Texture Analysis: Facial Symmetry ---
        val avgSymmetry = if (symmetryScores.isNotEmpty()) symmetryScores.average().toFloat() else 1f
        val symmetryVariance = if (symmetryScores.size >= 5) {
            val mean = symmetryScores.average()
            symmetryScores.map { abs(it - mean) }.average().toFloat()
        } else 0f
        
        // Real faces have slight asymmetry variations; flat images tend to have
        // unnaturally perfect or highly inconsistent symmetry
        val symmetryAnomaly = avgSymmetry > 0.99f || symmetryVariance > 0.05f
        
        Log.d(TAG, "Texture analysis - Avg symmetry: $avgSymmetry, Variance: $symmetryVariance, Anomaly: $symmetryAnomaly")
        
        // --- Temporal Consistency Analysis ---
        val temporalAnomaly = if (temporalConsistencyScores.size >= 5) {
            val avgConsistency = temporalConsistencyScores.average().toFloat()
            // Real faces have natural micro-movements (consistency ~0.85-0.98)
            // Screen recordings tend to have very high consistency (>0.99) or very low (<0.7)
            avgConsistency > 0.995f || avgConsistency < 0.6f
        } else false
        
        val avgTemporal = if (temporalConsistencyScores.isNotEmpty()) {
            temporalConsistencyScores.average().toFloat()
        } else -1f
        Log.d(TAG, "Temporal analysis - Avg consistency: $avgTemporal, Anomaly: $temporalAnomaly")
        
        // --- Combined Scoring ---
        var spoofScore = 0f
        if (variance > MAX_RATIO_VARIANCE * 2) spoofScore += 0.5f
        else if (variance > MAX_RATIO_VARIANCE) spoofScore += 0.25f
        if (symmetryAnomaly) spoofScore += 0.25f
        if (temporalAnomaly) spoofScore += 0.25f
        
        Log.d(TAG, "Combined spoof score: $spoofScore")
        
        return when {
            spoofScore >= 0.75f -> {
                Log.w(TAG, "SPOOF DETECTED - Score: $spoofScore")
                AntiSpoofResult.Spoof("Spoofing detected: geometric=$variance, symmetry=$symmetryAnomaly, temporal=$temporalAnomaly")
            }
            spoofScore >= 0.25f -> {
                Log.w(TAG, "Suspicious behavior - Score: $spoofScore")
                AntiSpoofResult.Suspicious(
                    "Unusual pattern detected",
                    spoofScore
                )
            }
            else -> {
                Log.d(TAG, "All checks passed (geometric + texture + temporal)")
                AntiSpoofResult.Pass
            }
        }
    }
    
    /**
     * Calculate facial symmetry from landmarks.
     * Compares left-right landmark positions relative to face center.
     * Real faces have natural slight asymmetry (~0.92-0.98).
     * Perfect symmetry (>0.99) suggests a digital image.
     */
    private fun calculateFacialSymmetry(landmarks: FaceLandmarks): Float {
        val pts = landmarks.landmarks
        if (pts.size < 468) return 0.95f // Default for incomplete data
        
        // MediaPipe face mesh has known symmetry pairs
        // Compare key pairs: eyes, eyebrows, mouth corners, jaw
        val pairs = listOf(
            33 to 263,   // Left eye - Right eye
            133 to 362,  // Left eye inner - Right eye inner
            61 to 291,   // Left mouth corner - Right mouth corner
            234 to 454,  // Left cheek - Right cheek
            127 to 356   // Left eyebrow - Right eyebrow
        )
        
        var totalDiff = 0f
        var validPairs = 0
        
        for ((left, right) in pairs) {
            if (left < pts.size && right < pts.size) {
                val leftPt = pts[left]
                val rightPt = pts[right]
                // Compare normalized distances from center (nose tip = landmark 1)
                val nose = if (pts.size > 1) pts[1] else return 0.95f
                
                val leftDist = kotlin.math.sqrt(
                    (leftPt.x - nose.x) * (leftPt.x - nose.x) +
                    (leftPt.y - nose.y) * (leftPt.y - nose.y)
                )
                val rightDist = kotlin.math.sqrt(
                    (rightPt.x - nose.x) * (rightPt.x - nose.x) +
                    (rightPt.y - nose.y) * (rightPt.y - nose.y)
                )
                
                val maxDist = maxOf(leftDist, rightDist)
                if (maxDist > 0.001f) {
                    totalDiff += abs(leftDist - rightDist) / maxDist
                    validPairs++
                }
            }
        }
        
        return if (validPairs > 0) {
            1f - (totalDiff / validPairs)
        } else 0.95f
    }
    
    /**
     * Calculate temporal consistency between consecutive frames.
     * Measures how much landmarks moved between frames.
     * Real faces have natural micro-movements.
     * Screen recordings tend to be unnaturally still or have digital jitter.
     */
    private fun calculateTemporalConsistency(
        prev: FaceLandmarks,
        current: FaceLandmarks
    ): Float {
        val prevPts = prev.landmarks
        val currPts = current.landmarks
        
        if (prevPts.isEmpty() || currPts.isEmpty() || prevPts.size != currPts.size) {
            return 0.9f
        }
        
        var totalMovement = 0.0
        val sampleSize = minOf(50, prevPts.size) // Sample subset for performance
        val step = prevPts.size / sampleSize
        
        for (i in 0 until prevPts.size step step) {
            val dx = (currPts[i].x - prevPts[i].x).toDouble()
            val dy = (currPts[i].y - prevPts[i].y).toDouble()
            totalMovement += kotlin.math.sqrt(dx * dx + dy * dy)
        }
        
        val avgMovement = (totalMovement / (prevPts.size / step)).toFloat()
        
        // Normalize: typical micro-movement is ~0.001-0.01 in normalized coords
        // Consistency score: higher = less movement
        return (1f - avgMovement * 50f).coerceIn(0f, 1f)
    }
    
    /**
     * Quick check for obvious 2D indicators.
     * Returns true if definitely a spoof, false if needs more analysis.
     * Checks: flat z-profile, unnaturally perfect symmetry.
     */
    fun quickSpoofCheck(landmarks: FaceLandmarks): Boolean {
        val pts = landmarks.landmarks
        
        // Check 1: Flat z-profile (definite 2D indicator)
        if (pts.isNotEmpty()) {
            val zValues = pts.map { it.z }
            val zRange = (zValues.maxOrNull() ?: 0f) - (zValues.minOrNull() ?: 0f)
            
            if (zRange < 0.01f) {
                Log.w(TAG, "Quick spoof check: Flat z-profile detected (range=$zRange)")
                return true
            }
            
            // Check 2: Unnaturally perfect z-depth
            // Real faces have clear z-depth variation (nose protrudes, eyes are deeper)
            val zMean = zValues.average().toFloat()
            val zVariance = zValues.map { abs(it - zMean) }.average().toFloat()
            if (zVariance < 0.001f) {
                Log.w(TAG, "Quick spoof check: Suspiciously uniform z-depth (variance=$zVariance)")
                return true
            }
        }
        
        // Check 3: Perfect facial symmetry (digital image indicator)
        val symmetry = calculateFacialSymmetry(landmarks)
        if (symmetry > 0.998f) {
            Log.w(TAG, "Quick spoof check: Unnaturally perfect symmetry ($symmetry)")
            return true
        }
        
        return false
    }
    
    /**
     * Reset all measurements.
     */
    fun reset() {
        measurements.clear()
        symmetryScores.clear()
        temporalConsistencyScores.clear()
        previousLandmarks = null
        Log.d(TAG, "AntiSpoofGuard reset")
    }
    
    /**
     * Get current sample count.
     */
    fun getSampleCount(): Int = measurements.size
}
