# Liveness Detection - Panduan Integrasi

## Mulai Cepat

### 1. Tambahkan ke Proyek Flutter Anda

```yaml
# pubspec.yaml
dependencies:
  liveness_detection:
    path: ../liveness_detection  # atau URL git
```

### 2. Minta Izin Kamera

```dart
import 'package:permission_handler/permission_handler.dart';

Future<bool> mintaIzinKamera() async {
  final status = await Permission.camera.request();
  return status.isGranted;
}
```

### 3. Navigasi ke Verifikasi Liveness

```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:liveness_detection/features/liveness/liveness.dart';

void mulaiVerifikasiLiveness(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => BlocProvider(
        create: (_) => LivenessBloc(),
        child: const InstructionScreen(),
      ),
    ),
  );
}
```

### 4. Tangani Hasil

Hasil verifikasi ditangani secara internal oleh SDK. Setelah selesai, pengguna dinavigasi ke `ResultScreen` yang menampilkan sukses/gagal.

Untuk mendapatkan hasil secara programatis:

```dart
// Di layar Anda yang meluncurkan verifikasi
void mulaiVerifikasi() async {
  final result = await Navigator.of(context).push<LivenessResult>(
    MaterialPageRoute(
      builder: (_) => BlocProvider(
        create: (_) => LivenessBloc(),
        child: const InstructionScreen(),
      ),
    ),
  );

  if (result != null) {
    if (result.isSuccess) {
      print('Verifikasi berhasil!');
      print('Tantangan selesai: ${result.completedChallenges}');
    } else {
      print('Verifikasi gagal: ${result.failureReason}');
    }
  }
}
```

---

## Integrasi Kustom

### Menggunakan LivenessChannel Langsung

Untuk kontrol lebih, Anda dapat menggunakan `LivenessChannel` langsung:

```dart
import 'package:liveness_detection/features/liveness/data/liveness_channel.dart';

class MyLivenessController {
  final _channel = LivenessChannel();

  Future<void> initialize() async {
    // Dengarkan perubahan state
    _channel.stateStream.listen((state) {
      switch (state) {
        case IdleChannelState():
          print('Diam');
        case GatingChannelState(message: final msg):
          print('Gating: $msg');
        case ChallengeChannelState(type: final t, progress: final p):
          print('Tantangan: $t pada ${(p * 100).toInt()}%');
        case SuccessChannelState(challenges: final c):
          print('Berhasil! Selesai: $c');
          _tanganiSukses(c);
        case FailedChannelState(reason: final r):
          print('Gagal: $r');
        default:
          break;
      }
    });

    // Inisialisasi model ML
    await _channel.initialize();
    await _channel.warmUp();
    _channel.startListening();
  }

  Future<CameraConfig> mulaiKamera() async {
    return await _channel.startCamera();
  }

  Future<void> mulaiVerifikasi() async {
    await _channel.startVerification();
  }

  Future<void> dispose() async {
    await _channel.stopCamera();
    await _channel.dispose();
  }

  void _tanganiSukses(Set<ChallengeType> challenges) {
    // Tangani verifikasi berhasil
  }
}
```

### Membangun UI Kamera Kustom

```dart
import 'package:flutter/material.dart';

class CustomCameraScreen extends StatefulWidget {
  final int textureId;
  final int width;
  final int height;

  const CustomCameraScreen({
    required this.textureId,
    required this.width,
    required this.height,
  });

  @override
  State<CustomCameraScreen> createState() => _CustomCameraScreenState();
}

class _CustomCameraScreenState extends State<CustomCameraScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Preview kamera
          Center(
            child: AspectRatio(
              aspectRatio: widget.width / widget.height,
              child: Texture(textureId: widget.textureId),
            ),
          ),
          
          // Overlay kustom Anda
          Positioned.fill(
            child: CustomPaint(
              painter: FaceOvalPainter(),
            ),
          ),
          
          // Instruksi tantangan
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Text(
              'Ikuti instruksi',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## Integrasi BLoC

### Mendengarkan State Verifikasi

```dart
BlocListener<LivenessBloc, LivenessState>(
  listener: (context, state) {
    if (state is LivenessSuccess) {
      // Verifikasi berhasil
      final result = state.result;
      Navigator.of(context).pop(result);
    } else if (state is LivenessFailed) {
      // Verifikasi gagal
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.reason)),
      );
    }
  },
  child: WidgetAnda(),
)
```

### Membangun UI Berdasarkan State

```dart
BlocBuilder<LivenessBloc, LivenessState>(
  builder: (context, state) {
    return switch (state) {
      LivenessInitial() => LoadingWidget(),
      LivenessInitializing() => LoadingWidget(message: 'Menginisialisasi...'),
      LivenessReady() => TombolMulai(),
      LivenessGating(:final message) => GatingOverlay(message: message),
      LivenessChallengeActive(:final type, :final progress) => 
        ChallengeWidget(type: type, progress: progress),
      LivenessProcessing() => ProcessingWidget(),
      LivenessSuccess(:final result) => SuccessWidget(result: result),
      LivenessFailed(:final reason) => FailedWidget(reason: reason),
      _ => Container(),
    };
  },
)
```

---

## Integrasi Android

### Menambahkan Model MediaPipe

1. Unduh `face_landmarker.task` dari MediaPipe
2. Letakkan di `android/app/src/main/assets/`
3. Pastikan disertakan dalam build:

```groovy
// android/app/build.gradle
android {
    aaptOptions {
        noCompress "task"
    }
}
```

### Aturan Proguard

```proguard
# ML Kit
-keep class com.google.mlkit.** { *; }

