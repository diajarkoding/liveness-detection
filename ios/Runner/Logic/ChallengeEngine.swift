import Foundation
import AVFoundation

/// Challenge types for active liveness.
enum ChallengeType: String {
    case blink = "BLINK"
    case turnLeft = "TURN_LEFT"
    case turnRight = "TURN_RIGHT"
    case smile = "SMILE"
}

/// State of a challenge execution.
enum ChallengeState {
    case idle
    case active(type: ChallengeType, progress: Float)
    case completed(type: ChallengeType)
    case failed(type: ChallengeType, reason: String)
}

/// Engine for managing liveness challenges.
/// Matches Android ChallengeEngine functionality.
class ChallengeEngine {
    
    // Blink detection thresholds using MediaPipe blendshapes (matching Android)
    private let blinkClosedThreshold: Float = 0.4   // Eyes considered closed when > 0.4
    private let blinkOpenThreshold: Float = 0.2     // Eyes considered open when < 0.2
    private let blinkMaxDurationMs: TimeInterval = 2.0  // Blink must complete within 2s
    
    // Head turn thresholds (matching Android)
    private let turnMinAngle: Float = 20.0          // Minimum yaw angle for turn completion
    private let turnMaxAngle: Float = 45.0          // Maximum yaw angle (don't lose face)
    private let centerThreshold: Float = 12.0       // User must start from center (yaw < 12)
    
    // Challenge timeout (matching Android)
    private let challengeTimeoutMs: TimeInterval = 15.0  // 15 seconds per challenge
    
    // Current challenge state
    private var currentChallenge: ChallengeType?
    private var challengeStartTime: Date?
    
    // Blink detection state
    private var eyeClosedTime: Date?
    private var wasEyesClosed = false
    
    // Turn detection state
    private var initialYaw: Float?
    private var maxYawReached: Float = 0
    private var hasStartedFromCenter = false  // User must start from center position
    
    // Challenge results
    private var completedChallenges = Set<ChallengeType>()
    
    // Sequential challenge order (matching Android)
    private let challengeSequence: [ChallengeType] = [
        .turnRight,
        .turnLeft,
        .blink
    ]
    private var currentChallengeIndex = 0
    
    // Blink counting for multiple blinks (matching Android)
    private var blinkCount = 0
    private let requiredBlinks = 2
    
    private let landmarkExtractor: LandmarkExtractorProtocol
    
    init(landmarkExtractor: LandmarkExtractorProtocol) {
        self.landmarkExtractor = landmarkExtractor
    }
    
    /// Start a new challenge.
    func startChallenge(_ type: ChallengeType) {
        currentChallenge = type
        challengeStartTime = Date()
        
        // Reset state for the challenge
        switch type {
        case .blink:
            eyeClosedTime = nil
            wasEyesClosed = false
            blinkCount = 0
        case .turnLeft, .turnRight:
            initialYaw = nil
            maxYawReached = 0
            hasStartedFromCenter = false  // Must start from center
        case .smile:
            break
        }
        
        print("[ChallengeEngine] Started challenge: \(type)")
    }
    
    /// Process a frame for the current challenge.
    func processFrame(landmarks: FaceLandmarks?, smilingProbability: Float?) -> ChallengeState {
        guard let challenge = currentChallenge,
              let startTime = challengeStartTime else {
            return .idle
        }
        
        // Check timeout
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed > challengeTimeoutMs {
            print("[ChallengeEngine] Challenge timed out: \(challenge)")
            return .failed(type: challenge, reason: "Timeout - please try again")
        }
        
        guard let landmarks = landmarks else {
            return .active(type: challenge, progress: 0)
        }
        
        switch challenge {
        case .blink:
            return processBlinkChallenge(landmarks: landmarks)
        case .turnLeft:
            return processTurnChallenge(landmarks: landmarks, isLeft: true)
        case .turnRight:
            return processTurnChallenge(landmarks: landmarks, isLeft: false)
        case .smile:
            return processSmileChallenge(smilingProbability: smilingProbability)
        }
    }
    
    /// Process blink detection using MediaPipe blendshapes.
    /// Blendshape eyeBlinkLeft/eyeBlinkRight: 0 = open, 1 = closed
    /// Blink = eyes close (value > threshold) then open (value < threshold) within time limit
    /// Requires multiple blinks to complete (matching Android).
    private func processBlinkChallenge(landmarks: FaceLandmarks) -> ChallengeState {
        // Use blendshapes for more accurate blink detection
        let (leftBlink, rightBlink) = landmarks.getEyeBlinkValues()
        let avgBlink = (leftBlink + rightBlink) / 2
        
        let currentTime = Date()
        
        print("[ChallengeEngine] Blink: avg=\(String(format: "%.2f", avgBlink)) (L=\(String(format: "%.2f", leftBlink)), R=\(String(format: "%.2f", rightBlink))), closed=\(wasEyesClosed), count=\(blinkCount)/\(requiredBlinks)")
        
        // State machine for blink detection
        if !wasEyesClosed {
            // Waiting for eyes to close
            if avgBlink > blinkClosedThreshold {
                eyeClosedTime = currentTime
                wasEyesClosed = true
                print("[ChallengeEngine] >>> Eyes CLOSED detected, blink=\(String(format: "%.2f", avgBlink))")
            }
            let progress = Float(blinkCount) / Float(requiredBlinks)
            return .active(type: .blink, progress: progress)
        } else {
            // Eyes were closed, waiting for them to open
            if avgBlink < blinkOpenThreshold {
                // Eyes opened after being closed - this is a blink!
                let blinkDuration = currentTime.timeIntervalSince(eyeClosedTime ?? currentTime)
                print("[ChallengeEngine] >>> Eyes OPENED after close, duration=\(blinkDuration * 1000)ms, blink=\(String(format: "%.2f", avgBlink))")
                
                if blinkDuration < blinkMaxDurationMs {
                    // Valid blink detected!
                    blinkCount += 1
                    print("[ChallengeEngine] >>> BLINK #\(blinkCount) DETECTED! Duration=\(blinkDuration * 1000)ms")
                    
                    // Reset for next blink
                    wasEyesClosed = false
                    eyeClosedTime = nil
                    
                    if blinkCount >= requiredBlinks {
                        // All required blinks completed
                        print("[ChallengeEngine] >>> ALL BLINKS COMPLETED! Total=\(blinkCount)")
                        completedChallenges.insert(.blink)
                        currentChallenge = nil
                        return .completed(type: .blink)
                    }
                    
                    // More blinks needed
                    let progress = Float(blinkCount) / Float(requiredBlinks)
                    return .active(type: .blink, progress: progress)
                } else {
                    // Too slow, reset this blink attempt but keep count
                    print("[ChallengeEngine] >>> Blink too slow (\(blinkDuration * 1000)ms > \(blinkMaxDurationMs * 1000)ms), resetting")
                    wasEyesClosed = false
                    eyeClosedTime = nil
                }
            }
            // Eyes still closed or partially open - show "in progress" indicator
            let progress = Float(blinkCount) / Float(requiredBlinks)
            return .active(type: .blink, progress: min(progress + 0.15, 0.99))
        }
    }
    
