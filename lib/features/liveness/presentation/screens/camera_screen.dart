import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/responsive.dart';
import '../../data/brightness_service.dart';
import '../bloc/liveness_bloc.dart';
import '../bloc/liveness_event.dart';
import '../bloc/liveness_state.dart';
import '../widgets/accessory_feedback.dart';
import '../widgets/challenge_indicator.dart';
import '../widgets/low_light_indicator.dart';
import '../widgets/oval_overlay.dart';
import '../widgets/progress_bar.dart';
import 'result_screen.dart';

/// Camera screen for liveness verification.
/// Displays camera preview with oval overlay and challenge instructions.
/// Includes UX enhancements: auto-brightness, low-light detection, accessory feedback.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  final BrightnessService _brightnessService = BrightnessService();
  late LivenessBloc _bloc;
  bool _isLowLight = false;
  String? _currentGatingReason;

  @override
  void initState() {
    super.initState();
    // Observe app lifecycle
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bloc = context.read<LivenessBloc>();
    // Start camera when screen opens (only once)
    if (!_cameraStarted) {
      _cameraStarted = true;
      _bloc.add(const StartCamera());
      // Check and auto-boost brightness
      _checkLightCondition();
    }
  }

  bool _cameraStarted = false;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Restore brightness when leaving
    _brightnessService.restoreBrightness();
    // Stop camera when leaving screen (use cached bloc reference)
    _bloc.add(const StopCamera());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // App going to background - pause camera
        _bloc.add(const StopCamera());
        break;
      case AppLifecycleState.resumed:
        // App coming back - resume camera
        _bloc.add(const StartCamera());
        _checkLightCondition();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _checkLightCondition() async {
    final isLow = await _brightnessService.isLowLightEnvironment();
    if (isLow) {
      await _brightnessService.boostBrightness();
    }
    if (mounted) {
      setState(() {
        _isLowLight = isLow;
      });
    }
  }

  void _navigateToResult(LivenessState state) {
    // Restore brightness before navigating
    _brightnessService.restoreBrightness();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<LivenessBloc>(),
          child: ResultScreen(state: state),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Initialize responsive utility
    Responsive.init(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: BlocConsumer<LivenessBloc, LivenessState>(
        listener: (context, state) {
          // Navigate to result on success or failure
          if (state is LivenessSuccess || state is LivenessFailed) {
            _navigateToResult(state);
          }

          // Update current gating reason for accessory feedback
          if (state is LivenessGatingFailed) {
            setState(() {
              _currentGatingReason = state.reason;
            });
          } else {
            if (_currentGatingReason != null) {
              setState(() {
                _currentGatingReason = null;
              });
            }
          }
        },
        builder: (context, state) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // Camera Preview
              _buildCameraPreview(state),

              // Overlay & UI
              _buildOverlay(state),

              // Top Bar with Progress & Low-light indicator
              _buildTopBar(state),

              // Accessory Feedback (mask/sunglasses)
              if (_currentGatingReason != null)
                Positioned(
                  top: MediaQuery.of(context).padding.top + Responsive.space(90),
                  left: 0,
                  right: 0,
                  child: AccessoryFeedback(
                    gatingReason: _currentGatingReason,
                    onDismiss: () {
                      setState(() {
                        _currentGatingReason = null;
                      });
                    },
                  ),
                ),

              // Bottom Instruction
              _buildBottomInstruction(state),

              // Loading Overlay
              if (state is LivenessProcessing) _buildLoadingOverlay(state),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCameraPreview(LivenessState state) {
    int? textureId;

    if (state is LivenessGating) {
      textureId = state.textureId;
    } else if (state is LivenessGatingFailed) {
      textureId = state.textureId;
    } else if (state is LivenessChallengeActive) {
      textureId = state.textureId;
    } else if (state is LivenessProcessing) {
      textureId = state.textureId;
    }

    if (textureId == null || textureId < 0) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: 3 / 4, // 4:3 sensor, displayed portrait
        child: Texture(textureId: textureId),
      ),
    );
  }

  Widget _buildOverlay(LivenessState state) {
    Color borderColor = Colors.white70;

    if (state is LivenessGatingFailed) {
      borderColor = Colors.red;
    } else if (state is LivenessChallengeActive) {
      // Animate color based on progress
      borderColor = Color.lerp(Colors.blue, Colors.green, state.progress)!;
    }

    return OvalOverlay(
      borderColor: borderColor,
      borderWidth: 3,
      overlayOpacity: 0.7,
    );
  }

  Widget _buildTopBar(LivenessState state) {
    int currentStep = 1;
    int totalSteps = 2;

    if (state is LivenessChallengeActive) {
      currentStep = state.currentStep;
      totalSteps = state.totalSteps;
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: Responsive.padding(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              // Close button, Title, and Low-light indicator
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: Colors.white,
                      size: Responsive.iconSize(24),
                    ),
                    onPressed: () {
                      _brightnessService.restoreBrightness();
                      Navigator.of(context).pop();
                    },
                  ),
                  Expanded(
                    child: Text(
                      'Verifikasi Wajah',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: Responsive.sp(17).clamp(15, 20),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Low-light indicator
                  LowLightIndicator(
                    isLowLight: _isLowLight,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Cahaya rendah terdeteksi. Kecerahan layar telah dinaikkan.',
                            style: TextStyle(fontSize: Responsive.sp(14)),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
              SizedBox(height: Responsive.space(8)),
              // Progress bar
              if (state is LivenessChallengeActive)
                StepProgressBar(
                  currentStep: currentStep,
                  totalSteps: totalSteps,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomInstruction(LivenessState state) {
    String message = '';
    bool isError = false;
    double? progress;

    if (state is LivenessGating) {
      message = state.message;
    } else if (state is LivenessGatingFailed) {
      message = state.message;
      isError = true;
    } else if (state is LivenessChallengeActive) {
      message = state.instruction;
      progress = state.progress;
    }

    if (message.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: Responsive.padding(all: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Challenge indicator with progress
              if (state is LivenessChallengeActive &&
                  state.challengeType != null)
                Padding(
                  padding: EdgeInsets.only(bottom: Responsive.space(14)),
                  child: ChallengeIndicator(
                    type: state.challengeType!,
                    progress: state.progress,
                  ),
                ),

              // Message box
              Container(
                padding: Responsive.padding(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: isError
                      ? Colors.red.withAlpha(230)
                      : Colors.black.withAlpha(180),
                  borderRadius: BorderRadius.circular(Responsive.radius(16)),
                  border: Border.all(
                    color: isError
                        ? Colors.red.shade300
                        : Colors.white.withAlpha(50),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: Responsive.sp(16).clamp(14, 20),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (progress != null) ...[
                      SizedBox(height: Responsive.space(12)),
                      LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.white.withAlpha(50),
                        valueColor: const AlwaysStoppedAnimation(Colors.green),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay(LivenessProcessing state) {
    return Container(
      color: Colors.black.withAlpha(180),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            SizedBox(height: Responsive.space(24)),
            Text(
              state.message,
              style: TextStyle(
                color: Colors.white,
                fontSize: Responsive.sp(15).clamp(13, 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
