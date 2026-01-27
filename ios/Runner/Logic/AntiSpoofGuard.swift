import Foundation
import CoreGraphics

/// Result of anti-spoof check.
enum AntiSpoofResult {
    case pass
    case suspicious(reason: String, confidence: Float)
    case spoof(reason: String)
}

/// Passive liveness guard using geometric consistency checks.
/// Matches Android AntiSpoofGuard functionality.
///
/// Key insight: In a real 3D face, when the face moves closer/farther,
/// the bounding box size and inter-ocular distance change proportionally.
/// In a 2D screen (spoof), this ratio often becomes inconsistent due to
/// lens distortion and flat surface behavior.
class AntiSpoofGuard {
    
    // Minimum samples needed for analysis
    private let minSamples = 10
    
    // Maximum allowed variance in box-to-IOD ratio
    private let maxRatioVariance: Float = 0.15
    
    // Minimum movement required for analysis (bbox change)
    private let minMovementThreshold: Float = 0.05
    
    // Suspicion threshold before marking as spoof
    private let suspicionThreshold: Float = 0.7
    
    // History of measurements for geometric consistency check
    private var measurements: [Measurement] = []
    
    struct Measurement {
        let boundingBoxArea: Float
        let interOcularDistance: Float
        let timestamp: TimeInterval
    }
    
    private let landmarkExtractor: LandmarkExtractorProtocol
    
    init(landmarkExtractor: LandmarkExtractorProtocol) {
        self.landmarkExtractor = landmarkExtractor
    }
    
    /// Add a new frame measurement for analysis.
    func addMeasurement(boundingBox: CGRect, landmarks: FaceLandmarks) {
        let boxArea = Float(boundingBox.width * boundingBox.height)
        let iod = landmarkExtractor.calculateInterOcularDistance(landmarks: landmarks)
        
        if iod > 0 {
            measurements.append(Measurement(
                boundingBoxArea: boxArea,
                interOcularDistance: iod,
                timestamp: Date().timeIntervalSince1970
            ))
            
            // Keep only recent measurements (last 30)
            if measurements.count > 30 {
                measurements.removeFirst()
            }
        }
    }
    
    /// Analyze collected measurements for spoofing indicators.
    ///
    /// The key check: In a real face, ratio of (BoundingBox Area) to
    /// (Inter-Ocular Distance²) should remain relatively constant
    /// as the face moves toward/away from camera.
    func analyze() -> AntiSpoofResult {
        if measurements.count < minSamples {
            print("[AntiSpoofGuard] Not enough samples for analysis: \(measurements.count)/\(minSamples)")
            return .pass  // Not enough data yet
        }
        
        // Check if there's enough movement in the data
        let minBox = measurements.map { $0.boundingBoxArea }.min() ?? 0
        let maxBox = measurements.map { $0.boundingBoxArea }.max() ?? 0
        let movementRange = maxBox > 0 ? (maxBox - minBox) / maxBox : 0
        
        if movementRange < minMovementThreshold {
            print("[AntiSpoofGuard] Not enough movement for analysis: \(movementRange)")
            return .pass  // Face didn't move enough to analyze
        }
        
        // Calculate consistency ratio for each measurement
        // Ratio = BoundingBoxArea / (InterOcularDistance²)
        // This should be relatively constant for a real 3D face
        let ratios = measurements.map { m -> Float in
            m.boundingBoxArea / (m.interOcularDistance * m.interOcularDistance)
        }
        
        let meanRatio = ratios.reduce(0, +) / Float(ratios.count)
        let variance = ratios.map { abs($0 - meanRatio) / meanRatio }.reduce(0, +) / Float(ratios.count)
        
        print("[AntiSpoofGuard] Geometric analysis - Mean ratio: \(meanRatio), Variance: \(variance)")
        
        if variance > maxRatioVariance * 2 {
            print("[AntiSpoofGuard] SPOOF DETECTED - High variance: \(variance)")
            return .spoof(reason: "Unnatural geometric behavior detected")
        } else if variance > maxRatioVariance {
            print("[AntiSpoofGuard] Suspicious behavior - Variance: \(variance)")
            return .suspicious(
                reason: "Unusual movement pattern",
                confidence: variance / (maxRatioVariance * 2)
            )
        } else {
            print("[AntiSpoofGuard] Geometric check passed")
            return .pass
        }
    }
    
    /// Quick check for obvious 2D indicators.
    /// Returns true if definitely a spoof, false if needs more analysis.
    func quickSpoofCheck(landmarks: FaceLandmarks) -> Bool {
        // Check for unnaturally flat z-coordinates
        // In a real face, there's significant z-depth variation
        let zValues = landmarks.landmarks.map { $0.z }
        let zRange = (zValues.max() ?? 0) - (zValues.min() ?? 0)
        
        // If z-range is near zero, likely a flat image
        if zRange < 0.01 {
            print("[AntiSpoofGuard] Quick spoof check: Flat z-profile detected")
            return true
        }
        
        return false
    }
    
    /// Reset all measurements.
    func reset() {
        measurements.removeAll()
        print("[AntiSpoofGuard] AntiSpoofGuard reset")
    }
    
    /// Get current sample count.
    func getSampleCount() -> Int {
        return measurements.count
    }
}