    /// Process head turn detection.
    /// Turn = yaw angle reaches threshold in the specified direction
    /// User must START from center position first, then turn.
    ///
    /// Yaw convention after MediaPipe processing with x-flip:
    /// - Positive yaw: User's head turned to their RIGHT
    /// - Negative yaw: User's head turned to their LEFT
    private func processTurnChallenge(landmarks: FaceLandmarks, isLeft: Bool) -> ChallengeState {
        let headPose = landmarkExtractor.calculateHeadPose(landmarks: landmarks)
        let yaw = headPose.yaw
        let absYaw = abs(yaw)
        
        let challengeType: ChallengeType = isLeft ? .turnLeft : .turnRight
        
        // Step 1: User must first be at center position
        if !hasStartedFromCenter {
            if absYaw <= centerThreshold {
                hasStartedFromCenter = true
                print("[ChallengeEngine] Turn \(challengeType): User started from CENTER (yaw=\(yaw))")
            } else {
                // Show message to look straight first
                print("[ChallengeEngine] Turn \(challengeType): Waiting for center position (yaw=\(yaw), need < \(centerThreshold))")
                return .active(type: challengeType, progress: 0)
            }
        }
        
        // Step 2: Now detect the turn
        // For TURN_LEFT: we need negative yaw (user looking left)
        // For TURN_RIGHT: we need positive yaw (user looking right)
        let isCorrectDirection = isLeft ? yaw < -5 : yaw > 5
        
        let progress: Float
        if isCorrectDirection {
            progress = min(1, max(0, absYaw / turnMinAngle))
        } else {
            progress = 0
        }
        
        print("[ChallengeEngine] Turn: isLeft=\(isLeft), yaw=\(yaw), absYaw=\(absYaw), correctDir=\(isCorrectDirection), progress=\(progress)")
        
        // Check if turn is complete
        if isCorrectDirection && absYaw >= turnMinAngle {
            print("[ChallengeEngine] TURN COMPLETED! Direction=\(isLeft ? "LEFT" : "RIGHT"), yaw=\(yaw)")
            completedChallenges.insert(challengeType)
            currentChallenge = nil
            return .completed(type: challengeType)
        }
        
        return .active(type: challengeType, progress: progress)
    }
    
    /// Process smile detection using ML Kit's smiling probability.
    private func processSmileChallenge(smilingProbability: Float?) -> ChallengeState {
        let prob = smilingProbability ?? 0
        
        if prob > 0.8 {
            print("[ChallengeEngine] Smile detected! Probability=\(prob)")
            completedChallenges.insert(.smile)
            currentChallenge = nil
            return .completed(type: .smile)
        }
        
        let progress = min(1, prob / 0.8)
        return .active(type: .smile, progress: progress)
    }
    
    /// Get the next challenge in sequential order.
    /// Challenges are executed in fixed order: TURN_RIGHT -> TURN_LEFT -> BLINK
    func getNextChallenge() -> ChallengeType? {
        // Find the next uncompleted challenge in sequence
        for i in currentChallengeIndex..<challengeSequence.count {
            let challenge = challengeSequence[i]
            if !completedChallenges.contains(challenge) {
                currentChallengeIndex = i
                print("[ChallengeEngine] Next challenge in sequence: \(challenge) (index=\(i))")
                return challenge
            }
        }
        print("[ChallengeEngine] No more challenges in sequence")
        return nil
    }
    
    /// Check if all required challenges are completed.
    /// For sequential flow, we require all challenges in the sequence.
    func areRequiredChallengesComplete() -> Bool {
        let allComplete = challengeSequence.allSatisfy { completedChallenges.contains($0) }
        print("[ChallengeEngine] Required challenges complete: \(allComplete), completed=\(completedChallenges)")
        return allComplete
    }
    
    /// Get completed challenges.
    func getCompletedChallenges() -> Set<ChallengeType> {
        return completedChallenges
    }
    
    /// Reset all challenge state.
    func reset() {
        currentChallenge = nil
        challengeStartTime = nil
        eyeClosedTime = nil
        wasEyesClosed = false
        initialYaw = nil
        maxYawReached = 0
        hasStartedFromCenter = false
        blinkCount = 0
        currentChallengeIndex = 0
        completedChallenges.removeAll()
        print("[ChallengeEngine] Challenge engine reset")
    }
}
