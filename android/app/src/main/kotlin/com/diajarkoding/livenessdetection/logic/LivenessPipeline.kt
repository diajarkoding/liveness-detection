package com.diajarkoding.livenessdetection.logic

import android.graphics.RectF
import android.util.Log
import androidx.camera.core.ImageProxy
import com.diajarkoding.livenessdetection.core.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Overall state of the liveness detection pipeline.
 */
sealed class LivenessState {
    data object Idle : LivenessState()
    data object Initializing : LivenessState()
    
    data class Gating(
        val message: String = "Position your face in the frame"
    ) : LivenessState()
    
    data class GatingFailed(
        val reason: GatingFailReason,
        val message: String
    ) : LivenessState()
    
    data class Challenge(
        val type: ChallengeType,
        val progress: Float = 0f,
        val instruction: String
    ) : LivenessState()
    
    data class Processing(
        val message: String = "Analyzing..."
    ) : LivenessState()
    
    data class Success(
        val completedChallenges: Set<ChallengeType>
    ) : LivenessState()
    
    data class Failed(
        val reason: String,
        val canRetry: Boolean = true
    ) : LivenessState()
}

/**
 * Main coordinator for the liveness detection pipeline.
 * Orchestrates ML Kit (gating) -> MediaPipe (analysis) -> Challenge Engine.
 */
