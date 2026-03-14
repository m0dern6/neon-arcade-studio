import 'package:audioplayers/audioplayers.dart';

class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;

  AudioManager._internal() {
    // Set global context to allow mixing (prevents one sound from cutting off another)
    // This solves the issue of background music stopping when sounds play.
    AudioPlayer.global.setAudioContext(
      AudioContext(
        android: AudioContextAndroid(
          usageType: AndroidUsageType.game,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.ambient, // Ambient allows mixing
        ),
      ),
    );

    // Pre-initialize a pool for SFX to prevent lags and memory leaks
    for (int i = 0; i < _poolSize; i++) {
      _sfxPool.add(AudioPlayer());
    }
  }

  final AudioPlayer _musicPlayer = AudioPlayer();
  final List<AudioPlayer> _sfxPool = [];
  final int _poolSize = 5; // Increased pool to handle faster games
  int _poolIndex = 0;

  String? _currentMusicFile;

  bool _isMusicEnabled = true;
  bool _isSfxEnabled = true;

  bool get isMusicEnabled => _isMusicEnabled;
  bool get isSfxEnabled => _isSfxEnabled;

  Future<void> playMusic(String fileName) async {
    _currentMusicFile = fileName;
    if (!_isMusicEnabled) return;

    // Safety check: if it's already playing, just ensure it's not paused
    if (_musicPlayer.state == PlayerState.playing &&
        _currentMusicFile == fileName)
      return;

    try {
      await _musicPlayer.setReleaseMode(ReleaseMode.loop);
      await _musicPlayer.play(AssetSource('audio/$fileName'));
    } catch (e) {
      print("Error playing music: $e");
    }
  }

  Future<void> pauseMusic() async {
    await _musicPlayer.pause();
  }

  Future<void> resumeMusic() async {
    if (_isMusicEnabled && _currentMusicFile != null) {
      await _musicPlayer.resume();
    }
  }

  Future<void> stopMusic() async {
    await _musicPlayer.stop();
  }

  Future<void> playSfx(String fileName) async {
    if (!_isSfxEnabled) return;

    try {
      // Pick next player in pool (Round-robin)
      final player = _sfxPool[_poolIndex];
      _poolIndex = (_poolIndex + 1) % _poolSize;

      // Ensure we don't 'stack' too many async play calls on one player
      if (player.state == PlayerState.playing) {
        await player.stop();
      }

      await player.play(AssetSource('audio/$fileName'), volume: 0.5);
    } catch (e) {
      print("Error playing SFX: $e");
    }
  }

  void toggleMusic(bool enabled) {
    _isMusicEnabled = enabled;
    if (!enabled) {
      stopMusic();
    } else if (_currentMusicFile != null) {
      playMusic(_currentMusicFile!);
    }
  }

  void toggleSfx(bool enabled) {
    _isSfxEnabled = enabled;
    if (!enabled) {
      // Immediately stop all active SFX in the pool
      for (var player in _sfxPool) {
        player.stop();
      }
    }
  }

  // Call this if needed for a full cleanup
  void dispose() {
    _musicPlayer.dispose();
    for (var player in _sfxPool) {
      player.dispose();
    }
  }
}
