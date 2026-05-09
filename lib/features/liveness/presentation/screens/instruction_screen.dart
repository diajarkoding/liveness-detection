import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/responsive.dart';
import '../bloc/liveness_bloc.dart';
import '../bloc/liveness_event.dart';
import '../bloc/liveness_state.dart';
import 'camera_screen.dart';

/// RouteObserver for detecting when this screen becomes visible again
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

/// Instruction screen shown before starting liveness verification.
class InstructionScreen extends StatefulWidget {
  const InstructionScreen({super.key});

  @override
  State<InstructionScreen> createState() => _InstructionScreenState();
}

class _InstructionScreenState extends State<InstructionScreen>
    with WidgetsBindingObserver, RouteAware {
  late LivenessBloc _bloc;
  late LivenessState _currentState;
  StreamSubscription<LivenessState>? _subscription;
  bool _hasInitialized = false;
  bool _isResettingState = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[InstructionScreen] initState');
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle if needed
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    debugPrint('[InstructionScreen] didChangeDependencies');

    // Subscribe to route changes
    routeObserver.subscribe(this, ModalRoute.of(context)!);

    // Get bloc only once
    if (_subscription == null) {
      _bloc = context.read<LivenessBloc>();
      _currentState = _bloc.state;
      debugPrint(
        '[InstructionScreen] Initial state: ${_currentState.runtimeType}',
      );

      // Subscribe to state changes manually
      _subscription = _bloc.stream.listen((state) {
        debugPrint('[InstructionScreen] Stream received: ${state.runtimeType}');
        // Only update state for relevant states on instruction screen
        // Ignore camera-related states (Gating, Challenge, etc.) since those
        // are handled by CameraScreen
        final isRelevantState =
            state is LivenessInitial ||
            state is LivenessInitializing ||
            state is LivenessReady ||
            state is LivenessError;
        if (mounted && isRelevantState) {
          // Reset the resetting flag when we receive LivenessReady
          if (state is LivenessReady) {
            _isResettingState = false;
          }
          setState(() {
            _currentState = state;
          });
        }
      });

      _initializeIfNeeded();
    }
  }

  void _initializeIfNeeded() {
    if (_hasInitialized) return;
    _hasInitialized = true;

    final currentState = _bloc.state;
    debugPrint(
      '[InstructionScreen] _initializeIfNeeded: state=${currentState.runtimeType}',
    );

    if (currentState is LivenessReady) {
      // Already ready, update UI
      debugPrint('[InstructionScreen] Already in LivenessReady state');
      setState(() {
        _currentState = currentState;
      });
    } else if (currentState is LivenessSuccess ||
        currentState is LivenessFailed) {
      // Returned from result screen, reset to ready
      debugPrint('[InstructionScreen] Returned from result, resetting state');
      _isResettingState = true;
      Future.microtask(() {
        if (mounted) {
          _bloc.add(const RetryVerification());
        }
      });
    } else if (currentState is LivenessInitial ||
        currentState is LivenessInitializing) {
      // Start or continue initialization
      Future.microtask(() {
        if (mounted) {
          debugPrint('[InstructionScreen] Adding InitializeLiveness event');
          _bloc.add(const InitializeLiveness());
        }
      });
    } else {
      // Other states (Gating, Challenge, etc.) - reset to ready
      debugPrint('[InstructionScreen] Unexpected state, resetting');
      Future.microtask(() {
        if (mounted) {
          _bloc.add(const RetryVerification());
        }
      });
    }
  }

  /// Called when returning to this screen from navigation
  void _handleReturnToScreen() {
    if (_isResettingState) return; // Prevent multiple resets

    final currentState = _bloc.state;
    debugPrint(
      '[InstructionScreen] _handleReturnToScreen: state=${currentState.runtimeType}',
    );

    // If state is not ready, reset it
    if (currentState is LivenessSuccess ||
        currentState is LivenessFailed ||
        currentState is LivenessGating ||
        currentState is LivenessChallengeActive ||
        currentState is LivenessProcessing) {
      _isResettingState = true;
      _bloc.add(const RetryVerification());
    } else if (currentState is LivenessReady) {
      // Already ready, just update UI
      _isResettingState = false;
      if (mounted) {
        setState(() {
          _currentState = currentState;
        });
      }
    } else if (currentState is LivenessInitial) {
      // Need to initialize
      _bloc.add(const InitializeLiveness());
    }
    // If LivenessInitializing, just wait for it to complete
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  /// Called when a route has been popped off and this route is now visible
  @override
  void didPopNext() {
    debugPrint('[InstructionScreen] didPopNext - route became visible again');
    _handleReturnToScreen();
  }

  void _startVerification() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) =>
                BlocProvider.value(value: _bloc, child: const CameraScreen()),
          ),
        )
        .then((_) {
          // Called when returning from CameraScreen or ResultScreen
          _handleReturnToScreen();
        });
  }

  @override
  Widget build(BuildContext context) {
    // Initialize responsive utility
    Responsive.init(context);

    // Check if we need to reset state when returning from result
    final blocState = _bloc.state;
    if (blocState is LivenessSuccess || blocState is LivenessFailed) {
      // Reset state if returning from result
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _handleReturnToScreen();
        }
      });
    }

    debugPrint(
      '[InstructionScreen] build with state: ${_currentState.runtimeType}',
    );

    final isReady = _currentState is LivenessReady;
    final isInitializing =
        _currentState is LivenessInitializing ||
        _currentState is LivenessInitial;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: Responsive.padding(all: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom -
                      Responsive.space(48),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      children: [
                        SizedBox(height: Responsive.space(20)),
                        _buildHeader(),
                        SizedBox(height: Responsive.space(40)),
                        _buildInstructionsList(),
                      ],
                    ),
                    Column(
                      children: [
                        SizedBox(height: Responsive.space(30)),
                        // Start Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isReady ? _startVerification : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isReady
                                  ? Colors.blue.shade600
                                  : Colors.grey.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  Responsive.radius(12),
                                ),
                              ),
                            ),
                            child: isInitializing
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation(
                                            Colors.white.withValues(alpha: 0.7),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Menyiapkan...',
                                        style: TextStyle(
                                          fontSize: Responsive.sp(
                                            16,
                                          ).clamp(14.0, 18.0),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    isReady ? 'Mulai Verifikasi' : 'Memuat...',
                                    style: TextStyle(
                                      fontSize: Responsive.sp(
                                        16,
                                      ).clamp(14.0, 18.0),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
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

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: Responsive.wp(30).clamp(90, 140),
          height: Responsive.wp(30).clamp(90, 140),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Colors.blue.shade400, Colors.purple.shade400],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Icon(
            Icons.face_retouching_natural,
            size: Responsive.wp(16).clamp(48, 72),
            color: Colors.white,
          ),
        ),
        SizedBox(height: Responsive.space(24)),
        Text(
          'Verifikasi Wajah',
          style: TextStyle(
            fontSize: Responsive.sp(26).clamp(22, 32),
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        SizedBox(height: Responsive.space(8)),
        Text(
          'Pastikan wajah Anda terlihat jelas',
          style: TextStyle(
            fontSize: Responsive.sp(15).clamp(13, 18),
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildInstructionsList() {
    final instructions = [
      (Icons.light_mode, 'Pastikan pencahayaan cukup'),
      (Icons.visibility, 'Lepas kacamata hitam & masker'),
      (Icons.face, 'Posisikan wajah di tengah bingkai'),
      (Icons.touch_app, 'Ikuti instruksi yang muncul'),
    ];

    return Container(
      padding: Responsive.padding(all: 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Responsive.radius(16)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: instructions.asMap().entries.map((entry) {
          final index = entry.key;
          final (icon, text) = entry.value;
          return Padding(
            padding: EdgeInsets.only(
              bottom: index < instructions.length - 1
                  ? Responsive.space(14)
                  : 0,
            ),
            child: Row(
              children: [
                Container(
                  width: Responsive.space(38),
                  height: Responsive.space(38),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(Responsive.radius(10)),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.blue.shade300,
                    size: Responsive.iconSize(20),
                  ),
                ),
                SizedBox(width: Responsive.space(14)),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: Responsive.sp(14).clamp(12, 16),
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
