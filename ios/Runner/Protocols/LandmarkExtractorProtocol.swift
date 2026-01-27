import Foundation
import AVFoundation

/// Represents face landmarks from MediaPipe FaceLandmarker.
struct FaceLandmarks {
    let landmarks: [Landmark]
    let timestamp: TimeInterval
    let blendshapes: [String: Float]
    
    struct Landmark {
        let x: Float
        let y: Float
        let z: Float
    }
    
    init(landmarks: [Landmark], timestamp: TimeInterval, blendshapes: [String: Float] = [:]) {
        self.landmarks = landmarks
        self.timestamp = timestamp
        self.blendshapes = blendshapes
    }
    
    /// Get specific landmark by index.
    func getLandmark(at index: Int) -> Landmark? {
        guard index >= 0 && index < landmarks.count else { return nil }
        return landmarks[index]
    }
    
    /// Get eye blink values from blendshapes.
    /// Returns (leftBlink, rightBlink) where 0 = open, 1 = closed
    func getEyeBlinkValues() -> (left: Float, right: Float) {
        let leftBlink = blendshapes["eyeBlinkLeft"] ?? 0
        let rightBlink = blendshapes["eyeBlinkRight"] ?? 0
        return (leftBlink, rightBlink)
    }
    
    // Key landmark indices
    static let leftEyeTop = 159
    static let leftEyeBottom = 145
    static let leftEyeInner = 133
    static let leftEyeOuter = 33
    
    static let rightEyeTop = 386
    static let rightEyeBottom = 374
    static let rightEyeInner = 362
    static let rightEyeOuter = 263
    
    static let leftIrisCenter = 468
    static let rightIrisCenter = 473
    static let noseTip = 1
    static let chin = 152
    static let leftMouth = 61
    static let rightMouth = 291
}

/// Head pose angles extracted from landmarks.
struct HeadPose {
    let pitch: Float  // Up/Down (X rotation)
    let yaw: Float    // Left/Right (Y rotation)
    let roll: Float   // Tilt (Z rotation)
}

/// Protocol for landmark extraction (MediaPipe implementation).
/// Used for deep liveness analysis.
protocol LandmarkExtractorProtocol {
    
    /// Initialize the MediaPipe FaceLandmarker.
    func initialize()
    
    /// Warm up the engine by processing a dummy frame.
    func warmUp(completion: @escaping () -> Void)
    
    /// Check if engine is warmed up and ready.
    func isReady() -> Bool
    
    /// Extract face landmarks from sample buffer.
    func extractLandmarks(sampleBuffer: CMSampleBuffer, completion: @escaping (FaceLandmarks?) -> Void)
    
    /// Calculate Eye Aspect Ratio (EAR) for blink detection.
    func calculateEyeAspectRatio(landmarks: FaceLandmarks) -> (left: Float, right: Float)
    
    /// Calculate head pose from landmarks.
    func calculateHeadPose(landmarks: FaceLandmarks) -> HeadPose
    
    /// Calculate inter-ocular distance.
    func calculateInterOcularDistance(landmarks: FaceLandmarks) -> Float
    
    /// Release extractor resources.
    func close()
}
