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
    final qualityIndex = prefs.getInt('graphics_quality') ?? 0;
    _graphicsQuality = GraphicsQuality.values[qualityIndex];
  }

  Future<void> setGraphicsQuality(GraphicsQuality quality) async {
    _graphicsQuality = quality;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('graphics_quality', quality.index);
  }
}
