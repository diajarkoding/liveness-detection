import 'package:flutter/material.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/entities/entities.dart';

/// Visual indicator for active liveness challenge.
class ChallengeIndicator extends StatelessWidget {
  final ChallengeType type;
  final double progress;

  const ChallengeIndicator({
    super.key,
    required this.type,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    
    return Container(
      padding: Responsive.padding(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.2),
        borderRadius: BorderRadius.circular(Responsive.radius(20)),
        border: Border.all(
          color: Color.lerp(Colors.blue, Colors.green, progress)!,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildIcon(),
          SizedBox(width: Responsive.space(12)),
          _buildProgressCircle(),
        ],
      ),
    );
  }

  Widget _buildIcon() {
    IconData icon;

    switch (type) {
      case ChallengeType.blink:
        icon = Icons.visibility;
      case ChallengeType.turnLeft:
        icon = Icons.arrow_back;
      case ChallengeType.turnRight:
        icon = Icons.arrow_forward;
      case ChallengeType.smile:
        icon = Icons.sentiment_satisfied_alt;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.0, end: progress > 0.5 ? 1.2 : 1.0),
      duration: const Duration(milliseconds: 200),
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: Icon(icon, color: Colors.white, size: Responsive.iconSize(28)),
        );
      },
    );
  }

  Widget _buildProgressCircle() {
    final circleSize = Responsive.space(44);
    return SizedBox(
      width: circleSize,
      height: circleSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          CircularProgressIndicator(
            value: 1.0,
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation(Colors.white.withOpacity(0.2)),
          ),
          // Progress circle
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 150),
            builder: (context, value, child) {
              return CircularProgressIndicator(
                value: value,
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(
                  Color.lerp(Colors.blue, Colors.green, value)!,
                ),
              );
            },
          ),
          // Percentage text
          Text(
            '${(progress * 100).toInt()}%',
            style: TextStyle(
              color: Colors.white,
              fontSize: Responsive.sp(11).clamp(10.0, 14.0),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
