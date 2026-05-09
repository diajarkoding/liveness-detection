import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/entities/entities.dart';

/// Service for communicating with native liveness detection pipeline
class LivenessChannel {
  static const _methodChannel = MethodChannel(
    'com.diajarkoding.livenessdetection/method',
  );
  static const _eventChannel = EventChannel(
    'com.diajarkoding.livenessdetection/events',
  );

  StreamSubscription? _eventSubscription;
  final _stateController = StreamController<LivenessChannelState>.broadcast();

  /// Stream of liveness states from native
  Stream<LivenessChannelState> get stateStream => _stateController.stream;

  /// Initialize the liveness detection components
  Future<bool> initialize() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('initialize');
      return result?['success'] == true;
    } on PlatformException catch (e) {
      throw LivenessException('Initialization failed: ${e.message}');
    }
  }

  /// Warm up MediaPipe engine (call during instruction screen)
  Future<bool> warmUp() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('warmUp');
      return result?['success'] == true;
    } on PlatformException catch (e) {
      throw LivenessException('Warm-up failed: ${e.message}');
    }
  }

  /// Start camera and get texture ID for Flutter rendering
  Future<CameraConfig> startCamera() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('startCamera');
      if (result == null) {
        throw LivenessException('Failed to start camera');
      }

      return CameraConfig(
        textureId: (result['textureId'] as num).toInt(),
        width: (result['width'] as num).toInt(),
        height: (result['height'] as num).toInt(),
      );
    } on PlatformException catch (e) {
      throw LivenessException('Camera start failed: ${e.message}');
    }
  }

  /// Stop camera
  Future<void> stopCamera() async {
    try {
      await _methodChannel.invokeMethod('stopCamera');
    } on PlatformException catch (e) {
      throw LivenessException('Camera stop failed: ${e.message}');
    }
  }

  /// Start listening to native state events
  void startListening() {
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Map) {
          final state = _parseState(event);
          _stateController.add(state);
        }
      },
      onError: (error) {
        _stateController.addError(LivenessException('Event error: $error'));
      },
    );
  }

  /// Stop listening to events
  void stopListening() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  /// Start verification process
  Future<void> startVerification() async {
    try {
      await _methodChannel.invokeMethod('startVerification');
    } on PlatformException catch (e) {
      throw LivenessException('Start verification failed: ${e.message}');
    }
  }

  /// Reset pipeline state
  Future<void> reset() async {
    try {
      await _methodChannel.invokeMethod('reset');
    } on PlatformException catch (e) {
      throw LivenessException('Reset failed: ${e.message}');
    }
  }

  /// Dispose all resources
  Future<void> dispose() async {
    stopListening();
    await _stateController.close();
    try {
      await _methodChannel.invokeMethod('dispose');
    } catch (_) {}
  }

  /// Parse native event map to LivenessChannelState
  LivenessChannelState _parseState(Map event) {
    final stateStr = event['state'] as String?;

    return switch (stateStr) {
      'idle' => const LivenessChannelState.idle(),
      'initializing' => const LivenessChannelState.initializing(),
      'gating' => LivenessChannelState.gating(
        message: event['message'] as String? ?? '',
      ),
      'gating_failed' => LivenessChannelState.gatingFailed(
        reason: event['reason'] as String? ?? '',
        message: event['message'] as String? ?? '',
      ),
      'challenge' => LivenessChannelState.challenge(
        type: ChallengeType.fromString(event['type'] as String? ?? ''),
        progress: (event['progress'] as num?)?.toDouble() ?? 0.0,
        instruction: event['instruction'] as String? ?? '',
      ),
      'processing' => LivenessChannelState.processing(
        message: event['message'] as String? ?? '',
      ),
      'success' => LivenessChannelState.success(
        challenges:
            (event['challenges'] as List?)
                ?.map((e) => ChallengeType.fromString(e as String))
                .whereType<ChallengeType>()
                .toSet() ??
            {},
      ),
      'failed' => LivenessChannelState.failed(
        reason: event['reason'] as String? ?? '',
        canRetry: event['canRetry'] as bool? ?? true,
      ),
      _ => const LivenessChannelState.idle(),
    };
  }
}

/// Camera configuration from native
class CameraConfig {
  final int textureId;
  final int width;
  final int height;

  const CameraConfig({
    required this.textureId,
    required this.width,
    required this.height,
  });
}

/// State received from native liveness pipeline
sealed class LivenessChannelState {
  const LivenessChannelState();

  const factory LivenessChannelState.idle() = IdleChannelState;
  const factory LivenessChannelState.initializing() = InitializingChannelState;
  const factory LivenessChannelState.gating({required String message}) =
      GatingChannelState;
  const factory LivenessChannelState.gatingFailed({
    required String reason,
    required String message,
  }) = GatingFailedChannelState;
  const factory LivenessChannelState.challenge({
    ChallengeType? type,
    required double progress,
    required String instruction,
  }) = ChallengeChannelState;
  const factory LivenessChannelState.processing({required String message}) =
      ProcessingChannelState;
  const factory LivenessChannelState.success({
    required Set<ChallengeType> challenges,
  }) = SuccessChannelState;
  const factory LivenessChannelState.failed({
    required String reason,
    required bool canRetry,
  }) = FailedChannelState;
}

class IdleChannelState extends LivenessChannelState {
  const IdleChannelState();
}

class InitializingChannelState extends LivenessChannelState {
  const InitializingChannelState();
}

class GatingChannelState extends LivenessChannelState {
  final String message;
  const GatingChannelState({required this.message});
}

class GatingFailedChannelState extends LivenessChannelState {
  final String reason;
  final String message;
  const GatingFailedChannelState({required this.reason, required this.message});
}

class ChallengeChannelState extends LivenessChannelState {
  final ChallengeType? type;
  final double progress;
  final String instruction;
  const ChallengeChannelState({
    this.type,
    required this.progress,
    required this.instruction,
  });
}

class ProcessingChannelState extends LivenessChannelState {
  final String message;
  const ProcessingChannelState({required this.message});
}

class SuccessChannelState extends LivenessChannelState {
  final Set<ChallengeType> challenges;
  const SuccessChannelState({required this.challenges});
}

class FailedChannelState extends LivenessChannelState {
  final String reason;
  final bool canRetry;
  const FailedChannelState({required this.reason, required this.canRetry});
}

/// Exception for liveness operations
class LivenessException implements Exception {
  final String message;
  const LivenessException(this.message);

  @override
  String toString() => 'LivenessException: $message';
}