# MediaPipe
-keep class com.google.mediapipe.** { *; }
```

---

## Integrasi iOS

### Menambahkan Model MediaPipe

1. Unduh `face_landmarker.task` dari MediaPipe
2. Tambahkan ke proyek Xcode:
   - Seret file ke folder Runner di Xcode
   - Pastikan "Copy items if needed" dicentang
   - Tambahkan ke target Runner

### Info.plist

```xml
<key>NSCameraUsageDescription</key>
<string>Akses kamera diperlukan untuk verifikasi wajah</string>
```

### Podfile

```ruby
platform :ios, '12.0'

target 'Runner' do
  # MediaPipe
  pod 'MediaPipeTasksVision'
  
  # ML Kit
  pod 'GoogleMLKit/FaceDetection'
end
```

---

## Kustomisasi

### Mengubah Urutan Tantangan

Modifikasi `ChallengeEngine` di kode native:

```kotlin
// Android: ChallengeEngine.kt
private val challengeSequence = listOf(
    ChallengeType.BLINK,        // Urutan diubah
    ChallengeType.TURN_LEFT,
    ChallengeType.TURN_RIGHT,
)
```

```swift
// iOS: ChallengeEngine.swift
private let challengeSequence: [ChallengeType] = [
    .blink,
    .turnLeft,
    .turnRight,
]
```

### Menyesuaikan Threshold

```kotlin
// Android: ChallengeEngine.kt
companion object {
    private const val BLINK_CLOSED_THRESHOLD = 0.5f  // Lebih ketat
    private const val TURN_MIN_ANGLE = 25f           // Tengok lebih lebar
    private const val CHALLENGE_TIMEOUT_MS = 20_000L // Timeout lebih lama
}
```

### Lokalisasi

Instruksi tantangan didefinisikan di kode native. Untuk mengubah bahasa:

```kotlin
// Android: LivenessPipeline.kt
private fun getChallengeInstruction(type: ChallengeType): String {
    return when (type) {
        ChallengeType.BLINK -> "Kedipkan mata Anda 2 kali"  // Indonesia
        ChallengeType.TURN_LEFT -> "Hadap lurus, lalu palingkan ke KIRI"
        ChallengeType.TURN_RIGHT -> "Hadap lurus, lalu palingkan ke KANAN"
        ChallengeType.SMILE -> "Tersenyum"
    }
}
```

---

## Pemecahan Masalah

### Masalah Umum

#### 1. Kamera tidak mau menyala

- Periksa izin kamera sudah diberikan
- Pastikan tidak ada aplikasi lain yang menggunakan kamera
- Coba restart aplikasi

#### 2. Inisialisasi ML Kit gagal

- Periksa koneksi internet (unduhan pertama memerlukan model)
- Pastikan Google Play Services sudah diperbarui (Android)

#### 3. Model MediaPipe tidak ditemukan

- Verifikasi `face_landmarker.task` ada di folder assets
- Periksa file tidak dikompresi di APK (noCompress)

#### 4. Tantangan tidak selesai

- Pastikan pencahayaan baik
- Wajah harus terlihat jelas
- Ikuti instruksi dengan tepat (misal, mulai dari tengah untuk tengok)

#### 5. False positive anti-spoof

- Tingkatkan threshold `MAX_RATIO_VARIANCE`
- Pastikan wajah bergerak selama verifikasi
- Periksa permukaan reflektif

### Logging Debug

Aktifkan logging verbose:

```kotlin
// Android
Log.d("LivenessPipeline", "State saat ini: $state")
```

```swift
// iOS
print("[LivenessPipeline] State saat ini: \(state)")
```

### Profiling Performa

Pantau tingkat pemrosesan frame:

```kotlin
// Android: LivenessPipeline.kt
private var frameCount = 0
private var lastLogTime = 0L

fun processFrame(imageProxy: ImageProxy) {
    frameCount++
    val now = System.currentTimeMillis()
    if (now - lastLogTime > 1000) {
        Log.d(TAG, "FPS: $frameCount")
        frameCount = 0
        lastLogTime = now
    }
    // ...
}
```

---

## Praktik Terbaik

1. **Inisialisasi Lebih Awal**: Panggil `warmUp()` selama layar instruksi untuk memuat MediaPipe terlebih dahulu
2. **Tangani Error dengan Baik**: Selalu sediakan opsi coba lagi untuk kegagalan
3. **Pandu Pengguna**: Tampilkan instruksi yang jelas untuk setiap tantangan
4. **Pencahayaan Baik**: Rekomendasikan lingkungan dengan cahaya baik
5. **Tes di Perangkat Asli**: Emulator tidak memiliki dukungan kamera/ML yang tepat
6. **Pertimbangkan Baterai**: Throttling frame sudah diimplementasikan (~15 FPS)
7. **Manajemen Memori**: Buang resource saat keluar layar
