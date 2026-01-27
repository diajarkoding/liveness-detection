# Liveness Detection - Referensi API

## API Flutter

### LivenessChannel

Layanan untuk berkomunikasi dengan pipeline deteksi liveness native.

```dart
import 'package:liveness_detection/features/liveness/data/liveness_channel.dart';

class LivenessChannel {
  /// Stream state liveness dari native
  Stream<LivenessChannelState> get stateStream;

  /// Inisialisasi komponen deteksi liveness
  /// Mengembalikan true jika berhasil
  Future<bool> initialize();

  /// Pemanasan engine MediaPipe (panggil saat layar instruksi)
  /// Mengembalikan true jika berhasil
  Future<bool> warmUp();

  /// Mulai kamera dan dapatkan texture ID untuk rendering Flutter
  /// Mengembalikan CameraConfig dengan textureId, width, height
  Future<CameraConfig> startCamera();

  /// Hentikan kamera
  Future<void> stopCamera();

  /// Mulai mendengarkan event state native
  void startListening();

  /// Berhenti mendengarkan event
  void stopListening();

  /// Mulai proses verifikasi
  Future<void> startVerification();

  /// Reset state pipeline
  Future<void> reset();

  /// Buang semua resource
  Future<void> dispose();
}
```

### CameraConfig

```dart
class CameraConfig {
  final int textureId;   // ID texture Flutter untuk preview kamera
  final int width;       // Lebar frame kamera
  final int height;      // Tinggi frame kamera
}
```

### LivenessChannelState

Sealed class yang merepresentasikan state dari pipeline native.

```dart
sealed class LivenessChannelState {
  const LivenessChannelState();

  // State yang tersedia:
  const factory LivenessChannelState.idle();
  const factory LivenessChannelState.initializing();
  const factory LivenessChannelState.gating({required String message});
  const factory LivenessChannelState.gatingFailed({
    required String reason,
    required String message,
  });
  const factory LivenessChannelState.challenge({
    ChallengeType? type,
    required double progress,
    required String instruction,
  });
  const factory LivenessChannelState.processing({required String message});
  const factory LivenessChannelState.success({
    required Set<ChallengeType> challenges,
  });
  const factory LivenessChannelState.failed({
    required String reason,
    required bool canRetry,
  });
}
```

### ChallengeType

```dart
enum ChallengeType {
  blink,
  turnLeft,
  turnRight,
  smile;

  /// Dapatkan tantangan dari nama string
  static ChallengeType? fromString(String name);

  /// Dapatkan nama tampilan untuk UI (Indonesia)
  String get displayName;
  // blink → 'Kedipkan Mata'
  // turnLeft → 'Tengok Kiri'
  // turnRight → 'Tengok Kanan'
  // smile → 'Senyum'

  /// Dapatkan teks instruksi (Indonesia)
  String get instruction;
  // blink → 'Kedipkan mata Anda 2 kali'
  // turnLeft → 'Hadap lurus, lalu palingkan ke KIRI'
  // turnRight → 'Hadap lurus, lalu palingkan ke KANAN'
  // smile → 'Tersenyum lebar'
}
```

### LivenessResult

```dart
class LivenessResult extends Equatable {
  /// Apakah verifikasi berhasil
  final bool isSuccess;

  /// Tantangan yang diselesaikan
  final Set<ChallengeType> completedChallenges;

  /// Alasan kegagalan jika tidak berhasil
  final String? failureReason;

  /// Apakah pengguna bisa coba lagi
  final bool canRetry;

  /// Timestamp hasil
  final DateTime timestamp;

  /// Buat hasil sukses
  factory LivenessResult.success(Set<ChallengeType> challenges);

  /// Buat hasil gagal
  factory LivenessResult.failure(String reason, {bool canRetry = true});
}
```

---

## API BLoC

### LivenessBloc

Manajemen state untuk alur verifikasi liveness.

```dart
class LivenessBloc extends Bloc<LivenessEvent, LivenessState> {
  LivenessBloc() : super(const LivenessInitial());
}
```

