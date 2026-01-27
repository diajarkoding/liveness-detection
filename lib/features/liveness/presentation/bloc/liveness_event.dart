import 'package:equatable/equatable.dart';

/// Liveness Bloc Events
sealed class LivenessEvent extends Equatable {
  const LivenessEvent();

  @override
  List<Object?> get props => [];
}

/// Event to initialize the liveness detection
class InitializeLiveness extends LivenessEvent {
  const InitializeLiveness();
}

/// Event to start camera preview
class StartCamera extends LivenessEvent {
  const StartCamera();
}

/// Event to stop camera
class StopCamera extends LivenessEvent {
  const StopCamera();
}

/// Event to start verification
class StartVerification extends LivenessEvent {
  const StartVerification();
}

/// Event to retry after failure
class RetryVerification extends LivenessEvent {
  const RetryVerification();
}

/// Event when native state changes
class NativeStateChanged extends LivenessEvent {
  final String stateName;
  final Map<String, dynamic> data;

  const NativeStateChanged({required this.stateName, required this.data});

  @override
  List<Object?> get props => [stateName, data];
}

/// Event to dispose resources
class DisposeLiveness extends LivenessEvent {
  const DisposeLiveness();
}
