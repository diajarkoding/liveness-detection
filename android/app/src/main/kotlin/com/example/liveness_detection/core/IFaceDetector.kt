package com.example.liveness_detection.core

import android.graphics.RectF

/**
 * Represents a detected face from ML Kit.
 */
data class DetectedFace(
    val boundingBox: RectF,
    val headEulerAngleX: Float,  // Pitch
    val headEulerAngleY: Float,  // Yaw
    val headEulerAngleZ: Float,  // Roll
    val leftEyeOpenProbability: Float?,
    val rightEyeOpenProbability: Float?,
    val smilingProbability: Float?,
    val trackingId: Int?
)

/**
 * Result of face gating validation.
 */
sealed class GatingResult {
    data object Pass : GatingResult()
    data class Fail(val reason: GatingFailReason) : GatingResult()
}

/**
 * Reasons why gating might fail.
 */
enum class GatingFailReason {
    NO_FACE_DETECTED,
    MULTIPLE_FACES,
    FACE_TOO_SMALL,
    FACE_NOT_CENTERED,
    FACE_TILTED,
    EYES_NOT_VISIBLE,      // Possible sunglasses
    MOUTH_NOT_VISIBLE      // Possible mask
}

/**
 * Interface for face detection (ML Kit implementation).
 * Used as the "gatekeeper" layer before deep analysis.
 */
interface IFaceDetector {
    
    /**
     * Initialize the face detector with options.
     */
    fun initialize()
    
    /**
     * Detect faces in the given image.
     * @param imageProxy CameraX ImageProxy
     * @return List of detected faces
     */
    suspend fun detectFaces(imageProxy: Any): List<DetectedFace>
    
    /**
     * Validate if the detected face passes gating rules:
     * - Exactly 1 face
     * - Face size >= 40% of frame width
     * - Face is centered
     * - Roll angle <= 20°
     * - Eyes and mouth are visible (no mask/sunglasses)
     */
    fun validateGating(
        face: DetectedFace,
        frameWidth: Int,
        frameHeight: Int
    ): GatingResult
    
    /**
     * Release detector resources.
     */
    fun close()
}
