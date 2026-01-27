# PRODUCT REQUIREMENTS DOCUMENT

## Feature: Secure On-device Liveness Detection

**Version:** 1.0
**Status:** Ready for Development
**Owner:** Mobile Engineering Team

---

## 1. Ringkasan Eksekutif

Fitur **On-device Liveness Detection** memastikan verifikasi identitas manusia asli secara real-time dan offline.

1. **Passive Liveness Layer:** Penambahan logika anti-spoofing (konsistensi jarak) untuk mencegah serangan _replay/screen_.
2. **Performance Optimization:** Strategi _MediaPipe Warm-up_ untuk menghilangkan _jank_ saat transisi.
3. **Low Light Booster:** Integrasi kontrol _screen brightness_ otomatis.
4. **Interface-Based Architecture:** Penerapan _Clean Architecture_ yang ketat pada native layer untuk testability.

---

## 2. Tujuan Produk (Objectives)

### Tujuan Utama

- Menyediakan verifikasi liveness yang **offline, real-time, dan on-device**.
- Mencegah _spoofing_ dasar (foto 2D, video replay) tanpa perlu backend scoring.

### Tujuan Teknis

- **Zero-Copy Preview:** Preview kamera langsung dari GPU/Surface, tidak ada passing buffer gambar ke Flutter.
- **Cold-Start Mitigation:** Waktu inisialisasi engine AI tidak boleh menghambat UX.
- **Robustness:** Berjalan optimal di kondisi minim cahaya dan variasi device Android (Low-end to Flagship).

---

## 3. Ruang Lingkup (Scope)

### In Scope

- **Hybrid Vision Pipeline:** ML Kit (Gating) + MediaPipe (Analysis).
- **Active Liveness:** Challenge acak (Kedip, Tengok, Senyum).
- **Passive Liveness (Basic):** Deteksi konsistensi jarak wajah (Geometric Consistency).
- **Environment Handling:** Auto-brightness boost & deteksi wajah tertutup (masker/kacamata).
- **State Management:** State machine ketat (Idle -> Gating -> Challenge -> Result).

### Out of Scope

- Face Recognition (Pencocokan 1:1 dengan KTP - akan dilakukan modul terpisah).
- Active Flash Spoof Analysis (Reflection analysis).

---

## 4. Definisi Keberhasilan (Success Metrics)

| Metric                            | Target                                              |
| --------------------------------- | --------------------------------------------------- |
| **False Acceptance Rate (Spoof)** | < 2% pada serangan video dasar                      |
| **False Rejection Rate (User)**   | < 5% pada kondisi pencahayaan wajar                 |
| **Initialization Lag**            | 0 ms (terasa instan oleh user karena warm-up)       |
| **CPU Usage**                     | < 40% (Average on mid-range)                        |
| **FPS Processing**                | Stabil di 15-20 FPS (Throttled untuk hemat baterai) |

---

## 5. User Flow (Updated)

1. User masuk ke halaman instruksi (Pre-Camera).

- _System Action:_ **Background Warm-up** MediaPipe engine (Paused State).

2. User tap "Mulai Verifikasi".
3. Kamera aktif (Full Screen UI, 4:3 Sensor Processing).

- _System Action:_ Cek lux (cahaya). Jika gelap, **boost screen brightness** ke 100%.

4. **Phase 1: Gating (ML Kit)**

- Validasi: 1 Wajah, Posisi Tengah, Tidak Pakai Masker/Kacamata Hitam.

5. **Phase 2: Deep Analysis (MediaPipe)**

- Challenge ditampilkan (misal: "Kedip").
- Analisis _Active Liveness_ (Eye Aspect Ratio).
- Analisis _Passive Liveness_ (Geometric Check) berjalan paralel.

6. Challenge Selesai -> Kirim Hasil ke Flutter.
7. Restore screen brightness -> Tampilkan Success/Fail Page.

---

## 6. Arsitektur Sistem (Technical Specification)

### 6.1 Camera Configuration (Critical)

- **Sensor Resolution:** Wajib set ke rasio **4:3** (misal 640x480 atau 1280x960).
- _Alasan:_ Rasio sensor natif. Crop ke 16:9 berisiko memotong dahi/dagu yang krusial untuk landmark.

- **Preview Rendering:** Menggunakan `SurfaceTexture` (Android) / `TextureID` (iOS) langsung ke Widget Flutter. **DILARANG** mengirim byte array frame ke Dart.

### 6.2 Logic Pipeline (Native Layer)

1. **Input:** ImageProxy (Android) / CMSampleBuffer (iOS).
2. **Gatekeeper (ML Kit):**

- Ringan, cepat (< 20ms).
- Filter frame sebelum masuk ke proses berat.

3. **Analyzer (MediaPipe):**

- Hanya menerima frame jika Gatekeeper return `TRUE`.
- Menggunakan `FaceLandmarker` API.

4. **Anti-Spoof Check (Passive):**

- Menghitung rasio jarak antar mata (Iris Distance) vs Ukuran Bounding Box Wajah.
- Jika wajah mendekat (box membesar) tapi jarak iris statis -> **Spoof (Layar 2D)**.

---

## 7. Functional Requirements (Detailed)

### 7.1 Face Gating (ML Kit) - Updated rules

Sistem menolak (Reject) jika:

