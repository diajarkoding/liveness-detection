import 'package:equatable/equatable.dart';

import 'challenge_type.dart';

/// Result of liveness verification
class LivenessResult extends Equatable {
  /// Whether verification was successful
  final bool isSuccess;

  /// Completed challenges
  final Set<ChallengeType> completedChallenges;

  /// Failure reason if not successful
  final String? failureReason;

  /// Whether user can retry
  final bool canRetry;

  /// Timestamp of the result
  final DateTime timestamp;

  const LivenessResult({
    required this.isSuccess,
    this.completedChallenges = const {},
    this.failureReason,
    this.canRetry = true,
    required this.timestamp,
  });

  /// Create a successful result
  factory LivenessResult.success(Set<ChallengeType> challenges) {
    return LivenessResult(
      isSuccess: true,
      completedChallenges: challenges,
      timestamp: DateTime.now(),
    );
  }

  /// Create a failed result
  factory LivenessResult.failure(String reason, {bool canRetry = true}) {
    return LivenessResult(
      isSuccess: false,
      failureReason: reason,
      canRetry: canRetry,
      timestamp: DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
    isSuccess,
    completedChallenges,
    failureReason,
    canRetry,
    timestamp,
  ];
}