### Event

```dart
// Inisialisasi model ML
class InitializeLiveness extends LivenessEvent {
  const InitializeLiveness();
}

// Mulai kamera dan dapatkan texture
class StartCamera extends LivenessEvent {
  const StartCamera();
}

// Mulai verifikasi (fase gating)
class StartVerification extends LivenessEvent {
  const StartVerification();
}

// Hentikan kamera dan lepaskan resource
class StopCamera extends LivenessEvent {
  const StopCamera();
}

// Reset dan coba lagi verifikasi
class RetryVerification extends LivenessEvent {
  const RetryVerification();
}
```

### State

```dart
// State awal, belum diinisialisasi
class LivenessInitial extends LivenessState {}

// Model ML sedang dimuat
class LivenessInitializing extends LivenessState {}

// Siap memulai verifikasi
class LivenessReady extends LivenessState {
  final int? textureId;
  final int? previewWidth;
  final int? previewHeight;
}

// Fase gating - mendeteksi wajah
class LivenessGating extends LivenessState {
  final int textureId;
  final int previewWidth;
  final int previewHeight;
  final String message;
  final String? gatingReason;  // null = valid, jika tidak = alasan kegagalan
}

// Tantangan sedang berlangsung
class LivenessChallengeActive extends LivenessState {
  final int textureId;
  final int previewWidth;
  final int previewHeight;
  final ChallengeType type;
  final double progress;       // 0.0 - 1.0
  final String instruction;
  final int currentStep;       // berbasis 1
  final int totalSteps;
}

// Pemrosesan verifikasi akhir
class LivenessProcessing extends LivenessState {
  final int textureId;
  final int previewWidth;
  final int previewHeight;
  final String message;
}

// Verifikasi berhasil
class LivenessSuccess extends LivenessState {
  final LivenessResult result;
}

// Verifikasi gagal
class LivenessFailed extends LivenessState {
  final String reason;
  final bool canRetry;
}

// Terjadi error
class LivenessError extends LivenessState {
  final String message;
  final bool canRetry;
}
```

---

## API Native (Android - Kotlin)

### LivenessPipeline

Koordinator utama untuk deteksi liveness.

```kotlin
class LivenessPipeline(
    private val faceDetector: IFaceDetector,
    private val landmarkExtractor: ILandmarkExtractor,
    private val screenManager: IScreenManager
) {
    /// StateFlow dari state pipeline saat ini
    val state: StateFlow<LivenessState>

    /// Inisialisasi semua komponen
    suspend fun initialize()

    /// Proses frame kamera
    fun processFrame(imageProxy: ImageProxy)

    /// Mulai fase gating
    fun startGating()

    /// Reset pipeline
    fun reset()

    /// Buang resource
    fun dispose()
}
```

### LivenessState (Android)

```kotlin
sealed class LivenessState {
    data object Idle : LivenessState()
    data object Initializing : LivenessState()
    
    data class Gating(
        val message: String = "Posisikan wajah Anda dalam bingkai"
    ) : LivenessState()
    
    data class GatingFailed(
        val reason: GatingFailReason,
        val message: String
    ) : LivenessState()
    
    data class Challenge(
        val type: ChallengeType,
        val progress: Float = 0f,
        val instruction: String
    ) : LivenessState()
    
    data class Processing(
        val message: String = "Menganalisis..."
    ) : LivenessState()
    
    data class Success(
        val completedChallenges: Set<ChallengeType>
    ) : LivenessState()
    
    data class Failed(
        val reason: String,
        val canRetry: Boolean = true
    ) : LivenessState()
}
```

### GatingFailReason

```kotlin
enum class GatingFailReason {
    NO_FACE_DETECTED,      // Tidak ada wajah terdeteksi
    MULTIPLE_FACES,        // Banyak wajah
    FACE_TOO_SMALL,        // Wajah terlalu kecil
    FACE_NOT_CENTERED,     // Wajah tidak di tengah
    FACE_TILTED,           // Wajah miring
    EYES_NOT_VISIBLE,      // Mata tidak terlihat
    MOUTH_NOT_VISIBLE      // Mulut tidak terlihat
}
```

