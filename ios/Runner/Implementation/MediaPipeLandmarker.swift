import Foundation
import AVFoundation
import MediaPipeTasksVision

/// MediaPipe implementation of LandmarkExtractorProtocol for iOS.
/// Matches Android MediaPipeLandmarker functionality.
class MediaPipeLandmarker: LandmarkExtractorProtocol {
    
    private var faceLandmarker: FaceLandmarker?
    private var isWarmedUp = false
    
    // Key landmark indices for EAR calculation
    private let leftEyeIndices = [33, 160, 158, 133, 153, 144]
    private let rightEyeIndices = [362, 385, 387, 263, 373, 380]
    
    // Key points for head pose estimation (matching Android)
    private let noseTipIdx = 1
    private let chinIdx = 152
    private let leftEyeOuterIdx = 33
    private let rightEyeOuterIdx = 263
    private let leftMouthIdx = 61
    private let rightMouthIdx = 291
    
    func initialize() {
        do {
            guard let modelPath = Bundle.main.path(forResource: "face_landmarker", ofType: "task") else {
                print("[MediaPipeLandmarker] Model file not found")
                return
            }
            
            let baseOptions = BaseOptions()
            baseOptions.modelAssetPath = modelPath
            
            let options = FaceLandmarkerOptions()
            options.baseOptions = baseOptions
            options.runningMode = .image
            options.numFaces = 1
            options.minFaceDetectionConfidence = 0.5
            options.minTrackingConfidence = 0.5
            options.outputFaceBlendshapes = true  // Enable blendshapes for blink detection (matching Android)
            options.outputFacialTransformationMatrixes = false
            
            faceLandmarker = try FaceLandmarker(options: options)
            print("[MediaPipeLandmarker] Initialized with blendshapes enabled")
        } catch {
            print("[MediaPipeLandmarker] Initialization error: \(error)")
        }
    }
    
    func warmUp(completion: @escaping () -> Void) {
        guard !isWarmedUp else {
            completion()
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Create a small black dummy image
            UIGraphicsBeginImageContext(CGSize(width: 64, height: 64))
            UIColor.black.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 64, height: 64))
            let dummyImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            if let image = dummyImage {
                do {
                    let mpImage = try MPImage(uiImage: image)
                    _ = try self?.faceLandmarker?.detect(image: mpImage)
                } catch {
                    print("[MediaPipeLandmarker] Warm-up error: \(error)")
                }
            }
            
            self?.isWarmedUp = true
            print("[MediaPipeLandmarker] Warm-up complete")
            
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    func isReady() -> Bool {
        return faceLandmarker != nil && isWarmedUp
    }
    
    func extractLandmarks(sampleBuffer: CMSampleBuffer, completion: @escaping (FaceLandmarks?) -> Void) {
        guard let landmarker = faceLandmarker else {
            completion(nil)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                    completion(nil)
                    return
                }
                
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                let context = CIContext()
                guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                    completion(nil)
                    return
                }
                
                let uiImage = UIImage(cgImage: cgImage)
                let mpImage = try MPImage(uiImage: uiImage)
                
                let result = try landmarker.detect(image: mpImage)
                
                guard let faceLandmarks = result.faceLandmarks.first else {
                    completion(nil)
                    return
                }
                
                // Convert landmarks with x-flip to match mirrored front camera preview (matching Android)
                let landmarks = faceLandmarks.map { landmark in
                    FaceLandmarks.Landmark(
                        x: 1.0 - Float(landmark.x),  // Flip x to match mirrored front camera preview
                        y: Float(landmark.y),
                        z: Float(landmark.z)
                    )
                }
                
                // Extract blendshapes if available (matching Android)
                var blendshapeMap: [String: Float] = [:]
                if let blendshapes = result.faceBlendshapes?.first {
                    for category in blendshapes.categories {
                        blendshapeMap[category.categoryName ?? ""] = category.score
                    }
                    print("[MediaPipeLandmarker] Blendshapes: eyeBlinkL=\(String(format: "%.2f", blendshapeMap["eyeBlinkLeft"] ?? 0)), eyeBlinkR=\(String(format: "%.2f", blendshapeMap["eyeBlinkRight"] ?? 0))")
                }
                
                let landmarksResult = FaceLandmarks(
                    landmarks: landmarks,
                    timestamp: Date().timeIntervalSince1970,
                    blendshapes: blendshapeMap
                )
                
