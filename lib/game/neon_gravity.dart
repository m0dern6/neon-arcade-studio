import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../services/database_service.dart';
import '../services/settings_manager.dart';
import 'audio_manager.dart';
import '../widgets/pause_overlay.dart';

class NeonGravityGame extends ConsumerStatefulWidget {
  final String? uid;
  const NeonGravityGame({super.key, this.uid});

  @override
  ConsumerState<NeonGravityGame> createState() => _NeonGravityGameState();
}

class _NeonGravityGameState extends ConsumerState<NeonGravityGame>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // ── Game state (mutated directly by _update; no setState needed per frame) ──
  double playerY = 0;
  double playerTargetY = 1;
  double playerX = 50;
  List<Offset> trail = [];
  List<Obstacle> obstacles = [];
  double speed = 5.0;
  int _lastObstacleMs = 0;

  // ── Cached screen size ────────────────────────────────────────────────────
  double _screenWidth = 0;
  double _screenHeight = 0;

  // ── ValueNotifiers drive only the widgets that need to react ──────────────
  final ValueNotifier<int> _score = ValueNotifier(0);
  final ValueNotifier<bool> _isGameOver = ValueNotifier(false);
  final ValueNotifier<bool> _isStarted = ValueNotifier(false);
  final ValueNotifier<bool> _isPaused = ValueNotifier(false);

  final Random random = Random();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.of(context).size;
    _screenWidth = size.width;
    _screenHeight = size.height;
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
    playerY = 1;
    playerTargetY = 1;
    obstacles = [];
    trail = [];
    speed = 5.0;
    _lastObstacleMs = DateTime.now().millisecondsSinceEpoch;
    AudioManager().playSfx('start.mp3');
    _controller.repeat();
  }

  void _update() {
    if (_isGameOver.value || !_isStarted.value || _isPaused.value) return;

    // Smooth player movement
    playerY += (playerTargetY - playerY) * 0.15;

    // Update trail
    const laneOffset = 80.0;
    final pY = (_screenHeight / 2) + (playerY * laneOffset);
    trail.insert(0, Offset(playerX, pY));
    if (trail.length > 15) trail.removeLast();

    // Move obstacles
    final int level = (_score.value / 10).floor();
    final double dynamicSpeed = speed + (level * 0.8);
    for (final obs in obstacles) {
      obs.x -= dynamicSpeed;
    }

    // Remove off-screen obstacles and update score
    int scored = 0;
    obstacles.removeWhere((obs) {
      if (obs.x < -40) {
        scored++;
        return true;
      }
      return false;
    });
    if (scored > 0) _score.value += scored;

    // Spawn new obstacles
    final double spawnInterval = (1600 / (1 + (level * 0.25))).clamp(400, 2000);
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastObstacleMs > spawnInterval) {
      obstacles.add(Obstacle(x: _screenWidth + 50, isTop: random.nextBool()));

      // Rare double-obstacle for level 2+
      if (level >= 2 && random.nextDouble() < (level * 0.08).clamp(0, 0.4)) {
        obstacles.add(Obstacle(
          x: _screenWidth + 180,
          isTop: !obstacles.last.isTop,
        ));
      }
      _lastObstacleMs = nowMs;
    }

    _checkCollision();
  }

  void _checkCollision() {
    final double pX = playerX;
    final double pY = (_screenHeight / 2) + (playerY * 80);

    for (final obs in obstacles) {
      final double dx = (pX - obs.x).abs();
      final double dy = (pY - ((_screenHeight / 2) + (obs.isTop ? -80 : 80))).abs();
      if (dx < 40 && dy < 30) {
        _gameOver();
        break;
      }
    }
  }

  void _gameOver() {
    _isGameOver.value = true;
    AudioManager().playSfx('gameover.mp3');
    _controller.stop();
    DatabaseService(uid: widget.uid).updateScore('neon_gravity', _score.value);
  }

  void _onTap() {
    if (_isPaused.value) return;
    if (!_isStarted.value || _isGameOver.value) {
      _startGame();
    } else {
      playerTargetY = -playerTargetY;
      AudioManager().playSfx('jump.mp3');
    }
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
        if (_isStarted.value && !_isGameOver.value) {
          _isPaused.value = true;
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D2B),
        body: GestureDetector(
          onTap: _onTap,
          child: Stack(
            children: [
              // ── Game Canvas (repaints only on animation tick) ─────────────
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return RepaintBoundary(
                    child: CustomPaint(
                      painter: NeonPainter(
                        playerY: playerY,
                        playerX: playerX,
                        obstacles: obstacles,
                        graphicsQuality: graphicsQuality,
                        trail: trail,
                        animationValue: _controller.value,
                      ),
                      size: Size.infinite,
                    ),
                  );
                },
              ),

              // ── Score (rebuilds only when score changes) ──────────────────
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
                        shadows: [Shadow(color: Colors.cyan, blurRadius: 10)],
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 40, vertical: 30),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D0D2B).withAlpha(220),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: (gameOver
                                      ? Colors.redAccent
                                      : Colors.cyanAccent)
                                  .withAlpha(150),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (gameOver
                                        ? Colors.redAccent
                                        : Colors.cyanAccent)
                                    .withAlpha(40),
                                blurRadius: 30,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                gameOver ? Icons.error_outline : Icons.bolt,
                                color: gameOver
                                    ? Colors.redAccent
                                    : Colors.cyanAccent,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                gameOver ? 'SYSTEM FAILURE' : 'NEON GRAVITY',
                                style: TextStyle(
                                  color: gameOver
                                      ? Colors.redAccent
                                      : Colors.cyanAccent,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                ),
                              ),
                              if (gameOver) ...[
                                const SizedBox(height: 8),
                                ValueListenableBuilder<int>(
                                  valueListenable: _score,
                                  builder: (context, score, _) => Text(
                                    'Score: $score',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 24),
                              Text(
                                gameOver
                                    ? 'TAP TO RETRY'
                                    : 'TAP TO INITIALIZE',
                                style: TextStyle(
                                  color: Colors.white.withAlpha(180),
                                  fontSize: 14,
                                  letterSpacing: 4,
                                  fontWeight: FontWeight.w500,
                                ),
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
                      ref
                          .read(sfxEnabledProvider.notifier)
                          .setValue(enabled);
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

class Obstacle {
  double x;
  bool isTop;
  Obstacle({required this.x, required this.isTop});
}

class NeonPainter extends CustomPainter {
  final double playerY;
  final double playerX;
  final List<Obstacle> obstacles;
  final GraphicsQuality graphicsQuality;
  final List<Offset> trail;
  final double animationValue;

  // ── Cached Paint objects ──────────────────────────────────────────────────
  static final Paint _gridPaint = Paint()
    ..color = Colors.cyan.withAlpha(20)
    ..strokeWidth = 1;

  static final Paint _laneCorePaint = Paint()
    ..color = Colors.white.withAlpha(180)
    ..strokeWidth = 1.5;

  static final Paint _obsCoreStroke = Paint()
    ..color = Colors.white.withAlpha(200)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  static final Paint _playerBodyPaint = Paint()..color = Colors.cyanAccent;
  static final Paint _playerCorePaint = Paint()..color = Colors.white;

  static final Paint _speedLinePaint = Paint()
    ..color = Colors.white.withAlpha(40)
    ..strokeWidth = 1.2;

  NeonPainter({
    required this.playerY,
    required this.playerX,
    required this.obstacles,
    required this.graphicsQuality,
    required this.trail,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    const laneOffset = 80.0;
    // Use animationValue to drive time-based effects without DateTime allocation.
    final double time = animationValue * 1000;

    // ── 0. Moving Grid Background ─────────────────────────────────────────
    final double offsetX = (time * 0.1) % 40;
    for (double x = -offsetX; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), _gridPaint);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), _gridPaint);
    }

    // ── 1. Lane Glow / Core Lines ─────────────────────────────────────────
    final laneGlowPaint = Paint()
      ..color = Colors.cyan.withAlpha(100)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    if (graphicsQuality != GraphicsQuality.low) {
      laneGlowPaint.maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        graphicsQuality == GraphicsQuality.high ? 4 : 2,
      );
      if (graphicsQuality == GraphicsQuality.high) {
        final broadGlow = Paint()
          ..color = Colors.cyan.withAlpha(40)
          ..strokeWidth = 12
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
        canvas.drawLine(Offset(0, centerY - laneOffset - 20),
            Offset(size.width, centerY - laneOffset - 20), broadGlow);
        canvas.drawLine(Offset(0, centerY + laneOffset + 20),
            Offset(size.width, centerY + laneOffset + 20), broadGlow);
      }
    }

    canvas.drawLine(Offset(0, centerY - laneOffset - 20),
        Offset(size.width, centerY - laneOffset - 20), laneGlowPaint);
    canvas.drawLine(Offset(0, centerY - laneOffset - 20),
        Offset(size.width, centerY - laneOffset - 20), _laneCorePaint);
    canvas.drawLine(Offset(0, centerY + laneOffset + 20),
        Offset(size.width, centerY + laneOffset + 20), laneGlowPaint);
    canvas.drawLine(Offset(0, centerY + laneOffset + 20),
        Offset(size.width, centerY + laneOffset + 20), _laneCorePaint);

    // ── 2. Obstacles ──────────────────────────────────────────────────────
    final obsPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;

    if (graphicsQuality != GraphicsQuality.low) {
      obsPaint.maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        graphicsQuality == GraphicsQuality.high ? 8 : 4,
      );
    }

    for (final obs in obstacles) {
      final oY = centerY + (obs.isTop ? -laneOffset - 20 : laneOffset + 20);
      final path = Path();
      if (obs.isTop) {
        path.moveTo(obs.x - 20, oY);
        path.lineTo(obs.x + 20, oY);
        path.lineTo(obs.x, oY + 35);
      } else {
        path.moveTo(obs.x - 20, oY);
        path.lineTo(obs.x + 20, oY);
        path.lineTo(obs.x, oY - 35);
      }
      path.close();
      canvas.drawPath(path, obsPaint);
      canvas.drawPath(path, _obsCoreStroke);

      if (graphicsQuality == GraphicsQuality.high) {
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.red.withAlpha(60)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 10
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
        );
      }
    }

    // ── 3. Player Trail ───────────────────────────────────────────────────
    if (graphicsQuality != GraphicsQuality.low) {
      for (int i = 0; i < trail.length; i++) {
        final opacity = (1.0 - (i / trail.length)) * 0.5;
        canvas.drawCircle(
          trail[i],
          15.0 * (1.0 - (i / trail.length)),
          Paint()
            ..color = Colors.cyanAccent.withOpacity(opacity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }
    }

    // ── 4. Player ─────────────────────────────────────────────────────────
    final pY = centerY + (playerY * laneOffset);
    final playerRect =
        Rect.fromCenter(center: Offset(playerX, pY), width: 32, height: 32);

    if (graphicsQuality != GraphicsQuality.low) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(playerRect.inflate(4), const Radius.circular(8)),
        Paint()
          ..color = Colors.cyanAccent.withAlpha(80)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal,
              graphicsQuality == GraphicsQuality.high ? 15 : 8),
      );
    }

    canvas.drawRRect(
        RRect.fromRectAndRadius(playerRect, const Radius.circular(6)),
        _playerBodyPaint);
    canvas.drawRRect(
        RRect.fromRectAndRadius(playerRect.deflate(6), const Radius.circular(4)),
        _playerCorePaint);

    // ── 5. Speed Lines ────────────────────────────────────────────────────
    for (int i = 0; i < 8; i++) {
      final double lx = (time * 0.4 + i * 200) % size.width;
      final double ly =
          (i * size.height / 8 + (sin(time * 0.001 + i) * 20)) % size.height;
      canvas.drawLine(Offset(size.width - lx, ly),
          Offset(size.width - lx - 40, ly), _speedLinePaint);
    }
  }

  @override
  bool shouldRepaint(covariant NeonPainter old) {
    return old.playerY != playerY ||
        old.playerX != playerX ||
        old.animationValue != animationValue ||
        old.graphicsQuality != graphicsQuality ||
        old.obstacles.length != obstacles.length ||
        old.trail.length != trail.length;
  }
}