### ChallengeType (Android)

```kotlin
enum class ChallengeType {
    BLINK,        // Kedip
    TURN_LEFT,    // Tengok kiri
    TURN_RIGHT,   // Tengok kanan
    SMILE         // Senyum
}
```

### ChallengeEngine

```kotlin
class ChallengeEngine(
    private val landmarkExtractor: ILandmarkExtractor
) {
    /// Mulai tantangan baru
    fun startChallenge(type: ChallengeType)

    /// Proses frame untuk tantangan saat ini
    fun processFrame(
        landmarks: FaceLandmarks?,
        smilingProbability: Float? = null
    ): ChallengeState

    /// Dapatkan tantangan berikutnya dalam urutan
    fun getNextChallenge(): ChallengeType?

    /// Cek apakah semua tantangan yang diperlukan sudah selesai
    fun areRequiredChallengesComplete(): Boolean

    /// Dapatkan tantangan yang sudah diselesaikan
    fun getCompletedChallenges(): Set<ChallengeType>

    /// Reset semua state
    fun reset()
}
```

### ChallengeState

```kotlin
sealed class ChallengeState {
    data object Idle : ChallengeState()
    data class Active(val type: ChallengeType, val progress: Float = 0f) : ChallengeState()
    data class Completed(val type: ChallengeType) : ChallengeState()
    data class Failed(val type: ChallengeType, val reason: String) : ChallengeState()
}
```

### AntiSpoofGuard

```kotlin
class AntiSpoofGuard(
    private val landmarkExtractor: ILandmarkExtractor
) {
    /// Tambah pengukuran untuk analisis
    fun addMeasurement(boundingBox: RectF, landmarks: FaceLandmarks)

    /// Analisis pengukuran yang dikumpulkan
    fun analyze(): AntiSpoofResult

    /// Pengecekan cepat untuk spoof yang jelas
    fun quickSpoofCheck(landmarks: FaceLandmarks): Boolean

    /// Reset pengukuran
    fun reset()

    /// Dapatkan jumlah sampel saat ini
    fun getSampleCount(): Int
}
```

### AntiSpoofResult

```kotlin
sealed class AntiSpoofResult {
    data object Pass : AntiSpoofResult()                                    // Lolos
    data class Suspicious(val reason: String, val confidence: Float) : AntiSpoofResult()  // Mencurigakan
    data class Spoof(val reason: String) : AntiSpoofResult()               // Spoof terdeteksi
}
```

---

## API Native (iOS - Swift)

### LivenessPipeline

```swift
class LivenessPipeline {
    var state: LivenessState { get }
    var onStateChanged: ((LivenessState) -> Void)?

    init(faceDetector: FaceDetectorProtocol,
         landmarkExtractor: LandmarkExtractorProtocol,
         screenManager: ScreenManagerProtocol)

    func initialize(completion: @escaping (Bool) -> Void)
    func processFrame(sampleBuffer: CMSampleBuffer)
    func startGating()
    func reset()
    func dispose()
}
```

### LivenessState (iOS)

```swift
enum LivenessState {
    case idle
    case initializing
    case gating(message: String)
    case gatingFailed(reason: GatingFailReason, message: String)
    case challenge(type: ChallengeType, progress: Float, instruction: String)
    case processing(message: String)
    case success(completedChallenges: Set<ChallengeType>)
    case failed(reason: String, canRetry: Bool)
}
```

### ChallengeType (iOS)

```swift
enum ChallengeType: String, CaseIterable {
    case blink = "BLINK"
    case turnLeft = "TURN_LEFT"
    case turnRight = "TURN_RIGHT"
    case smile = "SMILE"
}
```

### Protokol