class LivenessPipeline(
    private val faceDetector: IFaceDetector,
    private val landmarkExtractor: ILandmarkExtractor,
    private val screenManager: IScreenManager,
    private val securityGuardResult: SecurityCheckResult? = null
) {
    companion object {
        private const val TAG = "LivenessPipeline"
        
        // Frame throttling to save battery (target ~15 fps processing)
        private const val MIN_FRAME_INTERVAL_MS = 66L
    }
    
    private val _state = MutableStateFlow<LivenessState>(LivenessState.Idle)
    val state: StateFlow<LivenessState> = _state.asStateFlow()
    
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    
    private lateinit var challengeEngine: ChallengeEngine
    private lateinit var antiSpoofGuard: AntiSpoofGuard
    
    private var lastProcessedTime = 0L
    private var isProcessing = false
    private var currentFace: DetectedFace? = null
    
    /**
     * Initialize all components of the pipeline.
     */
    suspend fun initialize() {
        _state.value = LivenessState.Initializing
        
        try {
            // Security check: reject if environment is unsafe
            if (securityGuardResult != null && !securityGuardResult.isSafe) {
                Log.w(TAG, "Security check failed: ${securityGuardResult.riskFactors}")
                _state.value = LivenessState.Failed(
                    "Lingkungan tidak aman: ${securityGuardResult.riskFactors.joinToString()}",
                    canRetry = false
                )
                return
            }
            // Initialize detectors
            faceDetector.initialize()
            landmarkExtractor.initialize()
            
            // Warm up MediaPipe (critical for zero-lag experience)
            landmarkExtractor.warmUp()
            
            // Create engines
            challengeEngine = ChallengeEngine(landmarkExtractor)
            antiSpoofGuard = AntiSpoofGuard(landmarkExtractor)
            
            _state.value = LivenessState.Idle
            Log.d(TAG, "Pipeline initialized successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Pipeline initialization failed", e)
            _state.value = LivenessState.Failed(
                "Initialization failed: ${e.message}",
                canRetry = true
            )
        }
    }
    
    /**
     * Process a camera frame through the pipeline.
     * Called for each frame from CameraX.
     */
    @androidx.camera.core.ExperimentalGetImage
    fun processFrame(imageProxy: ImageProxy) {
        // Throttle processing
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastProcessedTime < MIN_FRAME_INTERVAL_MS) {
            imageProxy.close()
            return
        }
        
        if (isProcessing) {
            imageProxy.close()
            return
        }
        
        lastProcessedTime = currentTime
        isProcessing = true
        
        scope.launch {
            try {
                processFrameInternal(imageProxy)
            } catch (e: Exception) {
                Log.e(TAG, "Frame processing error", e)
            } finally {
                isProcessing = false
            }
        }
    }
    
    @androidx.camera.core.ExperimentalGetImage
    private suspend fun processFrameInternal(imageProxy: ImageProxy) {
        when (val currentState = _state.value) {
            is LivenessState.Gating, is LivenessState.GatingFailed -> {
                processGatingPhase(imageProxy)
            }
            is LivenessState.Challenge -> {
                processChallengePhase(imageProxy, currentState)
            }
            else -> {
                imageProxy.close()
            }
        }
    }
    
    /**
     * Phase 1: Gating with ML Kit.
     * Fast face detection and validation.
     */
    @androidx.camera.core.ExperimentalGetImage
    private suspend fun processGatingPhase(imageProxy: ImageProxy) {
        val faces = faceDetector.detectFaces(imageProxy)
        
        when {
            faces.isEmpty() -> {
                _state.value = LivenessState.GatingFailed(
                    GatingFailReason.NO_FACE_DETECTED,
                    "No face detected. Look at the camera."
                )
            }
            faces.size > 1 -> {
                _state.value = LivenessState.GatingFailed(
                    GatingFailReason.MULTIPLE_FACES,
                    "Multiple faces detected. Only one person allowed."
                )
            }
            else -> {
                val face = faces.first()
                currentFace = face
                
                val gatingResult = faceDetector.validateGating(
                    face,
                    imageProxy.width,
                    imageProxy.height
                )
                
                when (gatingResult) {
                    is GatingResult.Pass -> {
                        // Quick anti-spoof check before starting challenges
                        val landmarks = landmarkExtractor.extractLandmarks(imageProxy)
                        if (landmarks != null && antiSpoofGuard.quickSpoofCheck(landmarks)) {
                            _state.value = LivenessState.Failed(
                                reason = "Deteksi spoofing. Harap gunakan wajah asli.",
                                canRetry = true
                            )
                        } else {
                            // Gating passed! Start first challenge
                            val nextChallenge = challengeEngine.getNextChallenge()
                            if (nextChallenge != null) {
                                startChallenge(nextChallenge)
                            }
                        }
                    }
                    is GatingResult.Fail -> {
                        _state.value = LivenessState.GatingFailed(
                            gatingResult.reason,
                            getGatingFailMessage(gatingResult.reason)
                        )
                    }
                }
            }
        }
    }
    
    /**
     * Phase 2: Challenge processing with MediaPipe.
     */
    @androidx.camera.core.ExperimentalGetImage
    private suspend fun processChallengePhase(
        imageProxy: ImageProxy,
        currentState: LivenessState.Challenge
    ) {
        // Extract landmarks using MediaPipe
        val landmarks = landmarkExtractor.extractLandmarks(imageProxy)
        
        // Also update anti-spoof measurements
        currentFace?.let { face ->
            landmarks?.let { lm ->
                antiSpoofGuard.addMeasurement(face.boundingBox, lm)
            }
        }
        
        // Process challenge
        val challengeResult = challengeEngine.processFrame(
            landmarks,
            currentFace?.smilingProbability
        )
        
        when (challengeResult) {
            is ChallengeState.Completed -> {
                // Check if more challenges needed
                val nextChallenge = challengeEngine.getNextChallenge()
                
                if (challengeEngine.areRequiredChallengesComplete()) {
                    // All required challenges done - run final anti-spoof check
                    runFinalCheck()
                } else if (nextChallenge != null) {
                    startChallenge(nextChallenge)
                }
            }
            is ChallengeState.Active -> {
                _state.value = LivenessState.Challenge(
                    type = challengeResult.type,
                    progress = challengeResult.progress,
                    instruction = getChallengeInstruction(challengeResult.type)
                )
            }
            is ChallengeState.Failed -> {
                _state.value = LivenessState.Failed(
                    reason = challengeResult.reason,
                    canRetry = true
                )
            }
            is ChallengeState.Idle -> {
                // Shouldn't happen during challenge phase
            }
        }
    }
    
    /**
     * Run final anti-spoof analysis.
     */
    private fun runFinalCheck() {
        _state.value = LivenessState.Processing("Verifying authenticity...")
        
        val antiSpoofResult = antiSpoofGuard.analyze()
        
        when (antiSpoofResult) {
            is AntiSpoofResult.Pass -> {
                _state.value = LivenessState.Success(
                    completedChallenges = challengeEngine.getCompletedChallenges()
                )
                screenManager.restoreBrightness()
            }
            is AntiSpoofResult.Suspicious -> {
                // For suspicious but not definite spoof, we still pass but log
                Log.w(TAG, "Suspicious activity: ${antiSpoofResult.reason}")
                _state.value = LivenessState.Success(
                    completedChallenges = challengeEngine.getCompletedChallenges()
                )
                screenManager.restoreBrightness()
            }
            is AntiSpoofResult.Spoof -> {
                _state.value = LivenessState.Failed(
                    reason = "Verification failed. Please try again with your real face.",
                    canRetry = true
                )
                screenManager.restoreBrightness()
            }
        }
    }
    
    /**
     * Start a specific challenge.
     */
    private fun startChallenge(type: ChallengeType) {
        challengeEngine.startChallenge(type)
        _state.value = LivenessState.Challenge(
            type = type,
            progress = 0f,
            instruction = getChallengeInstruction(type)
        )
        Log.d(TAG, "Started challenge: $type")
    }
    
    /**
     * Get user-friendly gating fail message.
     */
    private fun getGatingFailMessage(reason: GatingFailReason): String {
        return when (reason) {
            GatingFailReason.NO_FACE_DETECTED -> "No face detected. Look at the camera."
            GatingFailReason.MULTIPLE_FACES -> "Multiple faces detected. Only one person allowed."
            GatingFailReason.FACE_TOO_SMALL -> "Move closer to the camera."
            GatingFailReason.FACE_NOT_CENTERED -> "Center your face in the frame."
            GatingFailReason.FACE_TILTED -> "Keep your head straight."
            GatingFailReason.EYES_NOT_VISIBLE -> "Please remove sunglasses."
            GatingFailReason.MOUTH_NOT_VISIBLE -> "Please remove your mask."
        }
    }
    
    /**
     * Get challenge instruction text in Indonesian.
     * Instructions should be clear about which direction to look.
     */
    private fun getChallengeInstruction(type: ChallengeType): String {
        return when (type) {
            ChallengeType.BLINK -> "Kedipkan mata Anda 2 kali"
            ChallengeType.TURN_LEFT -> "Hadap lurus, lalu palingkan ke KIRI"
            ChallengeType.TURN_RIGHT -> "Hadap lurus, lalu palingkan ke KANAN"
            ChallengeType.SMILE -> "Tersenyum"
        }
    }
    
    /**
     * Start gating phase (called when camera starts).
     */
    fun startGating() {
        if (::challengeEngine.isInitialized) {
            challengeEngine.reset()
        }
        if (::antiSpoofGuard.isInitialized) {
            antiSpoofGuard.reset()
        }
        currentFace = null
        _state.value = LivenessState.Gating()
        Log.d(TAG, "Gating started")
    }
    
    /**
     * Reset and restart the pipeline.
     */
    fun reset() {
        if (::challengeEngine.isInitialized) {
            challengeEngine.reset()
        }
        if (::antiSpoofGuard.isInitialized) {
            antiSpoofGuard.reset()
        }
        currentFace = null
        _state.value = LivenessState.Idle
        Log.d(TAG, "Pipeline reset")
    }
    
    /**
     * Dispose all resources.
     */
    fun dispose() {
        scope.cancel()
        faceDetector.close()
        landmarkExtractor.close()
        screenManager.restoreBrightness()
        Log.d(TAG, "Pipeline disposed")
    }
}
