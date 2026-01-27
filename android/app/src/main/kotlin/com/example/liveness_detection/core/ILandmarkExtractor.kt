package com.example.liveness_detection.core

/**
 * Represents 468 face landmarks from MediaPipe FaceLandmarker.
 */
data class FaceLandmarks(
    val landmarks: List<Landmark>,
    val timestamp: Long,
    val blendshapes: Map<String, Float> = emptyMap()  // Blendshape values for expressions
) {
    data class Landmark(
        val x: Float,
        val y: Float,
        val z: Float
    )
    
    /**
     * Get specific landmark by index.
     * MediaPipe uses 468 landmarks with predefined indices.
     */
    fun getLandmark(index: Int): Landmark? = landmarks.getOrNull(index)
    
    /**
     * Get eye blink values from blendshapes.
     * Returns (leftBlink, rightBlink) where 0 = open, 1 = closed
     */
    fun getEyeBlinkValues(): Pair<Float, Float> {
        val leftBlink = blendshapes["eyeBlinkLeft"] ?: 0f
        val rightBlink = blendshapes["eyeBlinkRight"] ?: 0f
        return Pair(leftBlink, rightBlink)
    }
    
    // Key landmark indices
    companion object {
        // Left eye landmarks
        const val LEFT_EYE_TOP = 159
        const val LEFT_EYE_BOTTOM = 145
        const val LEFT_EYE_INNER = 133
        const val LEFT_EYE_OUTER = 33
        
        // Right eye landmarks  
        const val RIGHT_EYE_TOP = 386
        const val RIGHT_EYE_BOTTOM = 374
        const val RIGHT_EYE_INNER = 362
        const val RIGHT_EYE_OUTER = 263
        
        // Iris landmarks (for inter-ocular distance)
        const val LEFT_IRIS_CENTER = 468
        const val RIGHT_IRIS_CENTER = 473
        
        // Nose tip
        const val NOSE_TIP = 1
    }
}

/**
 * Head pose angles extracted from landmarks.
 */
data class HeadPose(
    val pitch: Float,  // Up/Down (X rotation)
    val yaw: Float,    // Left/Right (Y rotation)
    val roll: Float    // Tilt (Z rotation)
)

/**
 * Interface for landmark extraction (MediaPipe implementation).
 * Used for deep liveness analysis.
 */
interface ILandmarkExtractor {
    
    /**
     * Initialize the MediaPipe FaceLandmarker.
     * This should pre-load the model graph.
     */
    fun initialize()
    
    /**
     * Warm up the engine by processing a dummy frame.
     * This eliminates cold-start lag when camera opens.
     */
    suspend fun warmUp()
    
    /**
     * Check if engine is warmed up and ready.
     */
    fun isReady(): Boolean
    
    /**
     * Extract face landmarks from image.
     * @param imageProxy CameraX ImageProxy
     * @return FaceLandmarks or null if no face detected
     */
    suspend fun extractLandmarks(imageProxy: Any): FaceLandmarks?
    
    /**
     * Calculate Eye Aspect Ratio (EAR) for blink detection.
     * EAR = (|p2-p6| + |p3-p5|) / (2 * |p1-p4|)
     * 
     * @return Pair of (leftEAR, rightEAR)
     */
    fun calculateEyeAspectRatio(landmarks: FaceLandmarks): Pair<Float, Float>
    
    /**
     * Calculate head pose from landmarks.
     */
    fun calculateHeadPose(landmarks: FaceLandmarks): HeadPose
    
    /**
     * Calculate inter-ocular distance (distance between iris centers).
     * Used for anti-spoof geometric consistency check.
     */
    fun calculateInterOcularDistance(landmarks: FaceLandmarks): Float
    
    /**
     * Release extractor resources.
     */
    fun close()
}
