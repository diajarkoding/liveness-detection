import 'package:flutter/material.dart';
import '../../../../core/utils/responsive.dart';

/// Widget that displays a low-light warning indicator.
class LowLightIndicator extends StatefulWidget {
  final bool isLowLight;
  final VoidCallback? onTap;

  const LowLightIndicator({super.key, required this.isLowLight, this.onTap});

  @override
  State<LowLightIndicator> createState() => _LowLightIndicatorState();
}

class _LowLightIndicatorState extends State<LowLightIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLowLight) return const SizedBox.shrink();

    Responsive.init(context);

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              padding: Responsive.padding(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.shade800.withAlpha(230),
                borderRadius: BorderRadius.circular(Responsive.radius(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withAlpha(100),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wb_sunny,
                    color: Colors.white,
                    size: Responsive.iconSize(16),
                  ),
                  SizedBox(width: Responsive.space(5)),
                  Text(
                    'Cahaya Rendah',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: Responsive.sp(11).clamp(10.0, 14.0),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
