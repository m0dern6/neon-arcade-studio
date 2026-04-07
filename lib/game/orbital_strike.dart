import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../services/database_service.dart';
import '../services/settings_manager.dart';
import 'audio_manager.dart';
import '../widgets/pause_overlay.dart';

class OrbitalStrikeGame extends ConsumerStatefulWidget {
  final String? uid;
  const OrbitalStrikeGame({super.key, this.uid});

  @override
  ConsumerState<OrbitalStrikeGame> createState() => _OrbitalStrikeGameState();
}

class _OrbitalStrikeGameState extends ConsumerState<OrbitalStrikeGame>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // ── Game state ────────────────────────────────────────────────────────────
  double shieldAngle = 0;
  double shieldRotationDirection = 1.0;
  double shieldWidth = pi / 2;
  List<Enemy> enemies = [];
  double spawnRate = 2000;
  int _lastSpawnMs = 0;

  final ValueNotifier<int> _score = ValueNotifier(0);
  final ValueNotifier<bool> _isGameOver = ValueNotifier(false);
  final ValueNotifier<bool> _isStarted = ValueNotifier(false);
  final ValueNotifier<bool> _isPaused = ValueNotifier(false);

  final Random random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_update);
  }

  void _startGame() {
    _score.value = 0;
    _isGameOver.value = false;
    _isStarted.value = true;
    enemies = [];
    shieldAngle = 0;
    spawnRate = 2000;
    _lastSpawnMs = DateTime.now().millisecondsSinceEpoch;
    AudioManager().playSfx('start.mp3');
    _controller.repeat();
  }

  void _update() {
    if (_isGameOver.value || !_isStarted.value || _isPaused.value) return;

    final int score = _score.value;

    // Rotate shield
    final double rotationSpeed = 0.08 + (score * 0.002);
    shieldAngle += rotationSpeed * shieldRotationDirection;

    // Dynamic shield width
    shieldWidth = (pi / 2) - (score * 0.01).clamp(0, pi / 4);

    // Move enemies
    for (final enemy in enemies) {
      enemy.distance -= (2.0 + (score / 8) + (random.nextDouble() * (score / 20)));
    }

    _checkCollisions();

    // Spawn enemies
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastSpawnMs > spawnRate) {
      enemies.add(Enemy(angle: random.nextDouble() * 2 * pi, distance: 400));

      if (score >= 15 && random.nextDouble() < 0.2) {
        enemies.add(Enemy(
          angle: (enemies.last.angle + pi) % (2 * pi),
          distance: 450,
        ));
      }

      _lastSpawnMs = nowMs;
      if (spawnRate > 450) spawnRate -= 35;
    }
  }

  void _checkCollisions() {
    final List<Enemy> toRemove = [];
    for (final enemy in enemies) {
      if (enemy.distance < 45) {
        double normShield = shieldAngle % (2 * pi);
        double normEnemy = enemy.angle % (2 * pi);
        double diff = (normShield - normEnemy).abs();
        if (diff > pi) diff = 2 * pi - diff;

        if (diff < shieldWidth / 2) {
          _score.value++;
          toRemove.add(enemy);
          AudioManager().playSfx('hit.mp3');
        } else {
          _gameOver();
          return;
        }
      }
    }
    enemies.removeWhere(toRemove.contains);
  }

  void _gameOver() {
    _isGameOver.value = true;
    AudioManager().playSfx('gameover.mp3');
    _controller.stop();
    DatabaseService(uid: widget.uid).updateScore('orbital', _score.value);
  }

  void _onTap() {
    if (_isPaused.value) return;
    if (!_isStarted.value || _isGameOver.value) {
      _startGame();
    } else {
      shieldRotationDirection = -shieldRotationDirection;
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
        if (_isStarted.value && !_isGameOver.value) _isPaused.value = true;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D2B),
        body: GestureDetector(
          onTap: _onTap,
          child: Stack(
            children: [
              // ── Game Canvas ───────────────────────────────────────────────
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return RepaintBoundary(
                    child: CustomPaint(
                      painter: OrbitalPainter(
                        shieldAngle: shieldAngle,
                        shieldWidth: shieldWidth,
                        enemies: enemies,
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
                        shadows: [Shadow(color: Colors.pinkAccent, blurRadius: 15)],
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
                                color: Colors.pinkAccent.withAlpha(100), width: 2),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                gameOver ? 'CORE BREACHED' : 'ORBITAL STRIKE',
                                style: const TextStyle(
                                  color: Colors.pinkAccent,
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
                              Text(
                                gameOver ? 'TAP TO RETRY' : 'TAP TO DEFEND',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 16),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Tap to change shield direction',
                                style:
                                    TextStyle(color: Colors.white38, fontSize: 12),
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
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
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
                      ref.read(musicEnabledProvider.notifier).setValue(enabled);
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

class Enemy {
  double angle;
  double distance;
  Enemy({required this.angle, required this.distance});
}

class OrbitalPainter extends CustomPainter {
  final double shieldAngle;
  final double shieldWidth;
  final List<Enemy> enemies;
  final bool isGameOver;
  final GraphicsQuality graphicsQuality;

  // ── Cached Paint objects ──────────────────────────────────────────────────
  static final Paint _ringPaint = Paint()
    ..color = Colors.white.withAlpha(10)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  static final Paint _coreWhite = Paint()..color = Colors.white;

  static final Paint _enemyCore = Paint()..color = Colors.white;

  OrbitalPainter({
    required this.shieldAngle,
    required this.shieldWidth,
    required this.enemies,
    required this.isGameOver,
    required this.graphicsQuality,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Background rings
    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, i * 100.0, _ringPaint);
    }

    // Core
    final corePaint = Paint()..color = isGameOver ? Colors.red : Colors.pinkAccent;
    if (graphicsQuality != GraphicsQuality.low) {
      corePaint.maskFilter = MaskFilter.blur(BlurStyle.normal,
          graphicsQuality == GraphicsQuality.high ? 15 : 10);
      if (graphicsQuality == GraphicsQuality.high) {
        canvas.drawCircle(
          center,
          30,
          Paint()
            ..color = (isGameOver ? Colors.red : Colors.pink).withAlpha(100)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
        );
      }
    }
    canvas.drawCircle(center, 25, corePaint);
    canvas.drawCircle(center, 15, _coreWhite);

    // Shield
    final shieldPaint = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    if (graphicsQuality != GraphicsQuality.low) {
      shieldPaint.maskFilter = MaskFilter.blur(BlurStyle.normal,
          graphicsQuality == GraphicsQuality.high ? 8 : 5);
      if (graphicsQuality == GraphicsQuality.high) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: 45),
          shieldAngle - shieldWidth / 2,
          shieldWidth,
          false,
          Paint()
            ..color = Colors.cyanAccent.withAlpha(100)
            ..strokeWidth = 12
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
        );
      }
    }

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 45),
      shieldAngle - shieldWidth / 2,
      shieldWidth,
      false,
      shieldPaint,
    );

    // Shield inner line
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 45),
      shieldAngle - shieldWidth / 2,
      shieldWidth,
      false,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // Enemies
    final enemyPaint = Paint()..color = Colors.amberAccent;
    if (graphicsQuality != GraphicsQuality.low) {
      enemyPaint.maskFilter = MaskFilter.blur(BlurStyle.normal,
          graphicsQuality == GraphicsQuality.high ? 6 : 4);
    }

    for (final enemy in enemies) {
      final ex = center.dx + cos(enemy.angle) * enemy.distance;
      final ey = center.dy + sin(enemy.angle) * enemy.distance;
      canvas.drawCircle(Offset(ex, ey), 8, enemyPaint);
      canvas.drawCircle(Offset(ex, ey), 4, _enemyCore);

      canvas.drawLine(
        Offset(ex, ey),
        Offset(
          center.dx + cos(enemy.angle) * (enemy.distance + 20),
          center.dy + sin(enemy.angle) * (enemy.distance + 20),
        ),
        Paint()
          ..color = Colors.amber.withAlpha(100)
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant OrbitalPainter old) {
    return old.shieldAngle != shieldAngle ||
        old.shieldWidth != shieldWidth ||
        old.isGameOver != isGameOver ||
        old.graphicsQuality != graphicsQuality ||
        old.enemies.length != enemies.length;
  }
}
