# Liveness Detection

A Flutter-based liveness detection SDK with on-device ML processing for Android and iOS. Provides real-time face verification with anti-spoofing protection.

## Features

- **Offline & On-device Processing**: All ML inference runs locally, no server required
- **Cross-platform**: Native implementations for both Android (Kotlin) and iOS (Swift)
- **Anti-spoofing Protection**: Geometric consistency checks to detect photo/video attacks
- **Sequential Challenges**: Turn right → Turn left → Blink (2x)
- **Real-time Analysis**: ~15 FPS processing with frame throttling
- **Responsive UI**: Adapts to all mobile screen sizes

## Tech Stack

| Component | Android | iOS |
|-----------|---------|-----|
| Face Detection (Gating) | ML Kit Face Detection | Google ML Kit |
| Landmark Extraction | MediaPipe Face Landmarker | MediaPipe Face Landmarker |
| State Management | Kotlin Flow | Callbacks |
| Camera | CameraX | AVFoundation |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter UI Layer                          │
│  (HomeScreen → InstructionScreen → CameraScreen → Result)   │
├─────────────────────────────────────────────────────────────┤
│                    BLoC State Management                     │
│              (LivenessBloc + LivenessChannel)               │
├─────────────────────────────────────────────────────────────┤
│               Platform Channel (Method + Event)              │
├──────────────────────────┬──────────────────────────────────┤
│      Android Native      │         iOS Native               │
│                          │                                  │
│  ┌────────────────────┐  │  ┌────────────────────┐         │
│  │  LivenessPipeline  │  │  │  LivenessPipeline  │         │
│  └────────────────────┘  │  └────────────────────┘         │
│           │              │           │                      │
│  ┌────────┴────────┐     │  ┌────────┴────────┐            │
│  │                 │     │  │                 │            │
│  ▼                 ▼     │  ▼                 ▼            │
│ MLKit           MediaPipe│ MLKit           MediaPipe       │
│ (Gating)      (Analysis) │ (Gating)      (Analysis)        │
│                          │                                  │
│  ┌─────────────────────┐ │  ┌─────────────────────┐        │
│  │  ChallengeEngine    │ │  │  ChallengeEngine    │        │
│  │  AntiSpoofGuard     │ │  │  AntiSpoofGuard     │        │
│  └─────────────────────┘ │  └─────────────────────┘        │
└──────────────────────────┴──────────────────────────────────┘
```

## Pipeline Flow

1. **Initialization**: Load ML Kit and MediaPipe models
2. **Gating Phase**: Fast face detection with ML Kit
   - Single face required
   - Face size, position, and tilt validation
   - Accessory detection (glasses, mask)
3. **Challenge Phase**: Sequential challenges with MediaPipe
   - Turn Right (yaw > 20°)
   - Turn Left (yaw < -20°)
   - Blink 2 times (using blendshapes)
4. **Anti-spoof Check**: Geometric consistency analysis
5. **Result**: Success or failure with retry option

## Project Structure

```
lib/
├── main.dart                    # App entry point, HomeScreen
├── core/
│   └── utils/
│       ├── responsive.dart      # Responsive sizing utility
│       └── error_handler.dart   # Error handling
└── features/
    └── liveness/
        ├── data/
        │   ├── liveness_channel.dart    # Platform channel
        │   └── brightness_service.dart  # Screen brightness
        ├── domain/
        │   └── entities/
        │       ├── challenge_type.dart  # Challenge enum
        │       └── liveness_result.dart # Result model
        └── presentation/
            ├── bloc/                    # BLoC state management
            ├── screens/                 # UI screens
            └── widgets/                 # Reusable widgets

android/app/src/main/kotlin/com/example/liveness_detection/
├── bridge/
│   └── LivenessPlugin.kt        # Flutter plugin bridge
├── core/
│   ├── IFaceDetector.kt         # Face detector interface
│   ├── ILandmarkExtractor.kt    # Landmark extractor interface
│   └── IScreenManager.kt        # Screen manager interface
├── impl/
│   ├── mlkit/
│   │   └── MLKitFaceDetector.kt # ML Kit implementation
│   └── mediapipe/
│       └── MediaPipeLandmarker.kt # MediaPipe implementation
└── logic/
    ├── LivenessPipeline.kt      # Main pipeline coordinator
    ├── ChallengeEngine.kt       # Challenge processing
    └── AntiSpoofGuard.kt        # Anti-spoof checks

ios/Runner/
├── LivenessPlugin.swift         # Flutter plugin bridge
├── Protocols/
│   ├── FaceDetectorProtocol.swift
│   ├── LandmarkExtractorProtocol.swift
│   └── ScreenManagerProtocol.swift
├── Implementation/
│   ├── MLKitFaceDetector.swift
│   └── MediaPipeLandmarker.swift
└── Logic/
    ├── LivenessPipeline.swift
    ├── ChallengeEngine.swift
    └── AntiSpoofGuard.swift
```

## Getting Started

### Prerequisites

- Flutter SDK ^3.9.2
- Android Studio / Xcode
- Android minSdkVersion: 24
- iOS deployment target: 12.0

### Installation

1. Clone the repository
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the app:
   ```bash
   flutter run
   ```

### Android Setup

MediaPipe models are included in `android/app/src/main/assets/`:
- `face_landmarker.task`

### iOS Setup

MediaPipe models should be added to the Xcode project:
- Add `face_landmarker.task` to the Runner target

## Dependencies

```yaml
dependencies:
  flutter_bloc: ^9.0.0      # State management
  equatable: ^2.0.7         # Value equality
  permission_handler: ^11.3.1  # Camera permissions
  screen_brightness: ^1.0.1    # Brightness control
```

## Documentation

See the [docs](./docs) folder for detailed documentation:
- [Product Requirements Document](./docs/prd.md)
- [Architecture Overview](./docs/architecture.md)
- [API Reference](./docs/api-reference.md)

## License

Private - All rights reserved.