- Jumlah wajah != 1.
- Wajah terlalu kecil (< 40% lebar layar).
- **Obstructed Face:** Probabilitas "Smiling" atau "Eyes Open" tidak terdeteksi (indikasi masker/kacamata hitam tebal).
- Wajah miring (Roll angle > 20°).

### 7.2 MediaPipe Warm-up Strategy

- Inisialisasi `FaceLandmarker` dilakukan secara _Lazy_ tapi _Pre-emptive_.
- Trigger inisialisasi saat `viewDidLoad` / `onCreate` halaman parent, bukan saat kamera dibuka.
- Kirim _dummy black frame_ 1x untuk memicu load graph ke memori.

### 7.3 Liveness Logic

#### A. Blink Detection (Active)

- Menggunakan EAR (Eye Aspect Ratio).
- Threshold: Turun di bawah 0.2 (tutup) lalu naik ke > 0.5 (buka) dalam waktu < 800ms.

#### B. Head Turn (Active)

- Menggunakan Yaw Angle.
- Threshold: > 20° (Kiri/Kanan) dan < 45° (agar tidak kehilangan mata).

#### C. Distance Consistency (Passive - Security)

- Pantau perubahan `Face Bounding Box Area` vs `Inter-ocular Distance` (jarak pupil).
- Dalam objek 3D (Wajah asli), perubahan harus linear.
- Dalam objek 2D (Layar HP ditunjukkan ke kamera), distorsi lensa sering membuat rasio ini tidak linear saat digerakkan maju-mundur.

---

## 8. Folder Structure & Code Architecture (Refined)

Menggunakan pola **Interface-based** di Native untuk memudahkan Unit Testing (Mocking vision engine).

### Android (`android/src/main/kotlin/...`)

```text
├── core/
│   ├── ICameraManager.kt
│   ├── IFaceDetector.kt        <-- Interface Generic
│   ├── ILandmarkExtractor.kt   <-- Interface Generic
│   └── IScreenManager.kt       (Brightness Control)
│
├── impl/
│   ├── mlkit/
│   │   └── MLKitFaceDetector.kt (implements IFaceDetector)
│   ├── mediapipe/
│   │   └── MediaPipeLandmarker.kt (implements ILandmarkExtractor)
│   └── AndroidScreenManager.kt
│
├── logic/
│   ├── LivenessPipeline.kt     (Coordinator)
│   ├── ChallengeEngine.kt      (State Machine: Blink, Turn)
│   └── AntiSpoofGuard.kt       (Passive Checks)
│
└── bridge/
    └── LivenessPlugin.kt       (MethodChannel Handler)

```

### iOS (`ios/Classes/...`)

```text
├── Protocols/
│   ├── FaceDetectorProtocol.swift
│   └── LandmarkExtractorProtocol.swift
│
├── Implementation/
│   ├── MLKitFaceDetector.swift
│   └── MediaPipeLandmarker.swift
│
├── Logic/
│   ├── LivenessPipeline.swift
│   └── ChallengeEngine.swift
│
└── LivenessPlugin.swift

```

---

## 9. UI / UX Guidelines (Updated)

### 9.1 Environment Feedback

- **Low Light:** Jika sensor mendeteksi gelap -> Tampilkan toast "Mencari cahaya..." -> Perlahan naikkan brightness layar -> Icon "Flash" menyala di UI.
- **Aksesoris:** Jika deteksi masker/kacamata -> Tampilkan instruksi spesifik "Mohon lepas masker/kacamata Anda".

### 9.2 Visual Guidance

- Gunakan **Oval Overlay** statis di tengah layar.
- Area di luar oval diberi efek _Blur_ atau _Darken_ (Opacity 70%) untuk fokus user.
- Progress Bar di bagian atas (Step 1 of 3).

---

## 10. Error Handling & Edge Cases

| Skenario           | Trigger                  | Tindakan Sistem                       | Pesan ke User                  |
| ------------------ | ------------------------ | ------------------------------------- | ------------------------------ |
| **Cold Start**     | User buka kamera cepat   | Tampilkan loading spinner max 1 detik | "Menyiapkan kamera..."         |
| **Low Light**      | Lux < 10                 | Boost Brightness Screen               | "Menerangkan layar..."         |
| **Accessory**      | Mata/Mulut tidak visible | Reject di Gating layer                | "Lepas masker/kacamata hitam"  |
| **Spoof Suspect**  | Jarak iris tidak natural | Fail Challenge diam-diam              | "Gerakan tidak wajar, ulangi." |
| **App Background** | User switch app          | Dispose Camera & Engine               | (Pause process)                |

---

## 11. Timeline & Phasing

### Phase 1: Core Foundation (Week 1)

- Setup CameraX (Android) & AVFoundation (iOS) dengan **Fixed 4:3 Ratio**.
- Implementasi Interface `IFaceDetector` & `ILandmarkExtractor`.
- Setup MethodChannel & EventChannel basic.

### Phase 2: Intelligence Implementation (Week 2)

- Integrasi ML Kit (Gating).
- Integrasi MediaPipe (Warm-up logic).
- Implementasi `AntiSpoofGuard` (Distance logic).

### Phase 3: UX Orchestration (Week 3)

- Flutter UI & Bloc implementation.
- Auto-brightness logic.
- Handling edge cases (Masker, Low light).

### Phase 4: Hardening & Testing (Week 4)

- Test di device Low-end (Android < 3GB RAM).
- Penetration Test (Coba spoof dengan foto/video).
