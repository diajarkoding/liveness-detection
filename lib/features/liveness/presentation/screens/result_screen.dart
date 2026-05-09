import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/responsive.dart';
import '../bloc/liveness_bloc.dart';
import '../bloc/liveness_event.dart';
import '../bloc/liveness_state.dart';
import 'camera_screen.dart';

/// Result screen showing verification success or failure.
class ResultScreen extends StatelessWidget {
  final LivenessState state;

  const ResultScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    // Initialize responsive utility
    Responsive.init(context);
    
    final isSuccess = state is LivenessSuccess;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isSuccess
                ? [const Color(0xFF1B4332), const Color(0xFF081C15)]
                : [const Color(0xFF641220), const Color(0xFF370617)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: Responsive.padding(all: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom -
                      Responsive.space(48),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      children: [
                        SizedBox(height: Responsive.space(40)),
                        // Result Icon
                        _buildResultIcon(isSuccess),
                        SizedBox(height: Responsive.space(28)),
                        // Title
                        Text(
                          isSuccess ? 'Verifikasi Berhasil!' : 'Verifikasi Gagal',
                          style: TextStyle(
                            fontSize: Responsive.sp(26).clamp(22, 32),
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: Responsive.space(14)),
                        // Description
                        _buildDescription(),
                        SizedBox(height: Responsive.space(28)),
                        // Details Card
                        if (isSuccess) _buildSuccessDetails(),
                      ],
                    ),
                    Column(
                      children: [
                        SizedBox(height: Responsive.space(30)),
                        // Actions
                        _buildActions(context),
                        SizedBox(height: Responsive.space(24)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultIcon(bool isSuccess) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        final iconContainerSize = Responsive.wp(35).clamp(100.0, 160.0);
        return Transform.scale(
          scale: value,
          child: Container(
            width: iconContainerSize,
            height: iconContainerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSuccess
                  ? Colors.green.withValues(alpha: 0.2)
                  : Colors.red.withValues(alpha: 0.2),
              border: Border.all(
                color: isSuccess ? Colors.green : Colors.red,
                width: 3,
              ),
            ),
            child: Icon(
              isSuccess ? Icons.check_rounded : Icons.close_rounded,
              size: Responsive.wp(20).clamp(60.0, 90.0),
              color: isSuccess ? Colors.green : Colors.red,
            ),
          ),
        );
      },
    );
  }

  Widget _buildDescription() {
    if (state is LivenessSuccess) {
      return Text(
        'Wajah Anda telah berhasil diverifikasi.\nAnda dapat melanjutkan proses selanjutnya.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: Responsive.sp(15).clamp(13.0, 18.0),
          color: Colors.white.withValues(alpha: 0.8),
          height: 1.5,
        ),
      );
    } else if (state is LivenessFailed) {
      final failedState = state as LivenessFailed;
      return Column(
        children: [
          Text(
            failedState.reason,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: Responsive.sp(15).clamp(13.0, 18.0),
              color: Colors.white.withValues(alpha: 0.8),
              height: 1.5,
            ),
          ),
          if (failedState.canRetry)
            Padding(
              padding: EdgeInsets.only(top: Responsive.space(8)),
              child: Text(
                'Silakan coba lagi.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: Responsive.sp(13).clamp(12.0, 16.0),
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildSuccessDetails() {
    if (state is! LivenessSuccess) return const SizedBox.shrink();

    final successState = state as LivenessSuccess;
    final challenges = successState.result.completedChallenges;

    return Container(
      padding: Responsive.padding(all: 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Responsive.radius(16)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tantangan Selesai:',
            style: TextStyle(
              fontSize: Responsive.sp(13).clamp(12.0, 16.0),
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          SizedBox(height: Responsive.space(12)),
          ...challenges.map(
            (c) => Padding(
              padding: EdgeInsets.only(bottom: Responsive.space(8)),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: Responsive.iconSize(20),
                  ),
                  SizedBox(width: Responsive.space(12)),
                  Text(
                    c.displayName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: Responsive.sp(14).clamp(12.0, 16.0),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final isSuccess = state is LivenessSuccess;
    final canRetry =
        state is LivenessFailed && (state as LivenessFailed).canRetry;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isSuccess)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                // Navigate back - InstructionScreen will handle state reset
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Responsive.radius(12)),
                ),
              ),
              child: Text(
                'Lanjutkan',
                style: TextStyle(
                  fontSize: Responsive.sp(16).clamp(14.0, 18.0),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        if (canRetry) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                // Retry verification - reset state and navigate to camera
                final bloc = context.read<LivenessBloc>();
                bloc.add(const RetryVerification());
                // Replace this screen with camera screen
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => BlocProvider.value(
                      value: bloc,
                      child: const CameraScreen(),
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Responsive.radius(12)),
                ),
              ),
              child: Text(
                'Coba Lagi',
                style: TextStyle(
                  fontSize: Responsive.sp(16).clamp(14.0, 18.0),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SizedBox(height: Responsive.space(12)),
        ],
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () {
              // Navigate back - InstructionScreen will handle state reset
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              isSuccess ? 'Kembali ke Beranda' : 'Batalkan',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: Responsive.sp(14).clamp(12.0, 16.0),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
