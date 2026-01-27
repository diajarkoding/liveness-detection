import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Utility class for responsive sizing across different screen sizes.
/// Supports both Android and iOS devices with various screen dimensions.
class Responsive {
  static late MediaQueryData _mediaQueryData;
  static late double screenWidth;
  static late double screenHeight;
  static late double blockSizeHorizontal;
  static late double blockSizeVertical;
  static late double safeAreaHorizontal;
  static late double safeAreaVertical;
  static late double safeBlockHorizontal;
  static late double safeBlockVertical;
  static late double textScaleFactor;
  static late bool isSmallScreen;
  static late bool isMediumScreen;
  static late bool isLargeScreen;

  static void init(BuildContext context) {
    _mediaQueryData = MediaQuery.of(context);
    screenWidth = _mediaQueryData.size.width;
    screenHeight = _mediaQueryData.size.height;
    blockSizeHorizontal = screenWidth / 100;
    blockSizeVertical = screenHeight / 100;

    safeAreaHorizontal =
        _mediaQueryData.padding.left + _mediaQueryData.padding.right;
    safeAreaVertical =
        _mediaQueryData.padding.top + _mediaQueryData.padding.bottom;
    safeBlockHorizontal = (screenWidth - safeAreaHorizontal) / 100;
    safeBlockVertical = (screenHeight - safeAreaVertical) / 100;

    textScaleFactor = _mediaQueryData.textScaleFactor;

    // Screen size categorization
    isSmallScreen = screenWidth < 360;
    isMediumScreen = screenWidth >= 360 && screenWidth < 400;
    isLargeScreen = screenWidth >= 400;
  }

  /// Get width as percentage of screen width
  static double wp(double percentage) {
    return blockSizeHorizontal * percentage;
  }

  /// Get height as percentage of screen height
  static double hp(double percentage) {
    return blockSizeVertical * percentage;
  }

  /// Get safe width as percentage
  static double swp(double percentage) {
    return safeBlockHorizontal * percentage;
  }

  /// Get safe height as percentage
  static double shp(double percentage) {
    return safeBlockVertical * percentage;
  }

  /// Responsive font size based on screen width
  static double sp(double size) {
    final scaleFactor = screenWidth / 375; // Base on iPhone X width
    return size * math.min(scaleFactor, 1.3); // Cap at 1.3x for large screens
  }

  /// Responsive icon size
  static double iconSize(double baseSize) {
    if (isSmallScreen) return baseSize * 0.85;
    if (isLargeScreen) return baseSize * 1.1;
    return baseSize;
  }

  /// Responsive padding
  static EdgeInsets padding({
    double? all,
    double? horizontal,
    double? vertical,
    double? left,
    double? right,
    double? top,
    double? bottom,
  }) {
    final scale = screenWidth / 375;
    final cappedScale = math.min(scale, 1.2);

    if (all != null) {
      return EdgeInsets.all(all * cappedScale);
    }

    return EdgeInsets.only(
      left: (left ?? horizontal ?? 0) * cappedScale,
      right: (right ?? horizontal ?? 0) * cappedScale,
      top: (top ?? vertical ?? 0) * cappedScale,
      bottom: (bottom ?? vertical ?? 0) * cappedScale,
    );
  }

  /// Get responsive value based on screen size
  static T value<T>({
    required T small,
    required T medium,
    required T large,
  }) {
    if (isSmallScreen) return small;
    if (isMediumScreen) return medium;
    return large;
  }

  /// Responsive border radius
  static double radius(double baseRadius) {
    final scale = screenWidth / 375;
    return baseRadius * math.min(scale, 1.2);
  }

  /// Responsive spacing (for SizedBox, margins, etc.)
  static double space(double baseSpace) {
    final scale = screenWidth / 375;
    return baseSpace * math.min(scale, 1.2);
  }
}

/// Extension for easy responsive access in widgets
extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;

  bool get isSmallScreen => screenWidth < 360;
  bool get isMediumScreen => screenWidth >= 360 && screenWidth < 400;
  bool get isLargeScreen => screenWidth >= 400;

  EdgeInsets get safePadding => MediaQuery.of(this).padding;
}
