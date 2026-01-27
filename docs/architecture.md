# Liveness Detection - Gambaran Arsitektur

## Arsitektur Sistem

SDK Liveness Detection menggunakan arsitektur berlapis dengan pemisahan yang jelas antara Flutter UI, state management, dan implementasi platform native.

```
┌─────────────────────────────────────────────────────────────────┐
│                         LAPISAN FLUTTER                          │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │  HomeScreen  │─▶│ Instruction  │─▶│    CameraScreen      │  │
│  │              │  │   Screen     │  │ (Texture + Overlay)  │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
│                                               │                  │
│                                               ▼                  │
│                                      ┌──────────────┐           │
│                                      │ ResultScreen │           │
│                                      └──────────────┘           │
├─────────────────────────────────────────────────────────────────┤
│                      MANAJEMEN STATE                             │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                      LivenessBloc                          │ │
│  │                                                            │ │
│  │  Event:                         State:                     │ │
│  │  - InitializeLiveness           - LivenessInitial          │ │
│  │  - StartCamera                  - LivenessInitializing     │ │
│  │  - StartVerification            - LivenessReady            │ │
│  │  - StopCamera                   - LivenessGating           │ │
│  │  - RetryVerification            - LivenessChallengeActive  │ │
│  │                                 - LivenessProcessing       │ │
│  │                                 - LivenessSuccess          │ │
│  │                                 - LivenessFailed           │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│                              ▼                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    LivenessChannel                         │ │
│  │                                                            │ │
│  │  MethodChannel: com.example.liveness_detection/method      │ │
│  │  EventChannel:  com.example.liveness_detection/events      │ │
│  └────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│                       LAPISAN NATIVE                             │
│                                                                  │
│  ┌─────────────────────────┐    ┌─────────────────────────┐    │
│  │     ANDROID (Kotlin)    │    │      iOS (Swift)        │    │
│  │                         │    │                         │    │
│  │  ┌───────────────────┐  │    │  ┌───────────────────┐  │    │
│  │  │  LivenessPlugin   │  │    │  │  LivenessPlugin   │  │    │
│  │  │  (MethodChannel)  │  │    │  │  (MethodChannel)  │  │    │
│  │  └─────────┬─────────┘  │    │  └─────────┬─────────┘  │    │
│  │            │            │    │            │            │    │
│  │            ▼            │    │            ▼            │    │
│  │  ┌───────────────────┐  │    │  ┌───────────────────┐  │    │
│  │  │  LivenessPipeline │  │    │  │  LivenessPipeline │  │    │
│  │  │  (Koordinator)    │  │    │  │  (Koordinator)    │  │    │
│  │  └─────────┬─────────┘  │    │  └─────────┬─────────┘  │    │
│  │            │            │    │            │            │    │
│  │     ┌──────┴──────┐     │    │     ┌──────┴──────┐     │    │
│  │     ▼             ▼     │    │     ▼             ▼     │    │
│  │ ┌─────────┐ ┌─────────┐ │    │ ┌─────────┐ ┌─────────┐ │    │
│  │ │ MLKit   │ │MediaPipe│ │    │ │ MLKit   │ │MediaPipe│ │    │
│  │ │ Face    │ │ Face    │ │    │ │ Face    │ │ Face    │ │    │
│  │ │Detector │ │Landmrkr │ │    │ │Detector │ │Landmrkr │ │    │
│  │ └─────────┘ └─────────┘ │    │ └─────────┘ └─────────┘ │    │
│  │                         │    │                         │    │
│  │ ┌─────────────────────┐ │    │ ┌─────────────────────┐ │    │
│  │ │  ChallengeEngine    │ │    │ │  ChallengeEngine    │ │    │
│  │ │  AntiSpoofGuard     │ │    │ │  AntiSpoofGuard     │ │    │
│  │ └─────────────────────┘ │    │ └─────────────────────┘ │    │
│  └─────────────────────────┘    └─────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Detail Komponen

### 1. Lapisan Flutter UI

#### Layar (Screen)

| Layar | Deskripsi |
|-------|-----------|
| `HomeScreen` | Titik masuk dengan penanganan izin dan tombol mulai |
| `InstructionScreen` | Instruksi pra-verifikasi, menginisialisasi model ML |
| `CameraScreen` | Feed kamera langsung dengan overlay tantangan |
| `ResultScreen` | Tampilan sukses/gagal dengan opsi coba lagi |

#### Widget

| Widget | Deskripsi |
|--------|-----------|
| `OvalOverlay` | Panduan overlay posisi wajah |
| `ChallengeIndicator` | Menampilkan tantangan saat ini dengan progres |
| `StepProgressBar` | Indikator progres langkah tantangan |
| `AccessoryFeedback` | Peringatan tentang deteksi kacamata/masker |
| `LowLightIndicator` | Peringatan cahaya rendah |

### 2. Manajemen State (BLoC)

```dart
// Event
InitializeLiveness       // Mulai inisialisasi model ML
StartCamera             // Buka kamera dan dapatkan texture
StartVerification       // Mulai fase gating
StopCamera              // Lepaskan resource kamera
RetryVerification       // Reset dan coba lagi