                completion(landmarksResult)
            } catch {
                print("[MediaPipeLandmarker] Extraction error: \(error)")
                completion(nil)
            }
        }
    }
    
    func calculateEyeAspectRatio(landmarks: FaceLandmarks) -> (left: Float, right: Float) {
        let leftEAR = calculateEAR(landmarks: landmarks, indices: leftEyeIndices)
        let rightEAR = calculateEAR(landmarks: landmarks, indices: rightEyeIndices)
        return (leftEAR, rightEAR)
    }
    
    private func calculateEAR(landmarks: FaceLandmarks, indices: [Int]) -> Float {
        let points = indices.compactMap { landmarks.getLandmark(at: $0) }
        guard points.count == 6 else { return 0 }
        
        let p1 = points[0]
        let p2 = points[1]
        let p3 = points[2]
        let p4 = points[3]
        let p5 = points[4]
        let p6 = points[5]
        
        let vertical1 = distance(p2, p6)
        let vertical2 = distance(p3, p5)
        let horizontal = distance(p1, p4)
        
        guard horizontal > 0 else { return 0 }
        return (vertical1 + vertical2) / (2 * horizontal)
    }
    
    func calculateHeadPose(landmarks: FaceLandmarks) -> HeadPose {
        // Get key landmarks for head pose estimation (matching Android implementation)
        guard let noseTip = landmarks.getLandmark(at: noseTipIdx),
              let leftEye = landmarks.getLandmark(at: leftEyeOuterIdx),
              let rightEye = landmarks.getLandmark(at: rightEyeOuterIdx),
              let leftMouth = landmarks.getLandmark(at: leftMouthIdx),
              let rightMouth = landmarks.getLandmark(at: rightMouthIdx) else {
            return HeadPose(pitch: 0, yaw: 0, roll: 0)
        }
        
        // Calculate roll first (angle of line connecting eyes)
        let eyeDeltaX = rightEye.x - leftEye.x
        let eyeDeltaY = rightEye.y - leftEye.y
        let rollRad = atan2(eyeDeltaY, eyeDeltaX)
        let roll = rollRad * 180 / .pi
        
        // If roll is close to 90 degrees, the image is rotated
        let isImageRotated = abs(roll) > 45
        
        // Calculate eye center
        let eyeCenterX = (leftEye.x + rightEye.x) / 2
        let eyeCenterY = (leftEye.y + rightEye.y) / 2
        
        // Calculate mouth center
        let mouthCenterY = (leftMouth.y + rightMouth.y) / 2
        
        var yaw: Float
        var pitch: Float
        
        if isImageRotated {
            // Image is rotated ~90 degrees
            let noseDeviationY = noseTip.y - eyeCenterY
            
            yaw = roll > 0 ? -noseDeviationY * 600 : noseDeviationY * 600
            
            let noseDeviationX = noseTip.x - eyeCenterX
            pitch = -noseDeviationX * 300
            
            print("[MediaPipeLandmarker] HeadPose (ROTATED): yaw=\(yaw), pitch=\(pitch), roll=\(roll)")
        } else {
            // Normal orientation - use X axis for yaw (matching Android)
            let noseDeviationX = noseTip.x - eyeCenterX
            yaw = noseDeviationX * 600
            
            // Pitch: Compare nose Y position relative to eye-mouth midpoint
            let faceCenterY = (eyeCenterY + mouthCenterY) / 2
            let noseDeviationY = noseTip.y - faceCenterY
            pitch = noseDeviationY * 300
            
            print("[MediaPipeLandmarker] HeadPose (NORMAL): yaw=\(yaw) (noseDevX=\(noseDeviationX)), pitch=\(pitch), roll=\(roll)")
        }
        
        return HeadPose(
            pitch: max(-45, min(45, pitch)),
            yaw: max(-45, min(45, yaw)),
            roll: max(-45, min(45, roll))
        )
    }
    
    func calculateInterOcularDistance(landmarks: FaceLandmarks) -> Float {
        if let leftIris = landmarks.getLandmark(at: FaceLandmarks.leftIrisCenter),
           let rightIris = landmarks.getLandmark(at: FaceLandmarks.rightIrisCenter) {
            return distance(leftIris, rightIris)
        }
        
        if let leftEye = landmarks.getLandmark(at: FaceLandmarks.leftEyeOuter),
           let rightEye = landmarks.getLandmark(at: FaceLandmarks.rightEyeOuter) {
            return distance(leftEye, rightEye)
        }
        
        return 0
    }
    
    func close() {
        faceLandmarker = nil
        isWarmedUp = false
        print("[MediaPipeLandmarker] Closed")
    }
    
    private func distance(_ p1: FaceLandmarks.Landmark, _ p2: FaceLandmarks.Landmark) -> Float {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        return sqrt(dx * dx + dy * dy)
    }
}
