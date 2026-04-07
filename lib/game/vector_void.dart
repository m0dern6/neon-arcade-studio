import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../services/database_service.dart';
import '../services/settings_manager.dart';
import 'audio_manager.dart';
import '../widgets/pause_overlay.dart';

class VectorVoidGame extends ConsumerStatefulWidget {
  final String? uid;
  const VectorVoidGame({super.key, this.uid});

  @override
  ConsumerState<VectorVoidGame> createState() => _VectorVoidGameState();
}

class _VectorVoidGameState extends ConsumerState<VectorVoidGame>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // ── Game state ────────────────────────────────────────────────────────────
  Offset playerPos = Offset.zero;
  List<VoidEnemy> enemies = [];
  double speedFactor = 1.0;
  int _lastSpawnMs = 0;
  int _lastMoveMs = 0;

  // ── Cached screen size ────────────────────────────────────────────────────
  double _screenWidth = 0;
  double _screenHeight = 0;

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
    enemies = [];
    speedFactor = 1.0;
    playerPos = Offset(_screenWidth / 2, _screenHeight / 2);
    _lastSpawnMs = DateTime.now().millisecondsSinceEpoch;
    _lastMoveMs = DateTime.now().millisecondsSinceEpoch;
    AudioManager().playSfx('start.mp3');
    _controller.repeat();
  }

  void _update() {
    if (_isGameOver.value || !_isStarted.value || _isPaused.value) return;

    for (final enemy in enemies) {
      enemy.pos += Offset(enemy.dir.dx * enemy.speed, enemy.dir.dy * enemy.speed);
    }

    enemies.removeWhere((e) =>
        e.pos.dx < -50 ||
        e.pos.dx > _screenWidth + 50 ||
        e.pos.dy < -50 ||
        e.pos.dy > _screenHeight + 50);

    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final double spawnInterval = (1200 / speedFactor).clamp(300, 1500);
    if (nowMs - _lastSpawnMs > spawnInterval) {
      enemies.add(_createEnemy(nowMs));
      _lastSpawnMs = nowMs;
      speedFactor += 0.01;
      _score.value += 10;
    }

    for (final enemy in enemies) {
      if ((enemy.pos - playerPos).distance < 25) {
        _gameOver();
        return;
      }
    }
  }

  VoidEnemy _createEnemy(int nowMs) {
    final double side = random.nextDouble();
    Offset pos;
    if (side < 0.25) {
      pos = Offset(random.nextDouble() * _screenWidth, -30);
    } else if (side < 0.5) {
      pos = Offset(random.nextDouble() * _screenWidth, _screenHeight + 30);
    } else if (side < 0.75) {
      pos = Offset(-30, random.nextDouble() * _screenHeight);
    } else {
      pos = Offset(_screenWidth + 30, random.nextDouble() * _screenHeight);
    }

    final bool isPlayerStatic = nowMs - _lastMoveMs >= 3000;
    final Offset target = isPlayerStatic
        ? playerPos
        : Offset(
            _screenWidth / 2 + (random.nextDouble() - 0.5) * 100,
            _screenHeight / 2 + (random.nextDouble() - 0.5) * 100,
          );

    Offset dir = target - pos;
    dir = Offset(dir.dx / dir.distance, dir.dy / dir.distance);

    return VoidEnemy(
      pos: pos,
      dir: dir,
      speed: (3.0 + random.nextDouble() * 2) *
          speedFactor *
          (isPlayerStatic ? 1.5 : 1.0),
      color: isPlayerStatic ? Colors.orangeAccent : Colors.greenAccent,
    );
  }

  void _gameOver() {
    _isGameOver.value = true;
    AudioManager().playSfx('gameover.mp3');
    _controller.stop();
    DatabaseService(uid: widget.uid).updateScore('vector_void', _score.value);
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
          onPanUpdate: (details) {
            if (_isStarted.value && !_isGameOver.value && !_isPaused.value) {
              playerPos += details.delta;
              _lastMoveMs = DateTime.now().millisecondsSinceEpoch;
            }
          },
          onTapDown: (_) {
            if (_isPaused.value) return;
            if (!_isStarted.value || _isGameOver.value) _startGame();
          },
          child: Stack(
            children: [
              // ── Static grid (does not repaint every frame) ────────────────
              const RepaintBoundary(
                child: CustomPaint(
                  painter: GridPainter(),
                  size: Size.infinite,
                ),
              ),

              // ── Game Canvas ───────────────────────────────────────────────
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return RepaintBoundary(
                    child: CustomPaint(
                      painter: VoidPainter(
                        playerPos: playerPos,
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
                        fontFamily: 'monospace',
                        shadows: [
                          Shadow(color: Colors.greenAccent, blurRadius: 15)
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
                                color: Colors.greenAccent.withAlpha(100),
                                width: 2),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                gameOver ? 'VOIDED' : 'VECTOR VOID',
                                style: const TextStyle(
                                  color: Colors.greenAccent,
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
                                'Drag to dodge incoming vectors.\nSurvive the void!',
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

class VoidEnemy {
  Offset pos;
  Offset dir;
  double speed;
  Color color;
  VoidEnemy({
    required this.pos,
    required this.dir,
    required this.speed,
    required this.color,
  });
}

/// Static background grid — painted once and cached by the compositor.
class GridPainter extends CustomPainter {
  const GridPainter();

  static final Paint _paint = Paint()
    ..color = Colors.white.withAlpha(5)
    ..strokeWidth = 1;

  @override
  void paint(Canvas canvas, Size size) {
    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), _paint);
    }
    for (double i = 0; i < size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), _paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class VoidPainter extends CustomPainter {
  final Offset playerPos;
  final List<VoidEnemy> enemies;
  final bool isGameOver;
  final GraphicsQuality graphicsQuality;

  // ── Cached Paint objects ──────────────────────────────────────────────────
  static final Paint _playerWhite = Paint()..color = Colors.white;

  VoidPainter({
    required this.playerPos,
    required this.enemies,
    required this.isGameOver,
    required this.graphicsQuality,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final playerPaint = Paint()
      ..color = isGameOver ? Colors.red : Colors.greenAccent;

    if (graphicsQuality != GraphicsQuality.low) {
      playerPaint.maskFilter = MaskFilter.blur(BlurStyle.normal,
          graphicsQuality == GraphicsQuality.high ? 15 : 10);
    }

    if (graphicsQuality == GraphicsQuality.high) {
      canvas.drawCircle(
        playerPos,
        18,
        Paint()
          ..color =
              (isGameOver ? Colors.red : Colors.greenAccent).withAlpha(100)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 25),
      );
    }

    canvas.drawCircle(playerPos, 15, playerPaint);
    canvas.drawCircle(playerPos, 8, _playerWhite);

    for (final enemy in enemies) {
      final curEnemyPaint = Paint()
        ..color = enemy.color.withAlpha(150)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      if (graphicsQuality != GraphicsQuality.low) {
        curEnemyPaint.maskFilter = MaskFilter.blur(BlurStyle.normal,
            graphicsQuality == GraphicsQuality.high ? 8 : 3);
      }

      final path = Path()
        ..moveTo(enemy.pos.dx, enemy.pos.dy - 10)
        ..lineTo(enemy.pos.dx + 8, enemy.pos.dy + 8)
        ..lineTo(enemy.pos.dx - 8, enemy.pos.dy + 8)
        ..close();

      if (graphicsQuality == GraphicsQuality.high) {
        canvas.drawPath(
          path,
          Paint()
            ..color = enemy.color.withAlpha(50)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
        );
      }

      canvas.drawPath(path, curEnemyPaint);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withAlpha(50)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant VoidPainter old) {
    return old.playerPos != playerPos ||
        old.isGameOver != isGameOver ||
        old.graphicsQuality != graphicsQuality ||
        old.enemies.length != enemies.length;
  }
}
