package com.example.liveness_detection.logic

import android.util.Log
import com.example.liveness_detection.core.FaceLandmarks
import com.example.liveness_detection.core.HeadPose
import com.example.liveness_detection.core.ILandmarkExtractor

/**
 * Enum representing available liveness challenges.
 */
enum class ChallengeType {
    BLINK,
    TURN_LEFT,
    TURN_RIGHT,
    SMILE
}

/**
 * State of a challenge execution.
 */
sealed class ChallengeState {
    data object Idle : ChallengeState()
    data class Active(val type: ChallengeType, val progress: Float = 0f) : ChallengeState()
    data class Completed(val type: ChallengeType) : ChallengeState()
    data class Failed(val type: ChallengeType, val reason: String) : ChallengeState()
}

/**
 * Engine for managing liveness challenges.
 * Handles blink detection, head turn, and smile detection.
 */
class ChallengeEngine(
    private val landmarkExtractor: ILandmarkExtractor
) {
    companion object {
        private const val TAG = "ChallengeEngine"
        
        // Blink detection thresholds using MediaPipe blendshapes
        // Blendshape values: 0 = eyes open, 1 = eyes closed
        private const val BLINK_CLOSED_THRESHOLD = 0.4f   // Eyes considered closed when > 0.4
        private const val BLINK_OPEN_THRESHOLD = 0.2f     // Eyes considered open when < 0.2
        private const val BLINK_MAX_DURATION_MS = 2000L   // Blink must complete within 2s
        
        // Head turn thresholds
        private const val TURN_MIN_ANGLE = 20f          // Minimum yaw angle for turn completion
        private const val TURN_MAX_ANGLE = 45f          // Maximum yaw angle (don't lose face)
        private const val CENTER_THRESHOLD = 12f         // User must start from center (yaw < 12)
        
        // Challenge timeout
        private const val CHALLENGE_TIMEOUT_MS = 15_000L  // 15 seconds per challenge
    }
    
    // Current challenge state
    private var currentChallenge: ChallengeType? = null
    private var challengeStartTime: Long = 0
    
    // Blink detection state
    private var eyeClosedTime: Long = 0
    private var wasEyesClosed = false
    
    // Turn detection state
    private var initialYaw: Float? = null
    private var maxYawReached: Float = 0f
    private var hasStartedFromCenter = false  // User must start from center position
    
    // Challenge results
    private val completedChallenges = mutableSetOf<ChallengeType>()
    
    // Sequential challenge order
    private val challengeSequence = listOf(
        ChallengeType.TURN_RIGHT,
        ChallengeType.TURN_LEFT,
        ChallengeType.BLINK
    )
    private var currentChallengeIndex = 0
    
    // Blink counting for multiple blinks
    private var blinkCount = 0
    private val requiredBlinks = 2
    
    /**
     * Start a new challenge.
     */
    fun startChallenge(type: ChallengeType) {
        currentChallenge = type
        challengeStartTime = System.currentTimeMillis()
        
        // Reset state for the challenge
        when (type) {
            ChallengeType.BLINK -> {
                eyeClosedTime = 0
                wasEyesClosed = false
                blinkCount = 0
            }
            ChallengeType.TURN_LEFT, ChallengeType.TURN_RIGHT -> {
                initialYaw = null
                maxYawReached = 0f
                hasStartedFromCenter = false  // Must start from center
            }
            ChallengeType.SMILE -> {
                // Smile detection uses ML Kit's smiling probability
            }
        }
        
        Log.d(TAG, "Started challenge: $type")
    }
    
    /**
     * Process a frame for the current challenge.
     * @return ChallengeState indicating current status
     */
    fun processFrame(
        landmarks: FaceLandmarks?,
        smilingProbability: Float? = null
    ): ChallengeState {
        val challenge = currentChallenge ?: return ChallengeState.Idle
        
        // Check timeout
        val elapsed = System.currentTimeMillis() - challengeStartTime
        if (elapsed > CHALLENGE_TIMEOUT_MS) {
            Log.d(TAG, "Challenge timed out: $challenge")
            return ChallengeState.Failed(challenge, "Timeout - please try again")
        }
        
        if (landmarks == null) {
            return ChallengeState.Active(challenge, 0f)
        }
        
        return when (challenge) {
            ChallengeType.BLINK -> processBlinkChallenge(landmarks)
            ChallengeType.TURN_LEFT -> processTurnChallenge(landmarks, isLeft = true)
            ChallengeType.TURN_RIGHT -> processTurnChallenge(landmarks, isLeft = false)
            ChallengeType.SMILE -> processSmileChallenge(smilingProbability)
        }
    }
    
    /**
     * Process blink detection using MediaPipe blendshapes.
     * Blendshape eyeBlinkLeft/eyeBlinkRight: 0 = open, 1 = closed
     * Blink = eyes close (value > threshold) then open (value < threshold) within time limit
     * Requires multiple blinks to complete.
     */
    private fun processBlinkChallenge(landmarks: FaceLandmarks): ChallengeState {
        // Use blendshapes for more accurate blink detection
        val (leftBlink, rightBlink) = landmarks.getEyeBlinkValues()
        val avgBlink = (leftBlink + rightBlink) / 2f
        
        val currentTime = System.currentTimeMillis()
        
        Log.d(TAG, "Blink: avg=${"%.2f".format(avgBlink)} (L=${"%.2f".format(leftBlink)}, R=${"%.2f".format(rightBlink)}), closed=$wasEyesClosed, count=$blinkCount/$requiredBlinks")
        
        // State machine for blink detection
        if (!wasEyesClosed) {
            // Waiting for eyes to close
            if (avgBlink > BLINK_CLOSED_THRESHOLD) {
                eyeClosedTime = currentTime
                wasEyesClosed = true
                Log.d(TAG, ">>> Eyes CLOSED detected, blink=${"%.2f".format(avgBlink)}")
            }
            val progress = blinkCount.toFloat() / requiredBlinks.toFloat()
            return ChallengeState.Active(ChallengeType.BLINK, progress)
        } else {
            // Eyes were closed, waiting for them to open
            if (avgBlink < BLINK_OPEN_THRESHOLD) {
                // Eyes opened after being closed - this is a blink!
                val blinkDuration = currentTime - eyeClosedTime
                Log.d(TAG, ">>> Eyes OPENED after close, duration=${blinkDuration}ms, blink=${"%.2f".format(avgBlink)}")
                
                if (blinkDuration < BLINK_MAX_DURATION_MS) {
                    // Valid blink detected!
                    blinkCount++
                    Log.d(TAG, ">>> BLINK #$blinkCount DETECTED! Duration=${blinkDuration}ms")
                    
                    // Reset for next blink
                    wasEyesClosed = false
                    eyeClosedTime = 0
                    
                    if (blinkCount >= requiredBlinks) {
                        // All required blinks completed
                        Log.d(TAG, ">>> ALL BLINKS COMPLETED! Total=$blinkCount")
                        completedChallenges.add(ChallengeType.BLINK)
                        currentChallenge = null
                        return ChallengeState.Completed(ChallengeType.BLINK)
                    }
                    
                    // More blinks needed
                    val progress = blinkCount.toFloat() / requiredBlinks.toFloat()
                    return ChallengeState.Active(ChallengeType.BLINK, progress)
                } else {
                    // Too slow, reset this blink attempt but keep count
                    Log.d(TAG, ">>> Blink too slow (${blinkDuration}ms > ${BLINK_MAX_DURATION_MS}ms), resetting")
                    wasEyesClosed = false
                    eyeClosedTime = 0
                }
            }
            // Eyes still closed or partially open - show "in progress" indicator
            val progress = blinkCount.toFloat() / requiredBlinks.toFloat()
            return ChallengeState.Active(ChallengeType.BLINK, (progress + 0.15f).coerceAtMost(0.99f))
        }
    }
    
    /**
     * Process head turn detection.
     * Turn = yaw angle reaches threshold in the specified direction
     * User must START from center position first, then turn.
     * 
     * Yaw convention after MediaPipe processing with x-flip:
     * - Positive yaw: User's head turned to their RIGHT
     * - Negative yaw: User's head turned to their LEFT
     */
    private fun processTurnChallenge(landmarks: FaceLandmarks, isLeft: Boolean): ChallengeState {
        val headPose = landmarkExtractor.calculateHeadPose(landmarks)
        val yaw = headPose.yaw
        val absYaw = kotlin.math.abs(yaw)
        
        val challenge = if (isLeft) ChallengeType.TURN_LEFT else ChallengeType.TURN_RIGHT
        
        // Step 1: User must first be at center position
        if (!hasStartedFromCenter) {
            if (absYaw <= CENTER_THRESHOLD) {
                hasStartedFromCenter = true
                Log.d(TAG, "Turn $challenge: User started from CENTER (yaw=$yaw)")
            } else {
                // Show message to look straight first
                Log.d(TAG, "Turn $challenge: Waiting for center position (yaw=$yaw, need < $CENTER_THRESHOLD)")
                return ChallengeState.Active(challenge, 0f)
            }
        }
        
        // Step 2: Now detect the turn
        // For TURN_LEFT: we need negative yaw (user looking left)
        // For TURN_RIGHT: we need positive yaw (user looking right)
        val isCorrectDirection = if (isLeft) yaw < -5f else yaw > 5f
        
        val progress = if (isCorrectDirection) {
            (absYaw / TURN_MIN_ANGLE).coerceIn(0f, 1f)
        } else {
            0f
        }
        
        Log.d(TAG, "Turn: isLeft=$isLeft, yaw=$yaw, absYaw=$absYaw, correctDir=$isCorrectDirection, progress=$progress")
        
        // Check if turn is complete
        if (isCorrectDirection && absYaw >= TURN_MIN_ANGLE) {
            Log.d(TAG, "TURN COMPLETED! Direction=${if (isLeft) "LEFT" else "RIGHT"}, yaw=$yaw")
            completedChallenges.add(challenge)
            currentChallenge = null
            return ChallengeState.Completed(challenge)
        }
        
        return ChallengeState.Active(challenge, progress)
    }
    
    /**
     * Process smile detection.
     * Uses ML Kit's smiling probability.
     */
    private fun processSmileChallenge(smilingProbability: Float?): ChallengeState {
        val prob = smilingProbability ?: 0f
        
        if (prob > 0.8f) {
            Log.d(TAG, "Smile detected! Probability=$prob")
            completedChallenges.add(ChallengeType.SMILE)
            currentChallenge = null
            return ChallengeState.Completed(ChallengeType.SMILE)
        }
        
        val progress = (prob / 0.8f).coerceIn(0f, 1f)
        return ChallengeState.Active(ChallengeType.SMILE, progress)
    }
    
    /**
     * Get the next challenge in sequential order.
     * Challenges are executed in fixed order: TURN_RIGHT -> TURN_LEFT -> BLINK
     */
    fun getNextChallenge(): ChallengeType? {
        // Find the next uncompleted challenge in sequence
        for (i in currentChallengeIndex until challengeSequence.size) {
            val challenge = challengeSequence[i]
            if (challenge !in completedChallenges) {
                currentChallengeIndex = i
                Log.d(TAG, "Next challenge in sequence: $challenge (index=$i)")
                return challenge
            }
        }
        Log.d(TAG, "No more challenges in sequence")
        return null
    }
    
    /**
     * Check if all required challenges are completed.
     * For sequential flow, we require all challenges in the sequence.
     */
    fun areRequiredChallengesComplete(): Boolean {
        val allComplete = challengeSequence.all { it in completedChallenges }
        Log.d(TAG, "Required challenges complete: $allComplete, completed=$completedChallenges")
        return allComplete
    }
    
    /**
     * Reset all challenge state.
     */
    fun reset() {
        currentChallenge = null
        challengeStartTime = 0
        eyeClosedTime = 0
        wasEyesClosed = false
        initialYaw = null
        maxYawReached = 0f
        hasStartedFromCenter = false
        blinkCount = 0
        currentChallengeIndex = 0
        completedChallenges.clear()
        Log.d(TAG, "Challenge engine reset")
    }
    
    /**
     * Get completed challenges.
     */
    fun getCompletedChallenges(): Set<ChallengeType> = completedChallenges.toSet()
}
