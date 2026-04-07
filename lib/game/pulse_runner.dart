import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../services/database_service.dart';
import '../services/settings_manager.dart';
import 'audio_manager.dart';
import '../widgets/pause_overlay.dart';

class PulseRunnerGame extends ConsumerStatefulWidget {
  final String? uid;
  const PulseRunnerGame({super.key, this.uid});

  @override
  ConsumerState<PulseRunnerGame> createState() => _PulseRunnerGameState();
}

class _PulseRunnerGameState extends ConsumerState<PulseRunnerGame>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // ── Cached screen size ────────────────────────────────────────────────────
  double _screenWidth = 0;
  double _screenHeight = 0;

  // ── Game constants ────────────────────────────────────────────────────────
  static const double _playerX = 80;
  static const double _playerSize = 24;
  static const double _gravity = 0.7;
  static const double _jumpVelocity = -13.0;
  static const double _groundFraction = 0.75;

  // ── Game state ────────────────────────────────────────────────────────────
  double _playerY = 0;
  double _playerVelY = 0;
  bool _isOnGround = true;
  List<_RunnerObstacle> _obstacles = [];
  double _speed = 5.0;
  int _lastSpawnMs = 0;
  int _frameCount = 0;

  final ValueNotifier<int> _score = ValueNotifier(0);
  final ValueNotifier<bool> _isGameOver = ValueNotifier(false);
  final ValueNotifier<bool> _isStarted = ValueNotifier(false);
  final ValueNotifier<bool> _isPaused = ValueNotifier(false);

  final Random _random = Random();

  double get _groundY => _screenHeight * _groundFraction;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.of(context).size;
    _screenWidth = size.width;
    _screenHeight = size.height;
    _playerY = _groundY;
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(_update);
  }

  void _startGame() {
    _score.value = 0;
    _isGameOver.value = false;
    _isStarted.value = true;
    _playerY = _groundY;
    _playerVelY = 0;
    _isOnGround = true;
    _obstacles = [];
    _speed = 5.0;
    _frameCount = 0;
    _lastSpawnMs = DateTime.now().millisecondsSinceEpoch;
    AudioManager().playSfx('start.mp3');
    _controller.repeat();
  }

  void _jump() {
    if (_isOnGround &&
        _isStarted.value &&
        !_isGameOver.value &&
        !_isPaused.value) {
      _playerVelY = _jumpVelocity;
      _isOnGround = false;
    }
  }

  void _update() {
    if (_isGameOver.value || !_isStarted.value || _isPaused.value) return;

    _frameCount++;

    // Apply gravity
    _playerVelY += _gravity;
    _playerY += _playerVelY;
    if (_playerY >= _groundY) {
      _playerY = _groundY;
      _playerVelY = 0;
      _isOnGround = true;
    }

    // Move obstacles
    for (final obs in _obstacles) {
      obs.x -= _speed;
    }
    _obstacles.removeWhere((o) => o.x < -60);

    // Spawn obstacles
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final double spawnInterval = (1600 / (_speed / 5)).clamp(600, 2200);
    if (nowMs - _lastSpawnMs > spawnInterval) {
      final double h = 30 + _random.nextDouble() * 44;
      _obstacles.add(_RunnerObstacle(
        x: _screenWidth + 20,
        y: _groundY - h,
        width: 18 + _random.nextDouble() * 16,
        height: h,
      ));
      _lastSpawnMs = nowMs;
    }

    // Ramp up speed every 300 frames
    if (_frameCount % 300 == 0) {
      _speed = (_speed + 0.5).clamp(5.0, 18.0);
    }

    // Score based on frames survived
    _score.value = _frameCount ~/ 6;

    // Collision detection
    final playerRect = Rect.fromCenter(
      center: Offset(_playerX, _playerY),
      width: _playerSize,
      height: _playerSize,
    );
    for (final obs in _obstacles) {
      final obsRect = Rect.fromLTWH(obs.x, obs.y, obs.width, obs.height);
      if (playerRect.overlaps(obsRect.deflate(3))) {
        _gameOver();
        return;
      }
    }
  }

  void _gameOver() {
    _isGameOver.value = true;
    AudioManager().playSfx('gameover.mp3');
    _controller.stop();
    DatabaseService(uid: widget.uid)
        .updateScore('pulse_runner', _score.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    _score.dispose();
    _isGameOver.dispose();
    _isStarted.dispose();
    _isPaused.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final graphicsQuality = ref.watch(graphicsQualityProvider);

    return PopScope(
      canPop: _isGameOver.value || !_isStarted.value,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isStarted.value && !_isGameOver.value) _isPaused.value = true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D2B),
        body: GestureDetector(
          onTapDown: (_) {
            if (_isPaused.value) return;
            if (!_isStarted.value || _isGameOver.value) {
              _startGame();
            } else {
              _jump();
            }
          },
          child: Stack(
            children: [
              // ── Game Canvas ───────────────────────────────────────────────
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return RepaintBoundary(
                    child: CustomPaint(
                      painter: RunnerPainter(
                        playerX: _playerX,
                        playerY: _playerY,
                        obstacles: _obstacles,
                        groundY: _groundY,
                        isGameOver: _isGameOver.value,
                        graphicsQuality: graphicsQuality,
                      ),
                      size: Size.infinite,
                    ),
                  );
                },
              ),

              // ── Score ─────────────────────────────────────────────────────
              Positioned(
                top: 60,
                left: 0,
                right: 0,
                child: Center(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _score,
                    builder: (context, score, _) => Text(
                      '$score',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        shadows: [
                          Shadow(
                              color: Colors.orangeAccent, blurRadius: 15)
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Start / Game-over overlay ─────────────────────────────────
              ValueListenableBuilder<bool>(
                valueListenable: _isStarted,
                builder: (context, started, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: _isGameOver,
                    builder: (context, gameOver, _) {
                      if (started && !gameOver) return const SizedBox.shrink();
                      return Center(
                        child: Container(
                          padding: const EdgeInsets.all(30),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(200),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.orangeAccent.withAlpha(100),
                                width: 2),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                gameOver ? 'CRASHED' : 'PULSE RUNNER',
                                style: const TextStyle(
                                  color: Colors.orangeAccent,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (gameOver)
                                ValueListenableBuilder<int>(
                                  valueListenable: _score,
                                  builder: (context, score, _) => Text(
                                    'Score: $score',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 20),
                                  ),
                                ),
                              const SizedBox(height: 20),
                              const Text(
                                'Tap to jump over obstacles.\nSurvive as long as you can!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 14),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                gameOver ? 'TAP TO RETRY' : 'TAP TO START',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),

              // ── Back Button ───────────────────────────────────────────────
              Positioned(
                top: 50,
                left: 20,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white),
                  onPressed: () {
                    if (_isStarted.value && !_isGameOver.value) {
                      _isPaused.value = true;
                    } else {
                      Navigator.pop(context);
                    }
                  },
                ),
              ),

              // ── Pause overlay ─────────────────────────────────────────────
              ValueListenableBuilder<bool>(
                valueListenable: _isPaused,
                builder: (context, paused, _) {
                  if (!paused) return const SizedBox.shrink();
                  return PauseOverlay(
                    onResume: () => _isPaused.value = false,
                    onHome: () => Navigator.pop(context),
                    onToggleMusic: () {
                      final enabled = !AudioManager().isMusicEnabled;
                      AudioManager().toggleMusic(enabled);
                      ref
                          .read(musicEnabledProvider.notifier)
                          .setValue(enabled);
                    },
                    onToggleSfx: () {
                      final enabled = !AudioManager().isSfxEnabled;
                      AudioManager().toggleSfx(enabled);
                      ref.read(sfxEnabledProvider.notifier).setValue(enabled);
                    },
                    onToggleGraphics: () =>
                        ref.read(graphicsQualityProvider.notifier).cycle(),
                    isMusicEnabled: ref.read(musicEnabledProvider),
                    isSfxEnabled: ref.read(sfxEnabledProvider),
                    graphicsQuality: graphicsQuality,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunnerObstacle {
  double x;
  final double y;
  final double width;
  final double height;

  _RunnerObstacle({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

class RunnerPainter extends CustomPainter {
  final double playerX;
  final double playerY;
  final List<_RunnerObstacle> obstacles;
  final double groundY;
  final bool isGameOver;
  final GraphicsQuality graphicsQuality;

  static const double _playerSize = 24;

  RunnerPainter({
    required this.playerX,
    required this.playerY,
    required this.obstacles,
    required this.groundY,
    required this.isGameOver,
    required this.graphicsQuality,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Ground line
    canvas.drawLine(
      Offset(0, groundY + _playerSize / 2),
      Offset(size.width, groundY + _playerSize / 2),
      Paint()
        ..color = Colors.orangeAccent.withAlpha(120)
        ..strokeWidth = 2,
    );

    // Player
    final playerColor = isGameOver ? Colors.red : Colors.orangeAccent;
    final playerPaint = Paint()..color = playerColor;
    if (graphicsQuality != GraphicsQuality.low) {
      playerPaint.maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          graphicsQuality == GraphicsQuality.high ? 12 : 6);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(playerX, playerY),
          width: _playerSize,
          height: _playerSize,
        ),
        const Radius.circular(4),
      ),
      playerPaint,
    );

    // Obstacles
    final obsPaint = Paint()..color = Colors.cyanAccent;
    if (graphicsQuality != GraphicsQuality.low) {
      obsPaint.maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          graphicsQuality == GraphicsQuality.high ? 8 : 4);
    }
    for (final obs in obstacles) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(obs.x, obs.y, obs.width, obs.height),
          const Radius.circular(4),
        ),
        obsPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant RunnerPainter oldDelegate) => true;
}
