import 'package:flutter/material.dart';
import '../../../../core/utils/responsive.dart';

/// Step progress bar widget for multi-step verification.
class StepProgressBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const StepProgressBar({
    super.key,
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    
    return Container(
      padding: Responsive.padding(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Responsive.radius(20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Langkah $currentStep dari $totalSteps',
            style: TextStyle(
              color: Colors.white,
              fontSize: Responsive.sp(11).clamp(10.0, 14.0),
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(width: Responsive.space(10)),
          ...List.generate(totalSteps, (index) {
            final stepNum = index + 1;
            final isCompleted = stepNum < currentStep;
            final isCurrent = stepNum == currentStep;

            return Padding(
              padding: EdgeInsets.only(left: index > 0 ? Responsive.space(4) : 0),
              child: _buildStepDot(isCompleted, isCurrent),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStepDot(bool isCompleted, bool isCurrent) {
    Color color;
    double size;

    if (isCompleted) {
      color = Colors.green;
      size = Responsive.space(10);
    } else if (isCurrent) {
      color = Colors.blue;
      size = Responsive.space(12);
    } else {
      color = Colors.white.withValues(alpha: 0.3);
      size = Responsive.space(8);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: isCurrent ? Border.all(color: Colors.white, width: 2) : null,
      ),
    );
  }
}
