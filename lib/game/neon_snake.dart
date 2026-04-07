import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../services/database_service.dart';
import '../services/settings_manager.dart';
import 'audio_manager.dart';
import '../widgets/pause_overlay.dart';

class NeonSnakeGame extends ConsumerStatefulWidget {
  final String? uid;
  const NeonSnakeGame({super.key, this.uid});

  @override
  ConsumerState<NeonSnakeGame> createState() => _NeonSnakeGameState();
}

class _NeonSnakeGameState extends ConsumerState<NeonSnakeGame>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // ── Grid dimensions ───────────────────────────────────────────────────────
  static const int _cols = 20;
  static const int _rows = 32;

  // ── Cached screen size ────────────────────────────────────────────────────
  double _screenWidth = 0;
  double _screenHeight = 0;
  double _cellSize = 0;

  // ── Game state ────────────────────────────────────────────────────────────
  List<Point<int>> _snake = [];
  Point<int> _food = const Point(10, 10);
  Point<int> _direction = const Point(1, 0);
  Point<int> _nextDirection = const Point(1, 0);
  int _lastMoveMs = 0;
  int _moveInterval = 200; // ms between steps

  final ValueNotifier<int> _score = ValueNotifier(0);
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
    _cellSize = min(_screenWidth / _cols, _screenHeight / _rows);
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
    _snake = [
      const Point(10, 16),
      const Point(9, 16),
      const Point(8, 16),
    ];
    _direction = const Point(1, 0);
    _nextDirection = const Point(1, 0);
    _moveInterval = 200;
    _spawnFood();
    _lastMoveMs = DateTime.now().millisecondsSinceEpoch;
    AudioManager().playSfx('start.mp3');
    _controller.repeat();
  }

  void _spawnFood() {
    Point<int> candidate;
    do {
      candidate =
          Point(_random.nextInt(_cols), _random.nextInt(_rows));
    } while (_snake.contains(candidate));
    _food = candidate;
  }

  void _update() {
    if (_isGameOver.value || !_isStarted.value || _isPaused.value) return;

    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastMoveMs < _moveInterval) return;
    _lastMoveMs = nowMs;

    // Apply queued direction (disallow 180° reversal)
    if (_nextDirection.x + _direction.x != 0 ||
        _nextDirection.y + _direction.y != 0) {
      _direction = _nextDirection;
    }

    final head = _snake.first;
    final newHead = Point(
      (head.x + _direction.x + _cols) % _cols,
      (head.y + _direction.y + _rows) % _rows,
    );

    // Self-collision
    if (_snake.contains(newHead)) {
      _gameOver();
      return;
    }

    _snake.insert(0, newHead);

    if (newHead == _food) {
      _score.value += 10;
      _moveInterval = (_moveInterval - 3).clamp(80, 200);
      _spawnFood();
    } else {
      _snake.removeLast();
    }
  }

  void _handleSwipe(DragUpdateDetails details) {
    if (!_isStarted.value || _isGameOver.value || _isPaused.value) return;
    final dx = details.delta.dx;
    final dy = details.delta.dy;
    if (dx.abs() > dy.abs()) {
      _nextDirection = dx > 0 ? const Point(1, 0) : const Point(-1, 0);
    } else {
      _nextDirection = dy > 0 ? const Point(0, 1) : const Point(0, -1);
    }
  }

  void _gameOver() {
    _isGameOver.value = true;
    AudioManager().playSfx('gameover.mp3');
    _controller.stop();
    DatabaseService(uid: widget.uid).updateScore('neon_snake', _score.value);
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
          onPanUpdate: _handleSwipe,
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
                      painter: SnakePainter(
                        snake: _snake,
                        food: _food,
                        cellSize: _cellSize,
                        cols: _cols,
                        rows: _rows,
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
                          Shadow(color: Colors.limeAccent, blurRadius: 15)
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
                                color: Colors.limeAccent.withAlpha(100),
                                width: 2),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                gameOver ? 'GAME OVER' : 'NEON SNAKE',
                                style: const TextStyle(
                                  color: Colors.limeAccent,
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
                                'Swipe to steer the snake.\nEat the glowing orbs to grow!',
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

class SnakePainter extends CustomPainter {
  final List<Point<int>> snake;
  final Point<int> food;
  final double cellSize;
  final int cols;
  final int rows;
  final bool isGameOver;
  final GraphicsQuality graphicsQuality;

  SnakePainter({
    required this.snake,
    required this.food,
    required this.cellSize,
    required this.cols,
    required this.rows,
    required this.isGameOver,
    required this.graphicsQuality,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Grid
    final gridPaint = Paint()
      ..color = Colors.white.withAlpha(8)
      ..strokeWidth = 0.5;
    for (int c = 0; c <= cols; c++) {
      canvas.drawLine(
          Offset(c * cellSize, 0), Offset(c * cellSize, rows * cellSize),
          gridPaint);
    }
    for (int r = 0; r <= rows; r++) {
      canvas.drawLine(
          Offset(0, r * cellSize), Offset(cols * cellSize, r * cellSize),
          gridPaint);
    }

    // Food
    final foodPaint = Paint()..color = Colors.redAccent;
    if (graphicsQuality != GraphicsQuality.low) {
      foodPaint.maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          graphicsQuality == GraphicsQuality.high ? 10 : 5);
    }
    canvas.drawCircle(
      Offset((food.x + 0.5) * cellSize, (food.y + 0.5) * cellSize),
      cellSize * 0.4,
      foodPaint,
    );

    // Snake segments
    final snakeColor = isGameOver ? Colors.red : Colors.limeAccent;
    for (int i = 0; i < snake.length; i++) {
      final seg = snake[i];
      final alpha =
          (255 * (1.0 - i / snake.length * 0.5).clamp(0.5, 1.0)).round();
      final segPaint = Paint()
        ..color = snakeColor.withAlpha(alpha);
      if (graphicsQuality != GraphicsQuality.low && i == 0) {
        segPaint.maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            graphicsQuality == GraphicsQuality.high ? 8 : 4);
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            seg.x * cellSize + 1,
            seg.y * cellSize + 1,
            cellSize - 2,
            cellSize - 2,
          ),
          const Radius.circular(3),
        ),
        segPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SnakePainter oldDelegate) => true;
}
