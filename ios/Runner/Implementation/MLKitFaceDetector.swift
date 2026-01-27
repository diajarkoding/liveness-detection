import Foundation
import AVFoundation
import MLKitFaceDetection
import MLKitVision

/// ML Kit implementation of FaceDetectorProtocol for iOS.
class MLKitFaceDetector: FaceDetectorProtocol {
    
    // Gating thresholds
    private let minFaceSizeRatio: Float = 0.35
    private let maxRollAngle: Float = 20.0
    private let centerTolerance: Float = 0.25
    
    private var faceDetector: FaceDetector?
    
    func initialize() {
        let options = FaceDetectorOptions()
        options.performanceMode = .fast
        options.classificationMode = .all
        options.landmarkMode = .none
        options.minFaceSize = 0.25
        options.isTrackingEnabled = true
        
        faceDetector = FaceDetector.faceDetector(options: options)
        print("[MLKitFaceDetector] Initialized")
    }
    
    func detectFaces(sampleBuffer: CMSampleBuffer, completion: @escaping ([DetectedFace]) -> Void) {
        guard let detector = faceDetector else {
            completion([])
            return
        }
        
        let visionImage = VisionImage(buffer: sampleBuffer)
        visionImage.orientation = imageOrientation(from: UIDevice.current.orientation)
        
        detector.process(visionImage) { faces, error in
            if let error = error {
                print("[MLKitFaceDetector] Detection error: \(error)")
                completion([])
                return
            }
            
            guard let faces = faces else {
                completion([])
                return
            }
            
            let detectedFaces = faces.map { face -> DetectedFace in
                return DetectedFace(
                    boundingBox: face.frame,
                    headEulerAngleX: Float(face.headEulerAngleX),
                    headEulerAngleY: Float(face.headEulerAngleY),
                    headEulerAngleZ: Float(face.headEulerAngleZ),
                    leftEyeOpenProbability: face.hasLeftEyeOpenProbability ? Float(face.leftEyeOpenProbability) : nil,
                    rightEyeOpenProbability: face.hasRightEyeOpenProbability ? Float(face.rightEyeOpenProbability) : nil,
                    smilingProbability: face.hasSmilingProbability ? Float(face.smilingProbability) : nil,
                    trackingId: face.hasTrackingID ? Int(face.trackingID) : nil
                )
            }
            
            completion(detectedFaces)
        }
    }
    
    func validateGating(face: DetectedFace, frameWidth: Int, frameHeight: Int) -> GatingResult {
        // Check 1: Face size
        let faceWidthRatio = Float(face.boundingBox.width) / Float(frameWidth)
        if faceWidthRatio < minFaceSizeRatio {
            return .fail(.faceTooSmall)
        }
        
        // Check 2: Face is centered
        let faceCenterX = Float(face.boundingBox.midX)
        let faceCenterY = Float(face.boundingBox.midY)
        let frameCenterX = Float(frameWidth) / 2
        let frameCenterY = Float(frameHeight) / 2
        
        let xDeviation = abs(faceCenterX - frameCenterX) / Float(frameWidth)
        let yDeviation = abs(faceCenterY - frameCenterY) / Float(frameHeight)
        
        if xDeviation > centerTolerance || yDeviation > centerTolerance {
            return .fail(.faceNotCentered)
        }
        
        // Check 3: Head not tilted
        if abs(face.headEulerAngleZ) > maxRollAngle {
            return .fail(.faceTilted)
        }
        
        // Check 4: Eyes visible
        if face.leftEyeOpenProbability == nil || face.rightEyeOpenProbability == nil {
            return .fail(.eyesNotVisible)
        }
        
        // Check 5: Mouth visible
        if face.smilingProbability == nil {
            return .fail(.mouthNotVisible)
        }
        
        return .pass
    }
    
    func close() {
        faceDetector = nil
        print("[MLKitFaceDetector] Closed")
    }
    
    private func imageOrientation(from deviceOrientation: UIDeviceOrientation) -> UIImage.Orientation {
        switch deviceOrientation {
        case .portraitUpsideDown:
            return .leftMirrored
        case .landscapeLeft:
            return .upMirrored
        case .landscapeRight:
            return .downMirrored
        default:
            return .rightMirrored
        }
    }
}
