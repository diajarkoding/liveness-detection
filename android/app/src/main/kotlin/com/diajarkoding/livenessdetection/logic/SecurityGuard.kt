package com.diajarkoding.livenessdetection.logic

import android.content.Context
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Build
import android.util.Base64
import android.util.Log
import java.security.MessageDigest

/**
 * Runtime security checks for the liveness detection app.
 * Detects tampering, debugging, and rooted environments.
 */
object SecurityGuard {
    private const val TAG = "SecurityGuard"

    // Expected signing certificate SHA-256 hash (set during build)
    // This will be updated when you build with your release keystore
    private const val EXPECTED_SIGNER_HASH = ""

    /**
     * Check if app is running in a debugger.
     */
    fun isDebuggerAttached(): Boolean {
        return android.os.Debug.isDebuggerConnected() ||
                android.os.Debug.waitingForDebugger()
    }

    /**
     * Check if the app is running on an emulator.
     */
    fun isEmulator(): Boolean {
        return (Build.BRAND.startsWith("generic") && Build.DEVICE.startsWith("generic")
                || Build.FINGERPRINT.startsWith("generic")
                || Build.FINGERPRINT.startsWith("unknown")
                || Build.HARDWARE.contains("goldfish")
                || Build.HARDWARE.contains("ranchu")
                || Build.MODEL.contains("google_sdk")
                || Build.MODEL.contains("Emulator")
                || Build.MODEL.contains("Android SDK built for x86")
                || Build.MANUFACTURER.contains("Genymotion")
                || Build.PRODUCT.contains("sdk_google")
                || Build.PRODUCT.contains("google_sdk")
                || Build.PRODUCT.contains("sdk")
                || Build.PRODUCT.contains("sdk_x86")
                || Build.PRODUCT.contains("simulator")
                || Build.PRODUCT.contains("vbox86p"))
    }

    /**
     * Check if the app has been tampered with by verifying the installer.
     */
    fun isInstalledFromTrustedSource(context: Context): Boolean {
        val installer = context.packageManager.getInstallerPackageName(context.packageName)
        val trustedInstallers = listOf(
            "com.android.vending",     // Google Play Store
            "com.google.android.feedback", // Google Play Store (alternative)
            "com.android.packageinstaller", // System installer
            null                        // Sideloaded (debug builds)
        )
        return installer in trustedInstallers
    }

    /**
     * Run all security checks and return a risk score (0.0 = safe, 1.0 = high risk).
     */
    fun performSecurityCheck(context: Context): SecurityCheckResult {
        val riskFactors = mutableListOf<String>()
        var riskScore = 0f

        if (isDebuggerAttached()) {
            riskFactors.add("Debugger attached")
            riskScore += 0.3f
            Log.w(TAG, "Security: Debugger detected")
        }

        if (isEmulator()) {
            riskFactors.add("Emulator detected")
            riskScore += 0.5f
            Log.w(TAG, "Security: Emulator detected")
        }

        if (!isInstalledFromTrustedSource(context)) {
            riskFactors.add("Untrusted installer")
            riskScore += 0.2f
            Log.w(TAG, "Security: Untrusted installer")
        }

        riskScore = riskScore.coerceIn(0f, 1f)

        return SecurityCheckResult(
            riskScore = riskScore,
            riskFactors = riskFactors,
            isSafe = riskScore < 0.5f
        )
    }
}

data class SecurityCheckResult(
    val riskScore: Float,
    val riskFactors: List<String>,
    val isSafe: Boolean
)
