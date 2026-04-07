import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/settings_manager.dart';
import '../game/audio_manager.dart';

// ---------------------------------------------------------------------------
// Graphics quality provider
// Backed by SettingsManager so changes are persisted automatically.
// ---------------------------------------------------------------------------

class GraphicsQualityNotifier extends Notifier<GraphicsQuality> {
  @override
  GraphicsQuality build() => SettingsManager().graphicsQuality;

  void cycle() {
    final next = GraphicsQuality.values[(state.index + 1) % GraphicsQuality.values.length];
    state = next;
    SettingsManager().setGraphicsQuality(next);
  }

  void set(GraphicsQuality quality) {
    if (state == quality) return;
    state = quality;
    SettingsManager().setGraphicsQuality(quality);
  }
}

final graphicsQualityProvider =
    NotifierProvider<GraphicsQualityNotifier, GraphicsQuality>(
  GraphicsQualityNotifier.new,
);

// ---------------------------------------------------------------------------
// Audio state providers
// These are simple toggles backed by the AudioManager singleton.
// ---------------------------------------------------------------------------

final musicEnabledProvider = StateNotifierProvider<_BoolNotifier, bool>(
  (ref) => _BoolNotifier(AudioManager().isMusicEnabled),
);

final sfxEnabledProvider = StateNotifierProvider<_BoolNotifier, bool>(
  (ref) => _BoolNotifier(AudioManager().isSfxEnabled),
);

class _BoolNotifier extends StateNotifier<bool> {
  _BoolNotifier(super.initial);

  void toggle() => state = !state;
  // ignore: use_setters_to_change_properties
  void setValue(bool v) => state = v;
}
