import 'dart:async';

import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';

/// Service for managing screen brightness.
/// Handles auto-brightness boost in low-light conditions.
class BrightnessService {
  static const double _lowLightThreshold = 0.3;
  static const double _boostBrightness = 1.0;

  double? _originalBrightness;
  bool _isBoosted = false;

  /// Boost brightness to maximum for better face visibility.
  Future<void> boostBrightness() async {
    if (_isBoosted) return;

    try {
      _originalBrightness = await ScreenBrightness().current;
      await ScreenBrightness().setScreenBrightness(_boostBrightness);
      _isBoosted = true;
    } on PlatformException catch (_) {
      // Brightness control not available
    }
  }

  /// Restore original brightness.
  Future<void> restoreBrightness() async {
    if (!_isBoosted) return;

    try {
      if (_originalBrightness != null) {
        await ScreenBrightness().setScreenBrightness(_originalBrightness!);
      } else {
        await ScreenBrightness().resetScreenBrightness();
      }
      _isBoosted = false;
    } on PlatformException catch (_) {
      // Brightness control not available
    }
  }

  /// Check if current ambient light is low.
  Future<bool> isLowLightEnvironment() async {
    try {
      final brightness = await ScreenBrightness().current;
      return brightness < _lowLightThreshold;
    } catch (_) {
      return false;
    }
  }

  /// Auto-boost if in low light condition.
  Future<void> autoBoostIfNeeded() async {
    if (await isLowLightEnvironment()) {
      await boostBrightness();
    }
  }

  bool get isBoosted => _isBoosted;
}
