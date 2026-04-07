import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../services/database_service.dart';
import '../services/settings_manager.dart';
import 'audio_manager.dart';
import '../widgets/pause_overlay.dart';

class NeonBounceGame extends ConsumerStatefulWidget {
  final String? uid;
  const NeonBounceGame({super.key, this.uid});

  @override
  ConsumerState<NeonBounceGame> createState() => _NeonBounceGameState();
}

class _NeonBounceGameState extends ConsumerState<NeonBounceGame>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // ── Cached screen size ────────────────────────────────────────────────────
  double _screenWidth = 0;
  double _screenHeight = 0;

  // ── Game constants ────────────────────────────────────────────────────────
  static const double _paddleWidth = 100;
  static const double _paddleHeight = 14;
  static const double _ballRadius = 8;
  static const int _brickCols = 8;
  static const int _brickRows = 4;
  static const double _brickH = 22;
  static const double _brickOffsetY = 120;

  // ── Game state ────────────────────────────────────────────────────────────
  double _paddleX = 0;
  Offset _ballPos = Offset.zero;
  Offset _ballVel = Offset.zero;
  List<List<bool>> _bricks = [];
  double _ballSpeed = 6.0;

  final ValueNotifier<int> _score = ValueNotifier(0);
  final ValueNotifier<bool> _isGameOver = ValueNotifier(false);
  final ValueNotifier<bool> _isStarted = ValueNotifier(false);
  final ValueNotifier<bool> _isPaused = ValueNotifier(false);

  double get _paddleTopY => _screenHeight - 80;

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

  void _initBricks() {
    _bricks = List.generate(
      _brickRows,
      (_) => List.generate(_brickCols, (_) => true),
    );
  }

  void _startGame() {
    _score.value = 0;
    _isGameOver.value = false;
    _isStarted.value = true;
    _ballSpeed = 6.0;
    _paddleX = _screenWidth / 2;
    _ballPos = Offset(_screenWidth / 2, _screenHeight / 2);
    final angle = -pi / 2 + (Random().nextDouble() - 0.5) * 0.6;
    _ballVel =
        Offset(cos(angle) * _ballSpeed, sin(angle) * _ballSpeed);
    _initBricks();
    AudioManager().playSfx('start.mp3');
    _controller.repeat();
  }

  void _resetLevel() {
    _ballSpeed = (_ballSpeed + 0.6).clamp(6.0, 14.0);
    _ballPos = Offset(_screenWidth / 2, _screenHeight / 2);
    final angle = -pi / 2 + (Random().nextDouble() - 0.5) * 0.6;
    _ballVel =
        Offset(cos(angle) * _ballSpeed, sin(angle) * _ballSpeed);
    _initBricks();
  }

  void _update() {
    if (_isGameOver.value || !_isStarted.value || _isPaused.value) return;

    _ballPos += _ballVel;

    // Wall bounces (left / right)
    if (_ballPos.dx <= _ballRadius) {
      _ballVel = Offset(_ballVel.dx.abs(), _ballVel.dy);
      _ballPos = Offset(_ballRadius, _ballPos.dy);
    } else if (_ballPos.dx >= _screenWidth - _ballRadius) {
      _ballVel = Offset(-_ballVel.dx.abs(), _ballVel.dy);
      _ballPos = Offset(_screenWidth - _ballRadius, _ballPos.dy);
    }

    // Ceiling bounce
    if (_ballPos.dy <= _ballRadius) {
      _ballVel = Offset(_ballVel.dx, _ballVel.dy.abs());
      _ballPos = Offset(_ballPos.dx, _ballRadius);
    }

    // Paddle collision
    final paddleLeft = _paddleX - _paddleWidth / 2;
    final paddleTop = _paddleTopY;
    if (_ballVel.dy > 0 &&
        _ballPos.dy >= paddleTop - _ballRadius &&
        _ballPos.dy <= paddleTop + _paddleHeight &&
        _ballPos.dx >= paddleLeft &&
        _ballPos.dx <= paddleLeft + _paddleWidth) {
      final hitOffset =
          (_ballPos.dx - _paddleX) / (_paddleWidth / 2);
      final angle = -pi / 2 + hitOffset * (pi / 3);
      _ballVel = Offset(
          cos(angle) * _ballSpeed, sin(angle) * _ballSpeed);
      _ballPos =
          Offset(_ballPos.dx, paddleTop - _ballRadius - 1);
    }

    // Brick collisions
    final brickW = _screenWidth / _brickCols;
    bool hitAny = false;
    for (int row = 0; row < _brickRows && !hitAny; row++) {
      for (int col = 0; col < _brickCols && !hitAny; col++) {
        if (!_bricks[row][col]) continue;
        final bLeft = col * brickW + 2;
        final bTop = _brickOffsetY + row * (_brickH + 6);
        final bRect = Rect.fromLTWH(bLeft, bTop, brickW - 4, _brickH);

        if (bRect.inflate(_ballRadius).contains(_ballPos)) {
          _bricks[row][col] = false;
          _score.value += 10;
          hitAny = true;

          // Reflect on the dominant axis
          final closestX =
              _ballPos.dx.clamp(bRect.left, bRect.right);
          final closestY =
              _ballPos.dy.clamp(bRect.top, bRect.bottom);
          final diffX = _ballPos.dx - closestX;
          final diffY = _ballPos.dy - closestY;
          if (diffX.abs() > diffY.abs()) {
            _ballVel = Offset(-_ballVel.dx, _ballVel.dy);
          } else {
            _ballVel = Offset(_ballVel.dx, -_ballVel.dy);
          }
        }
      }
    }

    // Check all bricks cleared → next level
    if (_bricks.every((row) => row.every((b) => !b))) {
      _resetLevel();
    }

    // Ball fell off the bottom → game over
    if (_ballPos.dy > _screenHeight + _ballRadius) {
      _gameOver();
    }
  }

  void _gameOver() {
    _isGameOver.value = true;
    AudioManager().playSfx('gameover.mp3');
    _controller.stop();
    DatabaseService(uid: widget.uid)
        .updateScore('neon_bounce', _score.value);
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
          onHorizontalDragUpdate: (details) {
            if (_isStarted.value && !_isGameOver.value && !_isPaused.value) {
              _paddleX = (_paddleX + details.delta.dx).clamp(
                  _paddleWidth / 2, _screenWidth - _paddleWidth / 2);
            }
          },
          onTapDown: (_) {
            if (_isPaused.value) return;
            if (!_isStarted.value || _isGameOver.value) _startGame();
          },
          child: Stack(
            children: [
              // ── Game Canvas ───────────────────────────────────────────────
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return RepaintBoundary(
                    child: CustomPaint(
                      painter: BouncePainter(
                        paddleX: _paddleX,
                        paddleTopY: _paddleTopY,
                        ballPos: _ballPos,
                        bricks: _bricks,
                        screenWidth: _screenWidth,
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
                              color: Colors.deepPurpleAccent,
                              blurRadius: 15)
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
                                color: Colors.deepPurpleAccent.withAlpha(100),
                                width: 2),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                gameOver ? 'BALL LOST' : 'NEON BOUNCE',
                                style: const TextStyle(
                                  color: Colors.deepPurpleAccent,
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
                                'Drag left/right to move the paddle.\nBreak all the neon bricks!',
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

class BouncePainter extends CustomPainter {
  final double paddleX;
  final double paddleTopY;
  final Offset ballPos;
  final List<List<bool>> bricks;
  final double screenWidth;
  final bool isGameOver;
  final GraphicsQuality graphicsQuality;

  static const double _paddleWidth = 100;
  static const double _paddleHeight = 14;
  static const double _ballRadius = 8;
  static const double _brickH = 22;
  static const double _brickOffsetY = 120;
  static const int _brickCols = 8;

  static const List<Color> _brickColors = [
    Colors.redAccent,
    Colors.orangeAccent,
    Colors.yellowAccent,
    Colors.greenAccent,
  ];

  BouncePainter({
    required this.paddleX,
    required this.paddleTopY,
    required this.ballPos,
    required this.bricks,
    required this.screenWidth,
    required this.isGameOver,
    required this.graphicsQuality,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final brickW = screenWidth / _brickCols;

    // Draw bricks
    for (int row = 0; row < bricks.length; row++) {
      for (int col = 0; col < bricks[row].length; col++) {
        if (!bricks[row][col]) continue;
        final bLeft = col * brickW + 2;
        final bTop = _brickOffsetY + row * (_brickH + 6);
        final color = _brickColors[row % _brickColors.length];
        final brickPaint = Paint()..color = color;
        if (graphicsQuality != GraphicsQuality.low) {
          brickPaint.maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              graphicsQuality == GraphicsQuality.high ? 6 : 3);
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(bLeft, bTop, brickW - 4, _brickH),
            const Radius.circular(4),
          ),
          brickPaint,
        );
      }
    }

    // Draw paddle
    final paddlePaint = Paint()
      ..color = isGameOver ? Colors.red : Colors.deepPurpleAccent;
    if (graphicsQuality != GraphicsQuality.low) {
      paddlePaint.maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          graphicsQuality == GraphicsQuality.high ? 12 : 6);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          paddleX - _paddleWidth / 2,
          paddleTopY,
          _paddleWidth,
          _paddleHeight,
        ),
        const Radius.circular(6),
      ),
      paddlePaint,
    );

    // Draw ball
    if (graphicsQuality == GraphicsQuality.high) {
      canvas.drawCircle(
        ballPos,
        _ballRadius + 6,
        Paint()
          ..color = Colors.purpleAccent.withAlpha(80)
          ..maskFilter =
              const MaskFilter.blur(BlurStyle.normal, 15),
      );
    }
    final ballPaint = Paint()..color = Colors.white;
    if (graphicsQuality != GraphicsQuality.low) {
      ballPaint.maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          graphicsQuality == GraphicsQuality.high ? 8 : 4);
    }
    canvas.drawCircle(ballPos, _ballRadius, ballPaint);
  }

  @override
  bool shouldRepaint(covariant BouncePainter oldDelegate) => true;
}
