import 'package:flutter/material.dart';
import '../../../../core/utils/responsive.dart';

/// Widget that displays accessory detection feedback.
/// Shows warnings when user is wearing mask or sunglasses.
class AccessoryFeedback extends StatelessWidget {
  final String? gatingReason;
  final VoidCallback? onDismiss;

  const AccessoryFeedback({super.key, this.gatingReason, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    
    final feedbackInfo = _getFeedbackInfo();
    if (feedbackInfo == null) return const SizedBox.shrink();

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      builder: (context, value, child) {
        return Transform.scale(scale: value, child: child);
      },
      child: Container(
        margin: Responsive.padding(horizontal: 20, vertical: 6),
        padding: Responsive.padding(all: 14),
        decoration: BoxDecoration(
          color: feedbackInfo.color.withAlpha(230),
          borderRadius: BorderRadius.circular(Responsive.radius(12)),
          boxShadow: [
            BoxShadow(
              color: feedbackInfo.color.withAlpha(100),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              feedbackInfo.icon,
              color: Colors.white,
              size: Responsive.iconSize(26),
            ),
            SizedBox(width: Responsive.space(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    feedbackInfo.title,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: Responsive.sp(14).clamp(12.0, 16.0),
                    ),
                  ),
                  SizedBox(height: Responsive.space(2)),
                  Text(
                    feedbackInfo.message,
                    style: TextStyle(
                      color: Colors.white.withAlpha(200),
                      fontSize: Responsive.sp(12).clamp(11.0, 14.0),
                    ),
                  ),
                ],
              ),
            ),
            if (onDismiss != null)
              IconButton(
                icon: Icon(
                  Icons.close,
                  color: Colors.white70,
                  size: Responsive.iconSize(22),
                ),
                onPressed: onDismiss,
              ),
          ],
        ),
      ),
    );
  }

  _FeedbackInfo? _getFeedbackInfo() {
    if (gatingReason == null) return null;

    final reason = gatingReason!.toUpperCase();

    if (reason.contains('EYES_NOT_VISIBLE') || reason.contains('SUNGLASSES')) {
      return _FeedbackInfo(
        icon: Icons.visibility_off,
        title: 'Kacamata Hitam Terdeteksi',
        message: 'Lepas kacamata hitam Anda untuk melanjutkan',
        color: Colors.orange.shade700,
      );
    }

    if (reason.contains('MOUTH_NOT_VISIBLE') || reason.contains('MASK')) {
      return _FeedbackInfo(
        icon: Icons.masks,
        title: 'Masker Terdeteksi',
        message: 'Lepas masker Anda untuk verifikasi wajah',
        color: Colors.orange.shade700,
      );
    }

    if (reason.contains('FACE_TOO_SMALL')) {
      return _FeedbackInfo(
        icon: Icons.zoom_in,
        title: 'Wajah Terlalu Jauh',
        message: 'Dekatkan wajah Anda ke kamera',
        color: Colors.blue.shade700,
      );
    }

    if (reason.contains('FACE_NOT_CENTERED')) {
      return _FeedbackInfo(
        icon: Icons.center_focus_strong,
        title: 'Posisi Wajah',
        message: 'Posisikan wajah di tengah bingkai',
        color: Colors.blue.shade700,
      );
    }

    if (reason.contains('FACE_TILTED')) {
      return _FeedbackInfo(
        icon: Icons.straighten,
        title: 'Kepala Miring',
        message: 'Tegakkan kepala Anda',
        color: Colors.blue.shade700,
      );
    }

    if (reason.contains('MULTIPLE_FACES')) {
      return _FeedbackInfo(
        icon: Icons.people,
        title: 'Banyak Wajah',
        message: 'Hanya satu orang yang diizinkan',
        color: Colors.red.shade700,
      );
    }

    return null;
  }
}

class _FeedbackInfo {
  final IconData icon;
  final String title;
  final String message;
  final Color color;

  const _FeedbackInfo({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });
}