// State
LivenessInitial         // State awal
LivenessInitializing    // Memuat model ML
LivenessReady           // Siap memulai verifikasi
LivenessGating          // Fase deteksi wajah
LivenessChallengeActive // Tantangan sedang berlangsung
LivenessProcessing      // Pengecekan anti-spoof akhir
LivenessSuccess         // Verifikasi berhasil
LivenessFailed          // Verifikasi gagal
```

### 3. Platform Channel

```
MethodChannel: com.example.liveness_detection/method
├── initialize()      → Inisialisasi model ML
├── warmUp()          → Pemanasan MediaPipe
├── startCamera()     → Mulai kamera, kembalikan textureId
├── stopCamera()      → Hentikan kamera
├── startVerification() → Mulai gating
├── reset()           → Reset pipeline
└── dispose()         → Lepaskan semua resource

EventChannel: com.example.liveness_detection/events
└── Stream pembaruan LivenessState
    ├── idle
    ├── initializing
    ├── gating { message }
    ├── gating_failed { reason, message }
    ├── challenge { type, progress, instruction }
    ├── processing { message }
    ├── success { challenges }
    └── failed { reason, canRetry }
```

### 4. Pipeline Native

#### LivenessPipeline (Koordinator)

Orkestrator utama yang mengelola:
- Throttling frame (~15 FPS)
- Transisi state machine
- Koordinasi komponen

#### Komponen ML

| Komponen | Teknologi | Tujuan |
|----------|-----------|--------|
| Face Detector | ML Kit | Deteksi wajah cepat untuk gating |
| Landmark Extractor | MediaPipe | 478 landmark wajah + blendshapes |

#### Komponen Logika

| Komponen | Tujuan |
|----------|--------|
| ChallengeEngine | Memproses tantangan (kedip, tengok, senyum) |
| AntiSpoofGuard | Pengecekan anti-spoof konsistensi geometris |

## Aliran Data

### Aliran Verifikasi

```
┌────────────┐
│   Mulai    │
└─────┬──────┘
      │
      ▼
┌────────────────┐
│  FASE GATING   │◄─────────────────┐
│  (ML Kit)      │                  │
└─────┬──────────┘                  │
      │                             │
      ▼                             │
┌────────────────┐                  │
│  Wajah Valid?  │──Tidak───────────┘
└─────┬──────────┘
      │ Ya
      ▼
┌────────────────────────────────────────┐
│           FASE TANTANGAN               │
│           (MediaPipe)                  │
│                                        │
│  ┌──────────────────────────────────┐  │
│  │  Tantangan 1: TENGOK KANAN       │  │
│  │  (yaw > 20°, mulai dari tengah)  │  │
│  └───────────────┬──────────────────┘  │
│                  │                     │
│  ┌───────────────▼──────────────────┐  │
│  │  Tantangan 2: TENGOK KIRI        │  │
│  │  (yaw < -20°, mulai dari tengah) │  │
│  └───────────────┬──────────────────┘  │
│                  │                     │
│  ┌───────────────▼──────────────────┐  │
│  │  Tantangan 3: KEDIP (2x)         │  │
│  │  (menggunakan blendshapes)       │  │
│  └───────────────┬──────────────────┘  │
└──────────────────┼─────────────────────┘
                   │
                   ▼
