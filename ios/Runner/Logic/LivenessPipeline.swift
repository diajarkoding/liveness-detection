import Foundation
import AVFoundation
import CoreGraphics

/// Overall state of the liveness detection pipeline.
/// Matches Android LivenessState.
enum LivenessState {
    case idle
    case initializing
    case gating(message: String)
    case gatingFailed(reason: GatingFailReason, message: String)
    case challenge(type: ChallengeType, progress: Float, instruction: String)
    case processing(message: String)
    case success(completedChallenges: Set<ChallengeType>)
    case failed(reason: String, canRetry: Bool)
    
    static func defaultGating() -> LivenessState {
        return .gating(message: "Position your face in the frame")
    }
    
    static func defaultProcessing() -> LivenessState {
        return .processing(message: "Analyzing...")
    }
}

/// Main coordinator for the liveness detection pipeline.
/// Orchestrates ML Kit (gating) -> MediaPipe (analysis) -> Challenge Engine.
/// Matches Android LivenessPipeline functionality.
class LivenessPipeline {
    
    // Frame throttling to save battery (target ~15 fps processing)
    private let minFrameIntervalMs: TimeInterval = 0.066  // 66ms
    
    private let faceDetector: FaceDetectorProtocol
    private let landmarkExtractor: LandmarkExtractorProtocol
    private let screenManager: ScreenManagerProtocol
    
    private var challengeEngine: ChallengeEngine?
    private var antiSpoofGuard: AntiSpoofGuard?
    
    private var lastProcessedTime: TimeInterval = 0
    private var isProcessing = false
    private var currentFace: DetectedFace?
    
    private var _state: LivenessState = .idle
    var state: LivenessState {
        return _state
    }
    
    var onStateChanged: ((LivenessState) -> Void)?
    
    init(faceDetector: FaceDetectorProtocol,
         landmarkExtractor: LandmarkExtractorProtocol,
         screenManager: ScreenManagerProtocol) {
        self.faceDetector = faceDetector
        self.landmarkExtractor = landmarkExtractor
        self.screenManager = screenManager
    }
    
    /// Initialize all components of the pipeline.
    func initialize(completion: @escaping (Bool) -> Void) {
        updateState(.initializing)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }
            
            // Initialize detectors
            self.faceDetector.initialize()
            self.landmarkExtractor.initialize()
            
