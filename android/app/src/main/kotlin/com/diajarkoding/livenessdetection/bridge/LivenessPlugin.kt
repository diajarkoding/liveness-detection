package com.diajarkoding.livenessdetection.bridge

import android.app.Activity
import android.content.Context
import android.util.Log
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.diajarkoding.livenessdetection.core.*
import com.diajarkoding.livenessdetection.impl.AndroidScreenManager
import com.diajarkoding.livenessdetection.impl.mediapipe.MediaPipeLandmarker
import com.diajarkoding.livenessdetection.impl.mlkit.MLKitFaceDetector
import com.diajarkoding.livenessdetection.logic.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collectLatest
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Flutter plugin for Liveness Detection.
 * Bridges Flutter UI with native vision pipeline.
 */
class LivenessPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, 
    ActivityAware, EventChannel.StreamHandler {
    
    companion object {
        private const val TAG = "LivenessPlugin"
        private const val METHOD_CHANNEL = "com.diajarkoding.livenessdetection/method"
        private const val EVENT_CHANNEL = "com.diajarkoding.livenessdetection/events"
    }
    
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    
    private var context: Context? = null
    private var activity: Activity? = null
    private var textureRegistry: TextureRegistry? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    
    private var cameraProvider: ProcessCameraProvider? = null
    private var cameraExecutor: ExecutorService? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var preview: Preview? = null
    
    private var pipeline: LivenessPipeline? = null
    private var scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var stateCollectorJob: Job? = null
    
    // Components
    private var faceDetector: IFaceDetector? = null
    private var landmarkExtractor: ILandmarkExtractor? = null
    private var screenManager: IScreenManager? = null
    
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        textureRegistry = binding.textureRegistry
        
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
        
        cameraExecutor = Executors.newSingleThreadExecutor()
        
        Log.d(TAG, "Plugin attached to engine")
    }
    
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        dispose()
        Log.d(TAG, "Plugin detached from engine")
    }
    
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        Log.d(TAG, "Plugin attached to activity")
    }
    
    override fun onDetachedFromActivity() {
        activity = null
        Log.d(TAG, "Plugin detached from activity")
    }
    
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }
    
    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }
    
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        Log.d(TAG, "Event channel listening")
        
        // Start collecting state updates
        pipeline?.let { p ->
            scope.launch {
                p.state.collectLatest { state ->
                    sendStateUpdate(state)
                }
            }
        }
    }
    
    override fun onCancel(arguments: Any?) {
        eventSink = null
        Log.d(TAG, "Event channel cancelled")
    }
    
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(result)
            "startCamera" -> startCamera(result)
            "stopCamera" -> stopCamera(result)
            "startVerification" -> startVerification(result)
            "reset" -> reset(result)
            "dispose" -> {
                dispose()
                result.success(null)
            }
            "warmUp" -> warmUp(result)
            else -> result.notImplemented()
        }
    }
    
    /**
     * Initialize vision components without starting camera.
     * Called during instruction screen for warm-up.
     * If already initialized, just reset the pipeline state.
     */
    private fun initialize(result: MethodChannel.Result) {
        val ctx = context ?: run {
            result.error("NO_CONTEXT", "Context not available", null)
            return
        }
        
        val act = activity ?: run {
            result.error("NO_ACTIVITY", "Activity not available", null)
            return
        }
        
        // Ensure scope is active (recreate if cancelled)
        if (!scope.isActive) {
            Log.d(TAG, "Recreating cancelled scope")
            scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
        }
        
        // If pipeline already exists, just reset it and return success
        pipeline?.let { existingPipeline ->
            Log.d(TAG, "Pipeline already exists, resetting instead of re-initializing")
            existingPipeline.reset()
            result.success(mapOf("success" to true))
            return
        }
        
        scope.launch {
            try {
                // Create components
                faceDetector = MLKitFaceDetector()
                landmarkExtractor = MediaPipeLandmarker(ctx)
                screenManager = AndroidScreenManager(act)
                
                // Run security checks
                val securityResult = SecurityGuard.performSecurityCheck(ctx)
                Log.d(TAG, "Security check: safe=${securityResult.isSafe}, score=${securityResult.riskScore}, factors=${securityResult.riskFactors}")
                
                // Create pipeline
                pipeline = LivenessPipeline(
                    faceDetector!!,                    
                    landmarkExtractor!!,
                    screenManager!!,
                    securityResult
                )
                
                // Initialize pipeline (includes warm-up)
                pipeline?.initialize()
                
                // Cancel previous state collector if exists
                stateCollectorJob?.cancel()
                
                // Start collecting state updates
                stateCollectorJob = pipeline?.let { p ->
                    scope.launch {
                        p.state.collectLatest { state ->
                            sendStateUpdate(state)
                        }
                    }
                }
                
                result.success(mapOf("success" to true))
                Log.d(TAG, "Initialization complete")
            } catch (e: Exception) {
                Log.e(TAG, "Initialization failed", e)
                result.error("INIT_ERROR", e.message, null)
            }
        }
    }
    
    /**
     * Warm up MediaPipe engine before camera starts.
     */
    private fun warmUp(result: MethodChannel.Result) {
        scope.launch {
            try {
                landmarkExtractor?.warmUp()
                result.success(mapOf("success" to true))
            } catch (e: Exception) {
                result.error("WARMUP_ERROR", e.message, null)
            }
        }
    }
    
    /**
     * Start CameraX with SurfaceTexture for Flutter rendering.
     */
    @androidx.camera.core.ExperimentalGetImage
    private fun startCamera(result: MethodChannel.Result) {
        val ctx = context ?: run {
            result.error("NO_CONTEXT", "Context not available", null)
            return
        }
        
        val act = activity as? LifecycleOwner ?: run {
            result.error("NO_LIFECYCLE", "Activity must be LifecycleOwner", null)
            return
        }
        
        // Ensure camera executor exists
        if (cameraExecutor == null || cameraExecutor!!.isShutdown) {
            cameraExecutor = Executors.newSingleThreadExecutor()
        }
        
        val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
        
        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()
                
                // Create texture for Flutter
                textureEntry = textureRegistry?.createSurfaceTexture()
                val surfaceTexture = textureEntry?.surfaceTexture()
                
                if (surfaceTexture == null) {
                    result.error("TEXTURE_ERROR", "Failed to create surface texture", null)
                    return@addListener
                }
                
                // Configure preview with 4:3 ratio
                preview = Preview.Builder()
                    .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                    .build()
                
                preview?.setSurfaceProvider { request ->
                    surfaceTexture.setDefaultBufferSize(
                        request.resolution.width,
                        request.resolution.height
                    )
                    request.provideSurface(
                        android.view.Surface(surfaceTexture),
                        cameraExecutor!!
                    ) { }
                }
                
                // Configure image analysis with target rotation
                val displayRotation = activity?.windowManager?.defaultDisplay?.rotation ?: android.view.Surface.ROTATION_0
                imageAnalysis = ImageAnalysis.Builder()
                    .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setTargetRotation(displayRotation)
                    .build()
                
                imageAnalysis?.setAnalyzer(cameraExecutor!!) { imageProxy ->
                    pipeline?.processFrame(imageProxy)
                }
                
                // Use front camera
                val cameraSelector = CameraSelector.Builder()
                    .requireLensFacing(CameraSelector.LENS_FACING_FRONT)
                    .build()
                
                // Bind use cases
                cameraProvider?.unbindAll()
                cameraProvider?.bindToLifecycle(
                    act,
                    cameraSelector,
                    preview,
                    imageAnalysis
                )
                
                val textureId = textureEntry?.id() ?: -1L
                
                // Start gating phase now that camera is ready
                pipeline?.startGating()
                
                result.success(mapOf(
                    "textureId" to textureId,
                    "width" to 480,
                    "height" to 640
                ))
                
                Log.d(TAG, "Camera started with texture ID: $textureId")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start camera", e)
                result.error("CAMERA_ERROR", e.message, null)
            }
        }, ContextCompat.getMainExecutor(ctx))
    }
    
    /**
     * Stop camera and release resources.
     */
    private fun stopCamera(result: MethodChannel.Result) {
        cameraProvider?.unbindAll()
        textureEntry?.release()
        textureEntry = null
        result.success(null)
        Log.d(TAG, "Camera stopped")
    }
    
    /**
     * Start verification process.
     */
    private fun startVerification(result: MethodChannel.Result) {
        pipeline?.reset()
        result.success(null)
        Log.d(TAG, "Verification started")
    }
    
    /**
     * Reset pipeline state.
     */
    private fun reset(result: MethodChannel.Result) {
        pipeline?.reset()
        result.success(null)
        Log.d(TAG, "Pipeline reset")
    }
    
    /**
     * Dispose all resources.
     */
    private fun dispose() {
        // Cancel state collector first
        stateCollectorJob?.cancel()
        stateCollectorJob = null
        
        // Cancel scope
        scope.cancel()
        
        cameraProvider?.unbindAll()
        cameraProvider = null
        
        textureEntry?.release()
        textureEntry = null
        
        cameraExecutor?.shutdown()
        cameraExecutor = null
        
        pipeline?.dispose()
        pipeline = null
        
        faceDetector = null
        landmarkExtractor = null
        screenManager = null
        
        Log.d(TAG, "Plugin disposed")
    }
    
    /**
     * Send state update to Flutter via EventChannel.
     */
    private fun sendStateUpdate(state: LivenessState) {
        val data = when (state) {
            is LivenessState.Idle -> mapOf(
                "state" to "idle"
            )
            is LivenessState.Initializing -> mapOf(
                "state" to "initializing"
            )
            is LivenessState.Gating -> mapOf(
                "state" to "gating",
                "message" to state.message
            )
            is LivenessState.GatingFailed -> mapOf(
                "state" to "gating_failed",
                "reason" to state.reason.name,
                "message" to state.message
            )
            is LivenessState.Challenge -> mapOf(
                "state" to "challenge",
                "type" to state.type.name,
                "progress" to state.progress,
                "instruction" to state.instruction
            )
            is LivenessState.Processing -> mapOf(
                "state" to "processing",
                "message" to state.message
            )
            is LivenessState.Success -> mapOf(
                "state" to "success",
                "challenges" to state.completedChallenges.map { it.name }
            )
            is LivenessState.Failed -> mapOf(
                "state" to "failed",
                "reason" to state.reason,
                "canRetry" to state.canRetry
            )
        }
        
        activity?.runOnUiThread {
            eventSink?.success(data)
        }
    }
}
