import 'package:flutter/material.dart';

/// Utility class for displaying error messages consistently.
class ErrorHandler {
  /// Show error snackbar with retry option.
  static void showErrorSnackbar(
    BuildContext context, {
    required String message,
    VoidCallback? onRetry,
    Duration duration = const Duration(seconds: 4),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        duration: duration,
        action: onRetry != null
            ? SnackBarAction(
                label: 'Coba Lagi',
                textColor: Colors.white,
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }

  /// Show info snackbar.
  static void showInfoSnackbar(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 2),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
        backgroundColor: Colors.blue.shade700,
        duration: duration,
      ),
    );
  }

  /// Show warning snackbar.
  static void showWarningSnackbar(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade700,
        duration: duration,
      ),
    );
  }

  /// Map error codes to user-friendly messages.
  static String getErrorMessage(String errorCode) {
    final messages = {
      'CAMERA_ERROR':
          'Tidak dapat mengakses kamera. Pastikan izin kamera telah diberikan.',
      'INIT_ERROR': 'Gagal menginisialisasi. Silakan restart aplikasi.',
      'NO_FACE_DETECTED':
          'Wajah tidak terdeteksi. Pastikan wajah Anda terlihat.',
      'MULTIPLE_FACES':
          'Terdeteksi lebih dari satu wajah. Hanya satu orang yang diizinkan.',
      'FACE_TOO_SMALL': 'Wajah terlalu kecil. Dekatkan wajah ke kamera.',
      'FACE_NOT_CENTERED':
          'Wajah tidak di tengah. Posisikan wajah di tengah bingkai.',
      'FACE_TILTED': 'Kepala miring. Tegakkan kepala Anda.',
      'EYES_NOT_VISIBLE': 'Mata tidak terlihat. Lepas kacamata hitam.',
      'MOUTH_NOT_VISIBLE': 'Mulut tidak terlihat. Lepas masker.',
      'TIMEOUT': 'Waktu habis. Silakan coba lagi.',
      'SPOOF_DETECTED': 'Verifikasi gagal. Pastikan menggunakan wajah asli.',
      'PERMISSION_DENIED': 'Izin kamera ditolak. Berikan izin di pengaturan.',
      'NETWORK_ERROR': 'Koneksi bermasalah. Periksa koneksi internet Anda.',
    };

    return messages[errorCode] ?? 'Terjadi kesalahan. Silakan coba lagi.';
  }
}

/// Extension for showing error dialogs.
extension ErrorDialogExtension on BuildContext {
  /// Show error dialog with optional retry.
  Future<bool?> showErrorDialog({
    required String title,
    required String message,
    bool showRetry = true,
  }) {
    return showDialog<bool>(
      context: this,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade400),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(color: Colors.white.withAlpha(180)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          if (showRetry)
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text('Coba Lagi'),
            ),
        ],
      ),
    );
  }
}