```swift
protocol FaceDetectorProtocol {
    func initialize()
    func detectFaces(sampleBuffer: CMSampleBuffer, 
                     completion: @escaping ([DetectedFace]) -> Void)
    func validateGating(face: DetectedFace, 
                       frameWidth: Int, 
                       frameHeight: Int) -> GatingResult
    func close()
}

protocol LandmarkExtractorProtocol {
    func initialize()
    func warmUp(completion: @escaping () -> Void)
    func extractLandmarks(sampleBuffer: CMSampleBuffer,
                         completion: @escaping (FaceLandmarks?) -> Void)
    func calculateHeadPose(_ landmarks: FaceLandmarks) -> HeadPose
    func calculateInterOcularDistance(_ landmarks: FaceLandmarks) -> Float
    func close()
}

protocol ScreenManagerProtocol {
    func setMaxBrightness()
    func restoreBrightness()
}
```

---

## Protokol Platform Channel

### Method Channel

Nama channel: `com.example.liveness_detection/method`

| Method | Parameter | Mengembalikan |
|--------|-----------|---------------|
| `initialize` | tidak ada | `{ success: bool }` |
| `warmUp` | tidak ada | `{ success: bool }` |
| `startCamera` | tidak ada | `{ textureId: int, width: int, height: int }` |
| `stopCamera` | tidak ada | tidak ada |
| `startVerification` | tidak ada | tidak ada |
| `reset` | tidak ada | tidak ada |
| `dispose` | tidak ada | tidak ada |

### Event Channel

Nama channel: `com.example.liveness_detection/events`

Format event:
```json
{
  "state": "string",
  "message": "string?",
  "reason": "string?",
  "type": "string?",
  "progress": "double?",
  "instruction": "string?",
  "challenges": "string[]?",
  "canRetry": "bool?"
}
```

Nilai state:
- `idle` - Diam
- `initializing` - Menginisialisasi
- `gating` - Fase gating
- `gating_failed` - Gating gagal
- `challenge` - Tantangan
- `processing` - Memproses
- `success` - Berhasil
- `failed` - Gagal

---

## Threshold & Konfigurasi

### Threshold Gating

| Pengecekan | Threshold | Deskripsi |
|------------|-----------|-----------|
| Ukuran wajah | > 15% dari frame | Wajah harus cukup besar |
| Pusat wajah | Dalam 30% dari tengah | Wajah harus di tengah |
| Kemiringan kepala | Roll < 25° | Kepala harus tegak |
| Mata terlihat | Probabilitas > 0.5 | Tidak memakai kacamata gelap |
| Mulut terlihat | Probabilitas > 0.5 | Tidak memakai masker |

### Threshold Tantangan

| Tantangan | Threshold | Deskripsi |
|-----------|-----------|-----------|
| Kedip tertutup | > 0.4 | Mata dianggap tertutup |
| Kedip terbuka | < 0.2 | Mata dianggap terbuka |
| Jumlah kedip | 2 | Jumlah kedip yang diperlukan |
| Sudut tengok | > 20° | Yaw minimum untuk menyelesaikan tengok |
| Tengok maksimum | 45° | Yaw maksimum (jaga wajah tetap terlihat) |
| Mulai dari tengah | < 12° | Harus mulai tengok dari tengah |
| Senyum | > 0.8 | Threshold probabilitas senyum |
| Timeout | 15 detik | Timeout per tantangan |

### Threshold Anti-Spoof

| Pengecekan | Threshold | Hasil |
|------------|-----------|-------|
| Sampel minimum | 10 | Frame minimum untuk analisis |
| Pergerakan | > 5% | Perubahan ukuran bbox minimum |
| Varian rasio | < 15% | Lolos |
| Varian rasio | 15-30% | Mencurigakan |
| Varian rasio | > 30% | Spoof |
| Kedalaman Z | > 0.01 | Variasi kedalaman yang diperlukan |

### Konfigurasi Performa

| Pengaturan | Nilai | Deskripsi |
|------------|-------|-----------|
| Interval frame | 66ms | Target ~15 FPS pemrosesan |
| Maksimum pengukuran | 30 | Ukuran riwayat anti-spoof |
| Durasi kedip | < 2 detik | Durasi kedip maksimum |
