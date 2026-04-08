import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../services/database_service.dart';
import '../services/settings_manager.dart';
import 'audio_manager.dart';
import '../widgets/pause_overlay.dart';

class PixelPongGame extends ConsumerStatefulWidget {
  final String? uid;
  const PixelPongGame({super.key, this.uid});

  @override
  ConsumerState<PixelPongGame> createState() => _PixelPongGameState();
}

class _PixelPongGameState extends ConsumerState<PixelPongGame>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // ── Cached screen size ────────────────────────────────────────────────────
  double _screenWidth = 0;
  double _screenHeight = 0;

  // ── Game constants ────────────────────────────────────────────────────────
  static const double _paddleHeight = 80;
  static const double _paddleWidth = 12;
  static const double _ballSize = 10;
  static const double _paddleMargin = 20;

  // ── Game state ────────────────────────────────────────────────────────────
  double _playerY = 0;
  double _aiY = 0;
  Offset _ballPos = Offset.zero;
  Offset _ballVel = Offset.zero;
  double _speed = 5.0;

  final ValueNotifier<int> _score = ValueNotifier(0);
  final ValueNotifier<bool> _isGameOver = ValueNotifier(false);
  final ValueNotifier<bool> _isStarted = ValueNotifier(false);
  final ValueNotifier<bool> _isPaused = ValueNotifier(false);

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
    _speed = 7.0; // Increased from 5.0 for better initial ball movement
    _playerY = _screenHeight / 2;
    _aiY = _screenHeight / 2;
    _ballPos = Offset(_screenWidth / 2, _screenHeight / 2);
    // Start ball moving toward right side (AI), with slight vertical angle
    final verticalAngle =
        (Random().nextDouble() - 0.5) * (pi / 6); // ±30 degrees vertical
    _ballVel = Offset(_speed * 0.8, _speed * sin(verticalAngle));
    AudioManager().playSfx('start.mp3');
    _controller.repeat();
  }

  void _update() {
    if (_isGameOver.value || !_isStarted.value || _isPaused.value) return;

    // Increase speed gradually as score increases
    _speed = (5.0 + _score.value * 0.2).clamp(5.0, 15.0);

    _ballPos += _ballVel;

    // Bounce off top / bottom walls with proper clamping
    if (_ballPos.dy < _ballSize) {
      _ballVel = Offset(_ballVel.dx, _ballVel.dy.abs());
      _ballPos = Offset(_ballPos.dx, _ballSize);
    } else if (_ballPos.dy > _screenHeight - _ballSize) {
      _ballVel = Offset(_ballVel.dx, -_ballVel.dy.abs());
      _ballPos = Offset(_ballPos.dx, _screenHeight - _ballSize);
    }

    // Player paddle (left)
    final playerPaddleRight = _paddleMargin + _paddleWidth;
    if (_ballVel.dx < 0 &&
        _ballPos.dx <= playerPaddleRight + _ballSize &&
        _ballPos.dx >= _paddleMargin &&
        _ballPos.dy >= _playerY - _paddleHeight / 2 &&
        _ballPos.dy <= _playerY + _paddleHeight / 2) {
      final hitOffset = (_ballPos.dy - _playerY) / (_paddleHeight / 2);
      final angle = hitOffset * (pi / 3);
      _ballVel = Offset(cos(angle).abs() * _speed, sin(angle) * _speed);
      _ballPos = Offset(playerPaddleRight + _ballSize + 1, _ballPos.dy);
    }

    // AI paddle (right)
    final aiPaddleLeft = _screenWidth - _paddleMargin - _paddleWidth;
    if (_ballVel.dx > 0 &&
        _ballPos.dx >= aiPaddleLeft - _ballSize &&
        _ballPos.dx <= _screenWidth - _paddleMargin &&
        _ballPos.dy >= _aiY - _paddleHeight / 2 &&
        _ballPos.dy <= _aiY + _paddleHeight / 2) {
      final hitOffset = (_ballPos.dy - _aiY) / (_paddleHeight / 2);
      final angle = hitOffset * (pi / 3);
      _ballVel = Offset(-cos(angle).abs() * _speed, sin(angle) * _speed);
      _ballPos = Offset(aiPaddleLeft - _ballSize - 1, _ballPos.dy);
    }

    // AI follows the ball with slight imperfection
    final aiSpeed = (3.5 + _score.value * 0.04).clamp(3.5, 9.0);
    if (_aiY < _ballPos.dy - 5) {
      _aiY = (_aiY + aiSpeed).clamp(
        _paddleHeight / 2,
        _screenHeight - _paddleHeight / 2,
      );
    } else if (_aiY > _ballPos.dy + 5) {
      _aiY = (_aiY - aiSpeed).clamp(
        _paddleHeight / 2,
        _screenHeight - _paddleHeight / 2,
      );
    }

    // Ball passed the AI — score point
    if (_ballPos.dx > _screenWidth) {
      _score.value += 10;
      _resetBall(leftward: false);
    }

    // Ball passed the player — game over
    if (_ballPos.dx < 0) {
      _gameOver();
    }
  }

  void _resetBall({required bool leftward}) {
    _ballPos = Offset(_screenWidth / 2, _screenHeight / 2);
    final angle = (Random().nextDouble() - 0.5) * 0.5;
    // Ensure velocity magnitude matches current speed
    final vx = cos(angle).abs() * _speed;
    final vy = sin(angle) * _speed;
    _ballVel = leftward ? Offset(-vx, vy) : Offset(vx, vy);
  }

  void _gameOver() {
    _isGameOver.value = true;
    AudioManager().playSfx('gameover.mp3');
    _controller.stop();
    DatabaseService(uid: widget.uid).updateScore('pixel_pong', _score.value);
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
          onVerticalDragUpdate: (details) {
            if (_isStarted.value && !_isGameOver.value && !_isPaused.value) {
              _playerY = (_playerY + details.delta.dy).clamp(
                _paddleHeight / 2,
                _screenHeight - _paddleHeight / 2,
              );
            }
          },
          onTapDown: (_) {
            if (_isPaused.value) return;
            if (!_isStarted.value || _isGameOver.value) _startGame();
          },
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).viewPadding.top,
                ),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return RepaintBoundary(
                      child: CustomPaint(
                        painter: PongPainter(
                          playerY: _playerY,
                          aiY: _aiY,
                          ballPos: _ballPos,
                          screenWidth: _screenWidth,
                          screenHeight: _screenHeight,
                          isGameOver: _isGameOver.value,
                          graphicsQuality: graphicsQuality,
                        ),
                        size: Size.infinite,
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: 12,
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
                          Shadow(color: Colors.yellowAccent, blurRadius: 15),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: _isStarted,
                builder: (context, started, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: _isGameOver,
                    builder: (context, gameOver, _) {
                      if (started && !gameOver) {
                        return const SizedBox.shrink();
                      }
                      return Center(
                        child: Container(
                          padding: const EdgeInsets.all(30),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(200),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.yellowAccent.withAlpha(100),
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                gameOver ? 'GAME OVER' : 'PIXEL PONG',
                                style: const TextStyle(
                                  color: Colors.yellowAccent,
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
                                      color: Colors.white,
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 20),
                              const Text(
                                'Drag up/down to move your paddle.\nDon\'t let the ball past!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                gameOver ? 'TAP TO RETRY' : 'TAP TO START',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
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
              Positioned(
                top: 4,
                left: 4,
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    if (_isStarted.value && !_isGameOver.value) {
                      _isPaused.value = true;
                    } else {
                      Navigator.pop(context);
                    }
                  },
                ),
              ),
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

class PongPainter extends CustomPainter {
  final double playerY;
  final double aiY;
  final Offset ballPos;
  final double screenWidth;
  final double screenHeight;
  final bool isGameOver;
  final GraphicsQuality graphicsQuality;

  static const double _paddleHeight = 80;
  static const double _paddleWidth = 12;
  static const double _ballSize = 10;
  static const double _paddleMargin = 20;

  PongPainter({
    required this.playerY,
    required this.aiY,
    required this.ballPos,
    required this.screenWidth,
    required this.screenHeight,
    required this.isGameOver,
    required this.graphicsQuality,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Center divider
    final dividerPaint = Paint()
      ..color = Colors.white.withAlpha(30)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (double y = 0; y < screenHeight; y += 20) {
      canvas.drawLine(
        Offset(screenWidth / 2, y),
        Offset(screenWidth / 2, y + 10),
        dividerPaint,
      );
    }

    final glowColor = isGameOver ? Colors.red : Colors.yellowAccent;

    // Player paddle (left)
    final playerPaint = Paint()..color = glowColor;
    if (graphicsQuality != GraphicsQuality.low) {
      playerPaint.maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        graphicsQuality == GraphicsQuality.high ? 12 : 6,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(_paddleMargin + _paddleWidth / 2, playerY),
          width: _paddleWidth,
          height: _paddleHeight,
        ),
        const Radius.circular(4),
      ),
      playerPaint,
    );

    // AI paddle (right)
    final aiPaint = Paint()..color = Colors.pinkAccent;
    if (graphicsQuality != GraphicsQuality.low) {
      aiPaint.maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        graphicsQuality == GraphicsQuality.high ? 12 : 6,
      );
    }
    final aiPaddleLeft = screenWidth - _paddleMargin - _paddleWidth;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(aiPaddleLeft + _paddleWidth / 2, aiY),
          width: _paddleWidth,
          height: _paddleHeight,
        ),
        const Radius.circular(4),
      ),
      aiPaint,
    );

    // Ball
    if (graphicsQuality == GraphicsQuality.high) {
      canvas.drawCircle(
        ballPos,
        _ballSize + 6,
        Paint()
          ..color = Colors.yellowAccent.withAlpha(60)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
      );
    }
    final ballPaint = Paint()..color = Colors.white;
    if (graphicsQuality != GraphicsQuality.low) {
      ballPaint.maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        graphicsQuality == GraphicsQuality.high ? 8 : 4,
      );
    }
    canvas.drawCircle(ballPos, _ballSize, ballPaint);
  }

  @override
  bool shouldRepaint(covariant PongPainter oldDelegate) => true;
}
