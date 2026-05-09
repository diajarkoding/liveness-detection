import Foundation
import Flutter
import AVFoundation

/// Flutter plugin for Liveness Detection on iOS.
/// Matches Android LivenessPlugin functionality.
class LivenessPlugin: NSObject, FlutterPlugin {
    
    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private var eventSink: FlutterEventSink?
    
    private var textureRegistry: FlutterTextureRegistry?
    private var textureId: Int64 = -1
    
    // Pipeline
    private var pipeline: LivenessPipeline?
    
    // Components (for pipeline creation)
    private var faceDetector: FaceDetectorProtocol?
    private var landmarkExtractor: LandmarkExtractorProtocol?
    private var screenManager: ScreenManagerProtocol?
    
    // Camera
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoQueue = DispatchQueue(label: "com.diajarkoding.livenessdetection.videoQueue")
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: "com.diajarkoding.livenessdetection/method",
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: "com.diajarkoding.livenessdetection/events",
            binaryMessenger: registrar.messenger()
        )
        
        let instance = LivenessPlugin(
            methodChannel: methodChannel,
            eventChannel: eventChannel,
            textureRegistry: registrar.textures()
        )
        
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
    }
    
    init(methodChannel: FlutterMethodChannel, eventChannel: FlutterEventChannel, textureRegistry: FlutterTextureRegistry?) {
        self.methodChannel = methodChannel
        self.eventChannel = eventChannel
        self.textureRegistry = textureRegistry
        super.init()
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            initialize(result: result)
        case "startCamera":
            startCamera(result: result)
        case "stopCamera":
            stopCamera(result: result)
        case "startVerification":
            startVerification(result: result)
        case "reset":
            reset(result: result)
        case "dispose":
            dispose(result: result)
        case "warmUp":
            warmUp(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    /// Initialize vision components without starting camera.
    /// Called during instruction screen for warm-up.
    /// If already initialized, just reset the pipeline state.
    private func initialize(result: @escaping FlutterResult) {
        // If pipeline already exists, just reset it and return success
        if let existingPipeline = pipeline {
            print("[LivenessPlugin] Pipeline already exists, resetting instead of re-initializing")
            existingPipeline.reset()
            result(["success": true])
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Create components
            self.faceDetector = MLKitFaceDetector()
            self.landmarkExtractor = MediaPipeLandmarker()
            self.screenManager = IOSScreenManager()
            
            // Create pipeline
            self.pipeline = LivenessPipeline(
                faceDetector: self.faceDetector!,
                landmarkExtractor: self.landmarkExtractor!,
                screenManager: self.screenManager!
            )
            
            // Set up state change callback
            self.pipeline?.onStateChanged = { [weak self] state in
                self?.sendStateUpdate(state)
            }
            
            // Initialize pipeline (includes warm-up)
            self.pipeline?.initialize { success in
                DispatchQueue.main.async {
                    if success {
                        result(["success": true])
                        print("[LivenessPlugin] Initialization complete")
                    } else {
                        result(FlutterError(code: "INIT_ERROR", message: "Failed to initialize pipeline", details: nil))
                    }
                }
            }
        }
    }
    
    /// Warm up MediaPipe engine before camera starts.
    private func warmUp(result: @escaping FlutterResult) {
        landmarkExtractor?.warmUp {
            result(["success": true])
        }
    }
    
    /// Start AVCaptureSession for camera preview.
    private func startCamera(result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let session = AVCaptureSession()
            session.sessionPreset = .photo
            
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                result(FlutterError(code: "CAMERA_ERROR", message: "Could not access camera", details: nil))
                return
            }
            
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.setSampleBufferDelegate(self, queue: self.videoQueue)
            
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            self.captureSession = session
            self.videoOutput = output
            
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
            
            // Start gating phase now that camera is ready
            self.pipeline?.startGating()
            
            // For now, return a placeholder texture ID
            // In production, you'd use FlutterTexture for zero-copy rendering
            result([
                "textureId": 0,
                "width": 480,
                "height": 640
            ])
            
            print("[LivenessPlugin] Camera started")
        }
    }
    
    /// Stop camera and release resources.
    private func stopCamera(result: @escaping FlutterResult) {
        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
        result(nil)
        print("[LivenessPlugin] Camera stopped")
    }
    
    /// Start verification process.
    private func startVerification(result: @escaping FlutterResult) {
        pipeline?.reset()
        result(nil)
        print("[LivenessPlugin] Verification started")
    }
    
    /// Reset pipeline state.
    private func reset(result: @escaping FlutterResult) {
        pipeline?.reset()
        result(nil)
        print("[LivenessPlugin] Pipeline reset")
    }
    
    /// Dispose all resources.
    private func dispose(result: @escaping FlutterResult) {
        captureSession?.stopRunning()
        captureSession = nil
        videoOutput = nil
        
        pipeline?.dispose()
        pipeline = nil
        
        faceDetector = nil
        landmarkExtractor = nil
        screenManager = nil
        
        result(nil)
        print("[LivenessPlugin] Plugin disposed")
    }
    
    /// Send state update to Flutter via EventChannel.
    private func sendStateUpdate(_ state: LivenessState) {
        var data: [String: Any]
        
        switch state {
        case .idle:
            data = ["state": "idle"]
            
        case .initializing:
            data = ["state": "initializing"]
            
        case .gating(let message):
            data = [
                "state": "gating",
                "message": message
            ]
            
        case .gatingFailed(let reason, let message):
            data = [
                "state": "gating_failed",
                "reason": reason.rawValue,
                "message": message
            ]
            
        case .challenge(let type, let progress, let instruction):
            data = [
                "state": "challenge",
                "type": type.rawValue,
                "progress": progress,
                "instruction": instruction
            ]
            
        case .processing(let message):
            data = [
                "state": "processing",
                "message": message
            ]
            
        case .success(let completedChallenges):
            data = [
                "state": "success",
                "challenges": completedChallenges.map { $0.rawValue }
            ]
            
        case .failed(let reason, let canRetry):
            data = [
                "state": "failed",
                "reason": reason,
                "canRetry": canRetry
            ]
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(data)
        }
    }
}

// MARK: - FlutterStreamHandler
extension LivenessPlugin: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        print("[LivenessPlugin] Event channel listening")
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        print("[LivenessPlugin] Event channel cancelled")
        return nil
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension LivenessPlugin: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Process frame through the pipeline
        pipeline?.processFrame(sampleBuffer: sampleBuffer)
    }
}
