import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum GraphicsQuality { low, medium, high }

class SettingsManager {
  static final SettingsManager _instance = SettingsManager._internal();
  factory SettingsManager() => _instance;

  SettingsManager._internal();

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

  /// Returns a safe default based on the device's available memory.
  /// Falls back to [GraphicsQuality.low] on low-RAM or unknown devices.
  static GraphicsQuality _detectDefaultQuality() {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        // ProcessInfo.currentRss gives the resident set size of the Dart VM in
        // bytes. On a 3 GB device the full process overhead leaves very little
        // headroom, so we stay on low graphics to avoid jank.
        final rss = ProcessInfo.currentRss;
        // <  80 MB already used → plenty of room → medium
        // >= 80 MB already used → conserve resources → low
        if (rss < 80 * 1024 * 1024) {
          return GraphicsQuality.medium;
        }
      }
    } catch (_) {
      // Ignore; keep low as a safe default.
    }
    return GraphicsQuality.low;
  }
}
