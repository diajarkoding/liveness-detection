import Foundation
import UIKit

/// Protocol for screen brightness management.
/// Used for low-light environment handling.
protocol ScreenManagerProtocol {
    
    /// Get current screen brightness.
    func getCurrentBrightness() -> Float
    
    /// Set screen brightness.
    func setBrightness(_ brightness: Float)
    
    /// Boost brightness to maximum.
    func boostBrightness()
    
    /// Restore brightness to value before boost.
    func restoreBrightness()
    
    /// Check if brightness is currently boosted.
    func isBoosted() -> Bool
}

/// iOS implementation of ScreenManagerProtocol.
class IOSScreenManager: ScreenManagerProtocol {
    
    private var originalBrightness: Float = -1
    private var isBrightnessBoosted = false
    
    func getCurrentBrightness() -> Float {
        return Float(UIScreen.main.brightness)
    }
    
    func setBrightness(_ brightness: Float) {
        let clampedBrightness = max(0, min(1, brightness))
        DispatchQueue.main.async {
            UIScreen.main.brightness = CGFloat(clampedBrightness)
        }
    }
    
    func boostBrightness() {
        guard !isBrightnessBoosted else { return }
        
        originalBrightness = getCurrentBrightness()
        setBrightness(1.0)
        isBrightnessBoosted = true
    }
    
    func restoreBrightness() {
        guard isBrightnessBoosted else { return }
        
        if originalBrightness >= 0 {
            setBrightness(originalBrightness)
        }
        isBrightnessBoosted = false
    }
    
    func isBoosted() -> Bool {
        return isBrightnessBoosted
    }
}
