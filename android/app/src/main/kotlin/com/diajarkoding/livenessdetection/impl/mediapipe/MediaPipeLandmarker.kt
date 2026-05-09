package com.diajarkoding.livenessdetection.impl.mediapipe

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import androidx.camera.core.ImageProxy
import com.diajarkoding.livenessdetection.core.FaceLandmarks
import com.diajarkoding.livenessdetection.core.HeadPose
import com.diajarkoding.livenessdetection.core.ILandmarkExtractor
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.nio.ByteBuffer
import kotlin.math.atan2
import kotlin.math.sqrt

/**
 * MediaPipe implementation of ILandmarkExtractor.
 * Provides 468 face landmarks for detailed liveness analysis.
 */
class MediaPipeLandmarker(
    private val context: Context
) : ILandmarkExtractor {
    
    companion object {
        private const val TAG = "MediaPipeLandmarker"
        private const val MODEL_PATH = "./face_landmarker.task"
        
        // Landmark indices for EAR calculation
        // Left eye: p1=33, p2=160, p3=158, p4=133, p5=153, p6=144
        private val LEFT_EYE_INDICES = intArrayOf(33, 160, 158, 133, 153, 144)
        // Right eye: p1=362, p2=385, p3=387, p4=263, p5=373, p6=380
        private val RIGHT_EYE_INDICES = intArrayOf(362, 385, 387, 263, 373, 380)
        
        // Iris centers for inter-ocular distance
        private const val LEFT_IRIS = 468
        private const val RIGHT_IRIS = 473
        
        // Key points for head pose estimation
        private const val NOSE_TIP = 1
        private const val CHIN = 152
        private const val LEFT_EYE_OUTER = 33
        private const val RIGHT_EYE_OUTER = 263
        private const val LEFT_MOUTH = 61
        private const val RIGHT_MOUTH = 291
    }
    
    private var landmarker: FaceLandmarker? = null
    private var isWarmedUp = false
    
    override fun initialize() {
        try {
            val baseOptions = BaseOptions.builder()
                .setModelAssetPath(MODEL_PATH)
                .build()
            
            val options = FaceLandmarker.FaceLandmarkerOptions.builder()
                .setBaseOptions(baseOptions)
                .setRunningMode(RunningMode.IMAGE)
                .setNumFaces(1)
                .setMinFaceDetectionConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .setOutputFaceBlendshapes(true)  // Enable blendshapes for blink detection
                .setOutputFacialTransformationMatrixes(false)
                .build()
            
            landmarker = FaceLandmarker.createFromOptions(context, options)
            Log.d(TAG, "MediaPipe FaceLandmarker initialized")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize FaceLandmarker", e)
            throw e
        }
    }
    
    override suspend fun warmUp() = withContext(Dispatchers.Default) {
        if (isWarmedUp) return@withContext
        
        try {
            // Create a small black dummy frame
            val dummyBitmap = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
            val mpImage = BitmapImageBuilder(dummyBitmap).build()
            
            // Process dummy frame to load graph into memory
            landmarker?.detect(mpImage)
            
            dummyBitmap.recycle()
            isWarmedUp = true
            Log.d(TAG, "MediaPipe warm-up complete")
        } catch (e: Exception) {
            Log.e(TAG, "Warm-up failed", e)
        }
    }
    
    override fun isReady(): Boolean = landmarker != null && isWarmedUp
    
    @androidx.camera.core.ExperimentalGetImage
    override suspend fun extractLandmarks(imageProxy: Any): FaceLandmarks? = 
        withContext(Dispatchers.Default) {
            val proxy = imageProxy as? ImageProxy
                ?: throw IllegalArgumentException("Expected ImageProxy")
            
            try {
                val rotationDegrees = proxy.imageInfo.rotationDegrees
                Log.d(TAG, "ImageProxy rotation: $rotationDegrees degrees, size: ${proxy.width}x${proxy.height}")
                
                val bitmap = proxy.toBitmap()
                Log.d(TAG, "Bitmap after rotation: ${bitmap.width}x${bitmap.height}")
                
                val mpImage = BitmapImageBuilder(bitmap).build()
                
                val result = landmarker?.detect(mpImage)
                bitmap.recycle()
                
                result?.toLandmarks()
            } catch (e: Exception) {
                Log.e(TAG, "Landmark extraction failed", e)
                null
            } finally {
                proxy.close()
            }
        }
    
    // Track if image is rotated for EAR calculation
    private var isImageRotated = false
    
    override fun calculateEyeAspectRatio(landmarks: FaceLandmarks): Pair<Float, Float> {
        // First detect if image is rotated by checking eye positions
        val leftEye = landmarks.getLandmark(LEFT_EYE_OUTER)
        val rightEye = landmarks.getLandmark(RIGHT_EYE_OUTER)
        
        if (leftEye != null && rightEye != null) {
            val eyeDeltaX = rightEye.x - leftEye.x
            val eyeDeltaY = rightEye.y - leftEye.y
            val rollRad = atan2(eyeDeltaY.toDouble(), eyeDeltaX.toDouble())
            val roll = Math.toDegrees(rollRad).toFloat()
            isImageRotated = kotlin.math.abs(roll) > 45f
        }
        
        val leftEAR = calculateEAR(landmarks, LEFT_EYE_INDICES)
        val rightEAR = calculateEAR(landmarks, RIGHT_EYE_INDICES)
        Log.d(TAG, "EAR: left=$leftEAR, right=$rightEAR, avg=${(leftEAR + rightEAR) / 2f}, rotated=$isImageRotated")
        return Pair(leftEAR, rightEAR)
    }
    
    /**
     * Calculate Eye Aspect Ratio using formula:
     * EAR = (|p2-p6| + |p3-p5|) / (2 * |p1-p4|)
     * 
     * When image is rotated 90 degrees, the vertical/horizontal distances are swapped
     * so we need to account for that.
     */
    private fun calculateEAR(landmarks: FaceLandmarks, indices: IntArray): Float {
        val points: List<FaceLandmarks.Landmark> = indices.toList().mapNotNull { idx -> landmarks.getLandmark(idx) }
        if (points.size != 6) return 0f
        
        val p1: FaceLandmarks.Landmark = points[0]
        val p2: FaceLandmarks.Landmark = points[1]
        val p3: FaceLandmarks.Landmark = points[2]
        val p4: FaceLandmarks.Landmark = points[3]
        val p5: FaceLandmarks.Landmark = points[4]
        val p6: FaceLandmarks.Landmark = points[5]
        
        // For rotated images, use euclidean distance which works regardless of orientation
        val vertical1 = distance(p2, p6)
        val vertical2 = distance(p3, p5)
        val horizontal = distance(p1, p4)
        
        // EAR formula works with euclidean distances regardless of rotation
        return if (horizontal > 0) {
            (vertical1 + vertical2) / (2f * horizontal)
        } else {
            0f
        }
    }
    
    override fun calculateHeadPose(landmarks: FaceLandmarks): HeadPose {
        // Get key landmarks for head pose estimation
        val noseTip = landmarks.getLandmark(NOSE_TIP) ?: return HeadPose(0f, 0f, 0f)
        val leftEye = landmarks.getLandmark(LEFT_EYE_OUTER) ?: return HeadPose(0f, 0f, 0f)
        val rightEye = landmarks.getLandmark(RIGHT_EYE_OUTER) ?: return HeadPose(0f, 0f, 0f)
        val leftMouth = landmarks.getLandmark(LEFT_MOUTH) ?: return HeadPose(0f, 0f, 0f)
        val rightMouth = landmarks.getLandmark(RIGHT_MOUTH) ?: return HeadPose(0f, 0f, 0f)
        
        // Calculate roll first (angle of line connecting eyes)
        val eyeDeltaX = rightEye.x - leftEye.x
        val eyeDeltaY = rightEye.y - leftEye.y
        val rollRad = atan2(eyeDeltaY.toDouble(), eyeDeltaX.toDouble())
        val roll = Math.toDegrees(rollRad).toFloat()
        
        // If roll is close to 90 degrees, the image is rotated
        // We need to use Y deviation instead of X for yaw calculation
        val isImageRotated = kotlin.math.abs(roll) > 45f
        
        // Calculate eye center
        val eyeCenterX = (leftEye.x + rightEye.x) / 2f
        val eyeCenterY = (leftEye.y + rightEye.y) / 2f
        
        // Calculate mouth center  
        val mouthCenterY = (leftMouth.y + rightMouth.y) / 2f
        
        val yaw: Float
        val pitch: Float
        
        if (isImageRotated) {
            // Image is rotated ~90 degrees
            // Use Y axis for yaw calculation instead of X
            val noseDeviationY = noseTip.y - eyeCenterY
            
            // Positive Y deviation = nose is below eye center = looking RIGHT (in rotated frame)
            // For front camera, we need to check the actual roll direction
            yaw = if (roll > 0) {
                // Roll ~90: positive Y deviation means looking LEFT
                -noseDeviationY * 600f
            } else {
                // Roll ~-90: positive Y deviation means looking RIGHT  
                noseDeviationY * 600f
            }
            
            // Pitch uses X deviation when rotated
            val noseDeviationX = noseTip.x - eyeCenterX
            pitch = -noseDeviationX * 300f
            
            Log.d(TAG, "HeadPose (ROTATED): yaw=$yaw (noseDevY=${noseTip.y - eyeCenterY}), pitch=$pitch, roll=$roll")
        } else {
            // Normal orientation - use X axis for yaw
            val noseDeviationX = noseTip.x - eyeCenterX
            yaw = noseDeviationX * 600f
            
            // Pitch: Compare nose Y position relative to eye-mouth midpoint
            val faceCenterY = (eyeCenterY + mouthCenterY) / 2f
            val noseDeviationY = noseTip.y - faceCenterY
            pitch = noseDeviationY * 300f
            
            Log.d(TAG, "HeadPose (NORMAL): yaw=$yaw (noseDevX=$noseDeviationX), pitch=$pitch, roll=$roll")
        }
        
        return HeadPose(
            pitch = pitch.coerceIn(-45f, 45f),
            yaw = yaw.coerceIn(-45f, 45f),
            roll = roll.coerceIn(-45f, 45f)
        )
    }
    
    override fun calculateInterOcularDistance(landmarks: FaceLandmarks): Float {
        val leftIris = landmarks.getLandmark(LEFT_IRIS)
        val rightIris = landmarks.getLandmark(RIGHT_IRIS)
        
        return if (leftIris != null && rightIris != null) {
            distance(leftIris, rightIris)
        } else {
            // Fallback to outer eye corners if iris not available
            val leftEye = landmarks.getLandmark(LEFT_EYE_OUTER)
            val rightEye = landmarks.getLandmark(RIGHT_EYE_OUTER)
            
            if (leftEye != null && rightEye != null) {
                distance(leftEye, rightEye)
            } else {
                0f
            }
        }
    }
    
    override fun close() {
        landmarker?.close()
        landmarker = null
        isWarmedUp = false
        Log.d(TAG, "MediaPipe FaceLandmarker closed")
    }
    
    /**
     * Calculate Euclidean distance between two landmarks.
     */
    private fun distance(p1: FaceLandmarks.Landmark, p2: FaceLandmarks.Landmark): Float {
        val dx = p2.x - p1.x
        val dy = p2.y - p1.y
        return sqrt(dx * dx + dy * dy)
    }
    
    /**
     * Convert MediaPipe result to our FaceLandmarks model.
     * Note: Front camera image is NOT mirrored in raw data, but preview is mirrored.
     * We flip x-coordinates to match the mirrored preview that user sees.
     */
    private fun FaceLandmarkerResult.toLandmarks(): FaceLandmarks? {
        if (faceLandmarks().isEmpty()) return null
        
        val landmarks = faceLandmarks()[0].map { landmark ->
            FaceLandmarks.Landmark(
                x = 1.0f - landmark.x(),  // Flip x to match mirrored front camera preview
                y = landmark.y(),
                z = landmark.z()
            )
        }
        
        // Extract blendshapes if available
        val blendshapeMap = mutableMapOf<String, Float>()
        if (faceBlendshapes().isPresent && faceBlendshapes().get().isNotEmpty()) {
            val blendshapes = faceBlendshapes().get()[0]
            for (category in blendshapes) {
                blendshapeMap[category.categoryName()] = category.score()
            }
            Log.d(TAG, "Blendshapes: eyeBlinkL=${blendshapeMap["eyeBlinkLeft"]?.let { "%.2f".format(it) }}, eyeBlinkR=${blendshapeMap["eyeBlinkRight"]?.let { "%.2f".format(it) }}")
        }
        
        return FaceLandmarks(
            landmarks = landmarks,
            timestamp = System.currentTimeMillis(),
            blendshapes = blendshapeMap
        )
    }
    
    /**
     * Convert ImageProxy to Bitmap with proper rotation handling.
     */
    @androidx.camera.core.ExperimentalGetImage
    private fun ImageProxy.toBitmap(): Bitmap {
        val yBuffer = planes[0].buffer
        val uBuffer = planes[1].buffer
        val vBuffer = planes[2].buffer

        val ySize = yBuffer.remaining()
        val uSize = uBuffer.remaining()
        val vSize = vBuffer.remaining()

        val nv21 = ByteArray(ySize + uSize + vSize)
        yBuffer.get(nv21, 0, ySize)
        vBuffer.get(nv21, ySize, vSize)
        uBuffer.get(nv21, ySize + vSize, uSize)

        val yuvImage = android.graphics.YuvImage(
            nv21,
            android.graphics.ImageFormat.NV21,
            width,
            height,
            null
        )
        
        val out = java.io.ByteArrayOutputStream()
        yuvImage.compressToJpeg(android.graphics.Rect(0, 0, width, height), 100, out)
        val imageBytes = out.toByteArray()
        
        val originalBitmap = android.graphics.BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
        
        // Apply rotation based on imageProxy.imageInfo.rotationDegrees
        val rotationDegrees = imageInfo.rotationDegrees
        Log.d(TAG, "toBitmap: rotationDegrees=$rotationDegrees, original=${originalBitmap.width}x${originalBitmap.height}")
        
        return if (rotationDegrees != 0) {
            val matrix = android.graphics.Matrix()
            matrix.postRotate(rotationDegrees.toFloat())
            val rotatedBitmap = Bitmap.createBitmap(
                originalBitmap, 
                0, 0, 
                originalBitmap.width, originalBitmap.height, 
                matrix, 
                true
            )
            Log.d(TAG, "toBitmap: rotated=${rotatedBitmap.width}x${rotatedBitmap.height}")
            originalBitmap.recycle()
            rotatedBitmap
        } else {
            originalBitmap
        }
    }
}
