import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/liveness_channel.dart';
import '../../domain/entities/entities.dart';
import 'liveness_event.dart';
import 'liveness_state.dart';

/// Bloc for managing liveness detection flow
class LivenessBloc extends Bloc<LivenessEvent, LivenessState> {
  final LivenessChannel _channel;
  StreamSubscription? _stateSubscription;
  int? _textureId;
  int _currentStep = 0;
  String? _lastChallengeType;

  LivenessBloc({LivenessChannel? channel})
    : _channel = channel ?? LivenessChannel(),
      super(const LivenessInitial()) {
    on<InitializeLiveness>(_onInitialize);
    on<StartCamera>(_onStartCamera);
    on<StopCamera>(_onStopCamera);
    on<StartVerification>(_onStartVerification);
    on<RetryVerification>(_onRetry);
    on<DisposeLiveness>(_onDispose);
  }

  Future<void> _onInitialize(
    InitializeLiveness event,
    Emitter<LivenessState> emit,
  ) async {
    // If already ready or initializing, don't re-initialize
    if (state is LivenessReady) {
      debugPrint('[LivenessBloc] Already in LivenessReady state, skipping init');
      return;
    }
    if (state is LivenessInitializing) {
      debugPrint('[LivenessBloc] Already initializing, skipping');
      return;
    }
    
    debugPrint('[LivenessBloc] _onInitialize started');
    emit(const LivenessInitializing());

    try {
      // Initialize native components (or reset if already initialized)
      debugPrint('[LivenessBloc] Calling _channel.initialize()');
      final success = await _channel.initialize();
      debugPrint('[LivenessBloc] initialize() returned: $success');
      if (!success) {
        emit(const LivenessError(message: 'Failed to initialize'));
        return;
      }

      // Start listening to native events (only if not already listening)
      if (_stateSubscription == null) {
        _channel.startListening();
        _stateSubscription = _channel.stateStream.listen(_handleNativeState);
      }

      debugPrint('[LivenessBloc] Emitting LivenessReady');
      emit(const LivenessReady());
      debugPrint('[LivenessBloc] LivenessReady emitted');
    } on LivenessException catch (e) {
      debugPrint('[LivenessBloc] Exception: ${e.message}');
      emit(LivenessError(message: e.message));
    }
  }

  Future<void> _onStartCamera(
    StartCamera event,
    Emitter<LivenessState> emit,
  ) async {
    try {
      // Reset step counter when camera starts
      _currentStep = 0;
      _lastChallengeType = null;
      
      final config = await _channel.startCamera();
      _textureId = config.textureId;

      emit(
        LivenessGating(
          textureId: config.textureId,
          message: 'Posisikan wajah Anda dalam bingkai',
        ),
      );
    } on LivenessException catch (e) {
      emit(LivenessError(message: e.message));
    }
  }

  Future<void> _onStopCamera(
    StopCamera event,
    Emitter<LivenessState> emit,
  ) async {
    try {
      await _channel.stopCamera();
      _textureId = null;
      emit(const LivenessReady());
    } on LivenessException catch (e) {
      emit(LivenessError(message: e.message));
    }
  }

  Future<void> _onStartVerification(
    StartVerification event,
    Emitter<LivenessState> emit,
  ) async {
    try {
      _currentStep = 0;
      _lastChallengeType = null;
      await _channel.startVerification();
    } on LivenessException catch (e) {
      emit(LivenessError(message: e.message));
    }
  }

  Future<void> _onRetry(
    RetryVerification event,
    Emitter<LivenessState> emit,
  ) async {
    try {
      _currentStep = 0;
      _lastChallengeType = null;
      await _channel.reset();
      // Emit LivenessReady immediately - native will also send Idle state
      // but that's fine since both map to LivenessReady
      emit(const LivenessReady());
    } on LivenessException catch (e) {
      emit(LivenessError(message: e.message));
    }
  }

  Future<void> _onDispose(
    DisposeLiveness event,
    Emitter<LivenessState> emit,
  ) async {
    _stateSubscription?.cancel();
    _stateSubscription = null;
    _channel.stopListening();
    _textureId = null;
  }

  /// Handle state updates from native
  void _handleNativeState(LivenessChannelState nativeState) {
    final textureId = _textureId ?? -1;

    debugPrint('[LivenessBloc] Native state: $nativeState');

    final newState = switch (nativeState) {
      IdleChannelState() => const LivenessReady(),
      InitializingChannelState() => const LivenessInitializing(),
      GatingChannelState(message: final msg) => LivenessGating(
        textureId: textureId,
        message: msg,
      ),
      GatingFailedChannelState(reason: final r, message: final m) =>
        LivenessGatingFailed(textureId: textureId, reason: r, message: m),
      ChallengeChannelState(
        type: final type,
        progress: final p,
        instruction: final i,
      ) =>
        () {
          // Update step counter when challenge type changes
          final currentType = type?.name;
          debugPrint('[LivenessBloc] Challenge: type=$currentType, progress=$p, lastType=$_lastChallengeType, step=$_currentStep');
          
          if (currentType != null && currentType != _lastChallengeType) {
            _currentStep++;
            _lastChallengeType = currentType;
            debugPrint('[LivenessBloc] Step incremented to $_currentStep for $currentType');
          }

          return LivenessChallengeActive(
            textureId: textureId,
            challengeType: type,
            progress: p,
            instruction: i,
            currentStep: _currentStep,
            totalSteps: 3, // TURN_RIGHT, TURN_LEFT, BLINK
          );
        }(),
      ProcessingChannelState(message: final m) => LivenessProcessing(
        textureId: textureId,
        message: m,
      ),
      SuccessChannelState(challenges: final c) => LivenessSuccess(
        result: LivenessResult.success(c),
      ),
      FailedChannelState(reason: final r, canRetry: final retry) =>
        LivenessFailed(reason: r, canRetry: retry),
    };

    // ignore: invalid_use_of_visible_for_testing_member
    emit(newState);
  }

  @override
  Future<void> close() {
    _stateSubscription?.cancel();
    // Don't dispose the channel here - native plugin is a singleton
    // and can be reused. Just stop listening to events.
    _channel.stopListening();
    return super.close();
  }
}
