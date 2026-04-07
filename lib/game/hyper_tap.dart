import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../services/database_service.dart';
import '../services/settings_manager.dart';
import 'audio_manager.dart';
import '../widgets/pause_overlay.dart';

class HyperTapGame extends ConsumerStatefulWidget {
  final String? uid;
  const HyperTapGame({super.key, this.uid});

  @override
  ConsumerState<HyperTapGame> createState() => _HyperTapGameState();
}

class _HyperTapGameState extends ConsumerState<HyperTapGame>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // ── Cached screen size ────────────────────────────────────────────────────
  double _screenWidth = 0;
  double _screenHeight = 0;

  // ── Game constants ────────────────────────────────────────────────────────
  static const int _maxLives = 3;
  static const double _initialLifespan = 2000;
  static const double _lifespanDecreasePerPoint = 4.0;
  static const double _minLifespan = 700;
  static const double _initialSpawnInterval = 1200;

  // ── Game state ────────────────────────────────────────────────────────────
  List<_TapTarget> _targets = [];
  int _lives = _maxLives;
  double _spawnInterval = _initialSpawnInterval;
  int _lastSpawnMs = 0;

  final ValueNotifier<int> _score = ValueNotifier(0);
  final ValueNotifier<int> _livesNotifier = ValueNotifier(_maxLives);
  final ValueNotifier<bool> _isGameOver = ValueNotifier(false);
  final ValueNotifier<bool> _isStarted = ValueNotifier(false);
  final ValueNotifier<bool> _isPaused = ValueNotifier(false);

  final Random _random = Random();

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
    _lives = _maxLives;
    _livesNotifier.value = _maxLives;
    _isGameOver.value = false;
    _isStarted.value = true;
    _targets = [];
    _spawnInterval = _initialSpawnInterval;
    _lastSpawnMs = DateTime.now().millisecondsSinceEpoch;
    AudioManager().playSfx('start.mp3');
    _controller.repeat();
  }

  void _update() {
    if (_isGameOver.value || !_isStarted.value || _isPaused.value) return;

    final int nowMs = DateTime.now().millisecondsSinceEpoch;

    // Update progress and remove expired targets
    bool lostLife = false;
    _targets.removeWhere((t) {
      t.progress = (nowMs - t.spawnMs) / t.lifespan;
      if (t.progress >= 1.0) {
        lostLife = true;
        return true;
      }
      return false;
    });

    if (lostLife) {
      _lives--;
      _livesNotifier.value = _lives;
      if (_lives <= 0) {
        _gameOver();
        return;
      }
    }

    // Spawn new target
    if (nowMs - _lastSpawnMs > _spawnInterval) {
      const double padding = 70;
      final double lifespan =
          (_initialLifespan - _score.value * _lifespanDecreasePerPoint)
              .clamp(_minLifespan, _initialLifespan);
      _targets.add(_TapTarget(
        pos: Offset(
          padding + _random.nextDouble() * (_screenWidth - padding * 2),
          padding + _random.nextDouble() * (_screenHeight - padding * 2),
        ),
        spawnMs: nowMs,
        lifespan: lifespan,
        maxRadius: 28 + _random.nextDouble() * 22,
      ));
      _lastSpawnMs = nowMs;
      _spawnInterval = (_spawnInterval - 12).clamp(380, 1200);
    }
  }

  void _handleTap(Offset position) {
    if (!_isStarted.value || _isGameOver.value || _isPaused.value) return;
    for (int i = _targets.length - 1; i >= 0; i--) {
      final t = _targets[i];
      final radius = t.maxRadius * (1 - t.progress);
      if ((position - t.pos).distance < radius) {
        _targets.removeAt(i);
        _score.value += ((10 * (1 - t.progress)) + 5).round();
        return;
      }
    }
  }

  void _gameOver() {
    _isGameOver.value = true;
    AudioManager().playSfx('gameover.mp3');
    _controller.stop();
    DatabaseService(uid: widget.uid).updateScore('hyper_tap', _score.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    _score.dispose();
    _livesNotifier.dispose();
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
          onTapDown: (details) {
            if (_isPaused.value) return;
            if (!_isStarted.value || _isGameOver.value) {
              _startGame();
            } else {
              _handleTap(details.localPosition);
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
                      painter: HyperTapPainter(
                        targets: _targets,
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
                              color: Colors.amberAccent, blurRadius: 15)
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Lives ─────────────────────────────────────────────────────
              Positioned(
                top: 62,
                right: 20,
                child: ValueListenableBuilder<int>(
                  valueListenable: _livesNotifier,
                  builder: (context, lives, _) => Row(
                    children: List.generate(
                      3,
                      (i) => Icon(
                        Icons.favorite,
                        color: i < lives
                            ? Colors.amberAccent
                            : Colors.white.withAlpha(50),
                        size: 20,
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
                                color: Colors.amberAccent.withAlpha(100),
                                width: 2),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                gameOver ? 'TOO SLOW' : 'HYPER TAP',
                                style: const TextStyle(
                                  color: Colors.amberAccent,
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
                                'Tap the glowing circles before they vanish.\nMiss 3 and it\'s over!',
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

class _TapTarget {
  final Offset pos;
  final int spawnMs;
  final double lifespan;
  final double maxRadius;
  double progress;

  _TapTarget({
    required this.pos,
    required this.spawnMs,
    required this.lifespan,
    required this.maxRadius,
    this.progress = 0,
  });
}

class HyperTapPainter extends CustomPainter {
  final List<_TapTarget> targets;
  final bool isGameOver;
  final GraphicsQuality graphicsQuality;

  HyperTapPainter({
    required this.targets,
    required this.isGameOver,
    required this.graphicsQuality,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final t in targets) {
      final radius = t.maxRadius * (1 - t.progress);
      final alpha = (1 - t.progress).clamp(0.0, 1.0);
      final color =
          Color.lerp(Colors.amberAccent, Colors.redAccent, t.progress)!;

      if (graphicsQuality == GraphicsQuality.high) {
        canvas.drawCircle(
          t.pos,
          radius + 8,
          Paint()
            ..color = color.withAlpha((60 * alpha).round())
            ..maskFilter =
                const MaskFilter.blur(BlurStyle.normal, 20),
        );
      }

      final ringPaint = Paint()
        ..color = color.withAlpha((200 * alpha).round())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      if (graphicsQuality != GraphicsQuality.low) {
        ringPaint.maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            graphicsQuality == GraphicsQuality.high ? 8 : 4);
      }
      canvas.drawCircle(t.pos, radius, ringPaint);
      canvas.drawCircle(
        t.pos,
        radius * 0.3,
        Paint()..color = color.withAlpha((180 * alpha).round()),
      );
    }
  }

  @override
  bool shouldRepaint(covariant HyperTapPainter oldDelegate) => true;
}
