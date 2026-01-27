import Foundation
import AVFoundation

/// Protocol for face detection (ML Kit implementation).
/// Used as the "gatekeeper" layer before deep analysis.
protocol FaceDetectorProtocol {
    
    /// Initialize the face detector.
    func initialize()
    
    /// Detect faces in the given sample buffer.
    /// - Parameter sampleBuffer: CMSampleBuffer from camera
    /// - Returns: Array of detected faces
    func detectFaces(sampleBuffer: CMSampleBuffer, completion: @escaping ([DetectedFace]) -> Void)
    
    /// Validate if the detected face passes gating rules.
    func validateGating(face: DetectedFace, frameWidth: Int, frameHeight: Int) -> GatingResult
    
    /// Release detector resources.
    func close()
}

/// Represents a detected face.
struct DetectedFace {
    let boundingBox: CGRect
    let headEulerAngleX: Float  // Pitch
    let headEulerAngleY: Float  // Yaw
    let headEulerAngleZ: Float  // Roll
    let leftEyeOpenProbability: Float?
    let rightEyeOpenProbability: Float?
    let smilingProbability: Float?
    let trackingId: Int?
}

/// Result of face gating validation.
enum GatingResult {
    case pass
    case fail(GatingFailReason)
}

/// Reasons why gating might fail.
enum GatingFailReason: String {
    case noFaceDetected = "NO_FACE_DETECTED"
    case multipleFaces = "MULTIPLE_FACES"
    case faceTooSmall = "FACE_TOO_SMALL"
    case faceNotCentered = "FACE_NOT_CENTERED"
    case faceTilted = "FACE_TILTED"
    case eyesNotVisible = "EYES_NOT_VISIBLE"
    case mouthNotVisible = "MOUTH_NOT_VISIBLE"
}