┌────────────────────────────────────────┐
│          PENGECEKAN ANTI-SPOOF         │
│                                        │
│  Analisis Konsistensi Geometris:       │
│  - Varian rasio BoundingBox / IOD²     │
│  - Pengecekan profil kedalaman Z       │
└───────────────────┬────────────────────┘
                    │
         ┌──────────┴──────────┐
         ▼                     ▼
   ┌──────────┐          ┌──────────┐
   │ BERHASIL │          │  GAGAL   │
   └──────────┘          └──────────┘
```

### Aliran Pemrosesan Frame

```
Frame Kamera (30 FPS)
        │
        ▼
┌───────────────────┐
│ Throttling Frame  │──Lewati jika < 66ms sejak terakhir
│ (~15 FPS target)  │
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│   State Saat Ini  │
└─────────┬─────────┘
          │
    ┌─────┴─────┐
    ▼           ▼
┌───────┐   ┌───────────┐
│Gating │   │ Tantangan │
└───┬───┘   └─────┬─────┘
    │             │
    ▼             ▼
┌───────────┐ ┌───────────────┐
│  ML Kit   │ │   MediaPipe   │
│  Deteksi  │ │   Landmark    │
└─────┬─────┘ └───────┬───────┘
      │               │
      ▼               ▼
┌───────────┐ ┌───────────────┐
│  Cek      │ │   Proses      │
│  Gating   │ │   Tantangan   │
└─────┬─────┘ └───────┬───────┘
      │               │
      └───────┬───────┘
              │
              ▼
       Pembaruan State
              │
              ▼
       EventChannel
              │
              ▼
         Flutter UI
```

## Strategi Anti-Spoofing

### Pengecekan Konsistensi Geometris

Anti-spoof guard menggunakan konsistensi geometris untuk mendeteksi serangan layar 2D:

```
Wajah 3D Asli:
┌─────────────────────────────────────────┐
│                                         │
│  Ketika wajah mendekat/menjauh:         │
│                                         │
│  Area BoundingBox ∝ (Jarak)²            │
│  Jarak Antar-Mata ∝ Jarak               │
│                                         │
│  Rasio = AreaBBox / IOD² ≈ KONSTAN      │
│                                         │
└─────────────────────────────────────────┘

Layar 2D (Spoof):
┌─────────────────────────────────────────┐
│                                         │
│  Karena distorsi lensa pada permukaan   │
│  datar dan efek paralaks:               │
│                                         │
│  Rasio = AreaBBox / IOD² = BERVARIASI   │
│  Varian tinggi mengindikasikan spoof!   │
│                                         │
└─────────────────────────────────────────┘
```

### Threshold Deteksi

| Pengecekan | Threshold | Hasil |
|------------|-----------|-------|
| Varian rasio | < 15% | Lolos |
| Varian rasio | 15-30% | Mencurigakan |
| Varian rasio | > 30% | Spoof terdeteksi |
| Rentang kedalaman Z | < 0.01 | Gambar datar (spoof) |

## Pertimbangan Performa

### Throttling Frame

- Target: ~15 FPS pemrosesan
- Interval minimum: 66ms antar frame
- Mengurangi konsumsi baterai dan panas

### Optimasi Model

- ML Kit: Deteksi berbasis CPU cepat untuk gating
- MediaPipe: Ekstraksi landmark yang dipercepat GPU
- Pemanasan selama layar instruksi

### Manajemen Memori

- Instance tunggal model ML
- Pembuangan yang tepat saat keluar layar
- Image proxy ditutup setelah pemrosesan

## Pertimbangan Keamanan

1. **Pemrosesan On-device**: Tidak ada data yang dikirim ke server
2. **Anti-spoofing**: Pengecekan konsistensi geometris
3. **Multi-tantangan**: Verifikasi berurutan
4. **Perlindungan Timeout**: 15 detik per tantangan
5. **Deteksi Aksesori**: Memblokir kacamata hitam/masker
