import 'package:flutter/material.dart';

/// Oval overlay widget for face positioning guide.
/// Creates a transparent oval in the center with darkened surroundings.
class OvalOverlay extends StatelessWidget {
  final Color borderColor;
  final double borderWidth;
  final double overlayOpacity;

  const OvalOverlay({
    super.key,
    this.borderColor = Colors.white,
    this.borderWidth = 3.0,
    this.overlayOpacity = 0.7,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate oval dimensions (centered, ~60% width, ~40% height)
        final double ovalWidth = constraints.maxWidth * 0.7;
        final double ovalHeight = constraints.maxHeight * 0.45;
        final double centerX = constraints.maxWidth / 2;
        final double centerY =
            constraints.maxHeight * 0.4; // Slightly above center

        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _OvalOverlayPainter(
            ovalWidth: ovalWidth,
            ovalHeight: ovalHeight,
            centerX: centerX,
            centerY: centerY,
            borderColor: borderColor,
            borderWidth: borderWidth,
            overlayOpacity: overlayOpacity,
          ),
        );
      },
    );
  }
}

class _OvalOverlayPainter extends CustomPainter {
  final double ovalWidth;
  final double ovalHeight;
  final double centerX;
  final double centerY;
  final Color borderColor;
  final double borderWidth;
  final double overlayOpacity;

  _OvalOverlayPainter({
    required this.ovalWidth,
    required this.ovalHeight,
    required this.centerX,
    required this.centerY,
    required this.borderColor,
    required this.borderWidth,
    required this.overlayOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Create oval path
    final ovalRect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: ovalWidth,
      height: ovalHeight,
    );
    final ovalPath = Path()..addOval(ovalRect);

    // Create full screen path
    final fullPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Create overlay path (screen minus oval)
    final overlayPath = Path.combine(
      PathOperation.difference,
      fullPath,
      ovalPath,
    );

    // Draw dark overlay
    final overlayPaint = Paint()
      ..color = Colors.black.withOpacity(overlayOpacity)
      ..style = PaintingStyle.fill;
    canvas.drawPath(overlayPath, overlayPaint);

    // Draw oval border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    canvas.drawOval(ovalRect, borderPaint);

    // Draw corner guides
    _drawCornerGuides(canvas, ovalRect);
  }

  void _drawCornerGuides(Canvas canvas, Rect ovalRect) {
    final guidePaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth + 1
      ..strokeCap = StrokeCap.round;

    final guideLength = ovalWidth * 0.1;

    // Top guides
    canvas.drawLine(
      Offset(centerX - ovalWidth * 0.3, ovalRect.top),
      Offset(centerX - ovalWidth * 0.3 + guideLength, ovalRect.top),
      guidePaint,
    );
    canvas.drawLine(
      Offset(centerX + ovalWidth * 0.3, ovalRect.top),
      Offset(centerX + ovalWidth * 0.3 - guideLength, ovalRect.top),
      guidePaint,
    );

    // Bottom guides
    canvas.drawLine(
      Offset(centerX - ovalWidth * 0.3, ovalRect.bottom),
      Offset(centerX - ovalWidth * 0.3 + guideLength, ovalRect.bottom),
      guidePaint,
    );
    canvas.drawLine(
      Offset(centerX + ovalWidth * 0.3, ovalRect.bottom),
      Offset(centerX + ovalWidth * 0.3 - guideLength, ovalRect.bottom),
      guidePaint,
    );

    // Side guides
    canvas.drawLine(
      Offset(ovalRect.left, centerY - ovalHeight * 0.2),
      Offset(ovalRect.left, centerY - ovalHeight * 0.2 + guideLength),
      guidePaint,
    );
    canvas.drawLine(
      Offset(ovalRect.right, centerY - ovalHeight * 0.2),
      Offset(ovalRect.right, centerY - ovalHeight * 0.2 + guideLength),
      guidePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _OvalOverlayPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.overlayOpacity != overlayOpacity;
  }
}
