import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum GraphicsQuality { low, medium, high }

class SettingsManager {
  static final SettingsManager _instance = SettingsManager._internal();
  factory SettingsManager() => _instance;

  SettingsManager._internal();

  // Default to low until init() completes; also acts as a safe fallback for
  // any synchronous access that might happen before the async init finishes.
  GraphicsQuality _graphicsQuality = GraphicsQuality.low;

  GraphicsQuality get graphicsQuality => _graphicsQuality;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // If the user has never set a quality preference, auto-detect a safe default.
    if (!prefs.containsKey('graphics_quality')) {
      _graphicsQuality = _detectDefaultQuality();
      await prefs.setInt('graphics_quality', _graphicsQuality.index);
    } else {
      final qualityIndex = prefs.getInt('graphics_quality') ?? GraphicsQuality.low.index;
      _graphicsQuality = GraphicsQuality.values[qualityIndex];
    }
  }

  Future<void> setGraphicsQuality(GraphicsQuality quality) async {
    _graphicsQuality = quality;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('graphics_quality', quality.index);
  }

  /// Returns a safe default based on the platform.
  /// On Android (the most common low-end target), we default to [GraphicsQuality.low]
  /// to ensure smooth gameplay on devices like the Samsung Galaxy A20.
  /// Users can always raise the quality through the in-game pause menu.
  static GraphicsQuality _detectDefaultQuality() {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        return GraphicsQuality.low;
      }
    } catch (_) {
      // Ignore; keep low as a safe default.
    }
    return GraphicsQuality.medium;
  }
}
