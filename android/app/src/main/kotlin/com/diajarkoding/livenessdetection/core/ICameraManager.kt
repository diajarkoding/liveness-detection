package com.diajarkoding.livenessdetection.core

import android.graphics.ImageFormat
import androidx.camera.core.ImageProxy

/**
 * Interface for camera management.
 * Abstracts CameraX operations for testability.
 */
interface ICameraManager {
    
    /**
     * Initialize and start the camera with 4:3 aspect ratio.
     * @param surfaceProvider Surface for preview rendering
     * @param onFrameAvailable Callback for each frame (ImageProxy)
     */
    fun startCamera(
        surfaceProvider: Any,
        onFrameAvailable: (ImageProxy) -> Unit
    )
    
    /**
     * Stop camera and release all resources.
     */
    fun stopCamera()
    
    /**
     * Check if camera is currently running.
     */
    fun isRunning(): Boolean
    
    /**
     * Switch between front and back camera.
     * Default should be front camera for liveness.
     */
    fun switchCamera()
    
    /**
     * Get current camera lens facing (FRONT or BACK).
     */
    fun getLensFacing(): Int
}
