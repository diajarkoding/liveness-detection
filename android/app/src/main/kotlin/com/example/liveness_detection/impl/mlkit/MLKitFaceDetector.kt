package com.example.liveness_detection.impl.mlkit

import android.graphics.RectF
import android.util.Log
import androidx.camera.core.ImageProxy
import com.example.liveness_detection.core.*
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.abs

/**
 * ML Kit implementation of IFaceDetector.
 * Acts as the "gatekeeper" layer - fast and lightweight face detection.
 */
class MLKitFaceDetector : IFaceDetector {
    
    companion object {
        private const val TAG = "MLKitFaceDetector"
        
        // Gating thresholds
        private const val MIN_FACE_SIZE_RATIO = 0.35f  // Face must be >= 35% of frame width
        private const val MAX_ROLL_ANGLE = 20f         // Max head tilt in degrees
        private const val CENTER_TOLERANCE = 0.25f     // How far from center is acceptable
        private const val MIN_EYE_OPEN_PROB = 0.3f     // Min probability for eyes visible
        private const val MIN_SMILE_PROB = 0.0f        // Just needs to be detectable (not -1)
    }
    
    private var detector: FaceDetector? = null
    
    override fun initialize() {
        val options = FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_NONE) // We use MediaPipe for landmarks
            .setMinFaceSize(0.25f)
            .enableTracking()
            .build()
        
        detector = FaceDetection.getClient(options)
        Log.d(TAG, "ML Kit Face Detector initialized")
    }
    
    @androidx.camera.core.ExperimentalGetImage
    override suspend fun detectFaces(imageProxy: Any): List<DetectedFace> {
        val proxy = imageProxy as? ImageProxy 
            ?: throw IllegalArgumentException("Expected ImageProxy")
        
        val mediaImage = proxy.image ?: run {
            proxy.close()
            return emptyList()
        }
        
        val inputImage = InputImage.fromMediaImage(
            mediaImage,
            proxy.imageInfo.rotationDegrees
        )
        
        return suspendCancellableCoroutine { continuation ->
            detector?.process(inputImage)
                ?.addOnSuccessListener { faces ->
                    val detectedFaces = faces.map { it.toDetectedFace() }
                    proxy.close()
                    continuation.resume(detectedFaces)
                }
                ?.addOnFailureListener { e ->
                    Log.e(TAG, "Face detection failed", e)
                    proxy.close()
                    continuation.resume(emptyList())
                }
                ?: run {
                    proxy.close()
                    continuation.resumeWithException(
                        IllegalStateException("Detector not initialized")
                    )
                }
        }
    }
    
    override fun validateGating(
        face: DetectedFace,
        frameWidth: Int,
        frameHeight: Int
    ): GatingResult {
        // Check 1: Face size
        val faceWidthRatio = face.boundingBox.width() / frameWidth
        if (faceWidthRatio < MIN_FACE_SIZE_RATIO) {
            Log.d(TAG, "Gating failed: Face too small ($faceWidthRatio < $MIN_FACE_SIZE_RATIO)")
            return GatingResult.Fail(GatingFailReason.FACE_TOO_SMALL)
        }
        
        // Check 2: Face is centered
        val faceCenterX = face.boundingBox.centerX()
        val faceCenterY = face.boundingBox.centerY()
        val frameCenterX = frameWidth / 2f
        val frameCenterY = frameHeight / 2f
        
        val xDeviation = abs(faceCenterX - frameCenterX) / frameWidth
        val yDeviation = abs(faceCenterY - frameCenterY) / frameHeight
        
        if (xDeviation > CENTER_TOLERANCE || yDeviation > CENTER_TOLERANCE) {
            Log.d(TAG, "Gating failed: Face not centered (x=$xDeviation, y=$yDeviation)")
            return GatingResult.Fail(GatingFailReason.FACE_NOT_CENTERED)
        }
        
        // Check 3: Head not tilted (roll angle)
        if (abs(face.headEulerAngleZ) > MAX_ROLL_ANGLE) {
            Log.d(TAG, "Gating failed: Face tilted (roll=${face.headEulerAngleZ})")
            return GatingResult.Fail(GatingFailReason.FACE_TILTED)
        }
        
        // Check 4: Eyes visible (detect sunglasses)
        val leftEyeProb = face.leftEyeOpenProbability ?: -1f
        val rightEyeProb = face.rightEyeOpenProbability ?: -1f
        
        if (leftEyeProb < 0 || rightEyeProb < 0) {
            // Probability is null - eyes not detectable (likely sunglasses)
            Log.d(TAG, "Gating failed: Eyes not visible")
            return GatingResult.Fail(GatingFailReason.EYES_NOT_VISIBLE)
        }
        
        // Check 5: Mouth visible (detect mask)
        val smileProb = face.smilingProbability ?: -1f
        if (smileProb < 0) {
            // Probability is null - mouth not detectable (likely mask)
            Log.d(TAG, "Gating failed: Mouth not visible")
            return GatingResult.Fail(GatingFailReason.MOUTH_NOT_VISIBLE)
        }
        
        Log.d(TAG, "Gating passed")
        return GatingResult.Pass
    }
    
    override fun close() {
        detector?.close()
        detector = null
        Log.d(TAG, "ML Kit Face Detector closed")
    }
    
    /**
     * Convert ML Kit Face to our DetectedFace model.
     */
    private fun Face.toDetectedFace(): DetectedFace {
        return DetectedFace(
            boundingBox = RectF(boundingBox),
            headEulerAngleX = headEulerAngleX,
            headEulerAngleY = headEulerAngleY,
            headEulerAngleZ = headEulerAngleZ,
            leftEyeOpenProbability = leftEyeOpenProbability,
            rightEyeOpenProbability = rightEyeOpenProbability,
            smilingProbability = smilingProbability,
            trackingId = trackingId
        )
    }
}