            // Warm up MediaPipe (critical for zero-lag experience)
            self.landmarkExtractor.warmUp { [weak self] in
                guard let self = self else {
                    completion(false)
                    return
                }
                
                // Create engines
                self.challengeEngine = ChallengeEngine(landmarkExtractor: self.landmarkExtractor)
                self.antiSpoofGuard = AntiSpoofGuard(landmarkExtractor: self.landmarkExtractor)
                
                self.updateState(.idle)
                print("[LivenessPipeline] Pipeline initialized successfully")
                completion(true)
            }
        }
    }
    
    /// Process a camera frame through the pipeline.
    /// Called for each frame from AVCaptureSession.
    func processFrame(sampleBuffer: CMSampleBuffer) {
        // Throttle processing
        let currentTime = Date().timeIntervalSince1970
        if currentTime - lastProcessedTime < minFrameIntervalMs {
            return
        }
        
        if isProcessing {
            return
        }
        
        lastProcessedTime = currentTime
        isProcessing = true
        
        processFrameInternal(sampleBuffer: sampleBuffer)
    }
    
    private func processFrameInternal(sampleBuffer: CMSampleBuffer) {
        switch _state {
        case .gating, .gatingFailed:
            processGatingPhase(sampleBuffer: sampleBuffer)
        case .challenge:
            processChallengePhase(sampleBuffer: sampleBuffer)
        default:
            isProcessing = false
        }
    }
    
    /// Phase 1: Gating with ML Kit.
    /// Fast face detection and validation.
    private func processGatingPhase(sampleBuffer: CMSampleBuffer) {
        faceDetector.detectFaces(sampleBuffer: sampleBuffer) { [weak self] faces in
            guard let self = self else { return }
            
            defer { self.isProcessing = false }
            
            if faces.isEmpty {
                self.updateState(.gatingFailed(
                    reason: .noFaceDetected,
                    message: "No face detected. Look at the camera."
                ))
                return
            }
            
            if faces.count > 1 {
                self.updateState(.gatingFailed(
                    reason: .multipleFaces,
                    message: "Multiple faces detected. Only one person allowed."
                ))
                return
            }
            
            let face = faces[0]
            self.currentFace = face
            
            let gatingResult = self.faceDetector.validateGating(
                face: face,
                frameWidth: 480,
                frameHeight: 640
            )
            
            switch gatingResult {
            case .pass:
                // Gating passed! Start first challenge
                if let nextChallenge = self.challengeEngine?.getNextChallenge() {
                    self.startChallenge(nextChallenge)
                }
            case .fail(let reason):
                self.updateState(.gatingFailed(
                    reason: reason,
                    message: self.getGatingFailMessage(reason)
                ))
            }
        }
    }
    
    /// Phase 2: Challenge processing with MediaPipe.
    private func processChallengePhase(sampleBuffer: CMSampleBuffer) {
        // Extract landmarks using MediaPipe
        landmarkExtractor.extractLandmarks(sampleBuffer: sampleBuffer) { [weak self] landmarks in
            guard let self = self else { return }
            
            defer { self.isProcessing = false }
            
            // Also update anti-spoof measurements
            if let face = self.currentFace, let landmarks = landmarks {
                self.antiSpoofGuard?.addMeasurement(boundingBox: face.boundingBox, landmarks: landmarks)
            }
            
            // Process challenge
            let challengeResult = self.challengeEngine?.processFrame(
                landmarks: landmarks,
                smilingProbability: self.currentFace?.smilingProbability
            ) ?? .idle
            
            switch challengeResult {
            case .completed(let type):
                // Check if more challenges needed
                let nextChallenge = self.challengeEngine?.getNextChallenge()
                
                if self.challengeEngine?.areRequiredChallengesComplete() == true {
                    // All required challenges done - run final anti-spoof check
                    self.runFinalCheck()
                } else if let next = nextChallenge {
                    self.startChallenge(next)
                }
                
            case .active(let type, let progress):
                self.updateState(.challenge(
                    type: type,
                    progress: progress,
                    instruction: self.getChallengeInstruction(type)
                ))
                
            case .failed(let type, let reason):
                self.updateState(.failed(reason: reason, canRetry: true))
                
            case .idle:
                // Shouldn't happen during challenge phase
                break
            }
        }
    }
    
    /// Run final anti-spoof analysis.
    private func runFinalCheck() {
        updateState(.processing(message: "Verifying authenticity..."))
        
        let antiSpoofResult = antiSpoofGuard?.analyze() ?? .pass
        
        switch antiSpoofResult {
        case .pass:
            updateState(.success(
                completedChallenges: challengeEngine?.getCompletedChallenges() ?? []
            ))
            screenManager.restoreBrightness()
            
        case .suspicious(let reason, _):
            // For suspicious but not definite spoof, we still pass but log
            print("[LivenessPipeline] Suspicious activity: \(reason)")
            updateState(.success(
                completedChallenges: challengeEngine?.getCompletedChallenges() ?? []
            ))
            screenManager.restoreBrightness()
            
        case .spoof:
            updateState(.failed(
                reason: "Verification failed. Please try again with your real face.",
                canRetry: true
            ))
            screenManager.restoreBrightness()
        }
    }
    
    /// Start a specific challenge.
    private func startChallenge(_ type: ChallengeType) {
        challengeEngine?.startChallenge(type)
        updateState(.challenge(
            type: type,
            progress: 0,
            instruction: getChallengeInstruction(type)
        ))
        print("[LivenessPipeline] Started challenge: \(type)")
    }
    
    /// Get user-friendly gating fail message.
    private func getGatingFailMessage(_ reason: GatingFailReason) -> String {
        switch reason {
        case .noFaceDetected:
            return "No face detected. Look at the camera."
        case .multipleFaces:
            return "Multiple faces detected. Only one person allowed."
        case .faceTooSmall:
            return "Move closer to the camera."
        case .faceNotCentered:
            return "Center your face in the frame."
        case .faceTilted:
            return "Keep your head straight."
        case .eyesNotVisible:
            return "Please remove sunglasses."
        case .mouthNotVisible:
            return "Please remove your mask."
        }
    }
    
    /// Get challenge instruction text in Indonesian.
    /// Instructions should be clear about which direction to look (matching Android).
    private func getChallengeInstruction(_ type: ChallengeType) -> String {
        switch type {
        case .blink:
            return "Kedipkan mata Anda 2 kali"
        case .turnLeft:
            return "Hadap lurus, lalu palingkan ke KIRI"
        case .turnRight:
            return "Hadap lurus, lalu palingkan ke KANAN"
        case .smile:
            return "Tersenyum"
        }
    }
    
    /// Start gating phase (called when camera starts).
    func startGating() {
        challengeEngine?.reset()
        antiSpoofGuard?.reset()
        currentFace = nil
        updateState(.gating(message: "Position your face in the frame"))
        print("[LivenessPipeline] Gating started")
    }
    
    /// Reset and restart the pipeline.
    func reset() {
        challengeEngine?.reset()
        antiSpoofGuard?.reset()
        currentFace = nil
        updateState(.idle)
        print("[LivenessPipeline] Pipeline reset")
    }
    
    /// Dispose all resources.
    func dispose() {
        faceDetector.close()
        landmarkExtractor.close()
        screenManager.restoreBrightness()
        print("[LivenessPipeline] Pipeline disposed")
    }
    
    private func updateState(_ newState: LivenessState) {
        _state = newState
        DispatchQueue.main.async { [weak self] in
            self?.onStateChanged?(newState)
        }
    }
}
