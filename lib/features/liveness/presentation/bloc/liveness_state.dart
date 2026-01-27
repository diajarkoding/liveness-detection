import 'package:equatable/equatable.dart';

import '../../domain/entities/entities.dart';

/// Liveness Bloc States
sealed class LivenessState extends Equatable {
  const LivenessState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any action
class LivenessInitial extends LivenessState {
  const LivenessInitial();
}

/// Initializing components (warm-up)
class LivenessInitializing extends LivenessState {
  const LivenessInitializing();
}

/// Ready to start camera
class LivenessReady extends LivenessState {
  const LivenessReady();
}

/// Camera is active, waiting for face gating
class LivenessGating extends LivenessState {
  final int textureId;
  final String message;

  const LivenessGating({required this.textureId, required this.message});

  @override
  List<Object?> get props => [textureId, message];
}

/// Face gating failed (face not in position, wearing mask, etc.)
class LivenessGatingFailed extends LivenessState {
  final int textureId;
  final String reason;
  final String message;

  const LivenessGatingFailed({
    required this.textureId,
    required this.reason,
    required this.message,
  });

  @override
  List<Object?> get props => [textureId, reason, message];
}

/// Active challenge in progress
class LivenessChallengeActive extends LivenessState {
  final int textureId;
  final ChallengeType? challengeType;
  final double progress;
  final String instruction;
  final int currentStep;
  final int totalSteps;

  const LivenessChallengeActive({
    required this.textureId,
    this.challengeType,
    required this.progress,
    required this.instruction,
    this.currentStep = 1,
    this.totalSteps = 2,
  });

  @override
  List<Object?> get props => [
    textureId,
    challengeType,
    progress,
    instruction,
    currentStep,
    totalSteps,
  ];
}

/// Processing/analyzing results
class LivenessProcessing extends LivenessState {
  final int textureId;
  final String message;

  const LivenessProcessing({required this.textureId, required this.message});

  @override
  List<Object?> get props => [textureId, message];
}

/// Verification successful
class LivenessSuccess extends LivenessState {
  final LivenessResult result;

  const LivenessSuccess({required this.result});

  @override
  List<Object?> get props => [result];
}

/// Verification failed
class LivenessFailed extends LivenessState {
  final String reason;
  final bool canRetry;

  const LivenessFailed({required this.reason, required this.canRetry});

  @override
  List<Object?> get props => [reason, canRetry];
}

/// Error occurred
class LivenessError extends LivenessState {
  final String message;

  const LivenessError({required this.message});

  @override
  List<Object?> get props => [message];
}
