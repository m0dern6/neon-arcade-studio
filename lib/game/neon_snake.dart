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
  int _moveInterval = 200; // ms between grid steps

  // Smooth interpolation: fraction (0-1) between the last step and the next
  double _stepFraction = 0.0;

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
    _snake = [const Point(10, 16), const Point(9, 16), const Point(8, 16)];
    _direction = const Point(1, 0);
    _nextDirection = const Point(1, 0);
    _moveInterval = 200;
    _stepFraction = 0.0;
    _spawnFood();
    _lastMoveMs = DateTime.now().millisecondsSinceEpoch;
    AudioManager().playSfx('start.mp3');
    _controller.repeat();
  }

  void _spawnFood() {
    Point<int> candidate;
    do {
      candidate = Point(_random.nextInt(_cols), _random.nextInt(_rows));
    } while (_snake.contains(candidate));
    _food = candidate;
  }

  void _update() {
    if (_isGameOver.value || !_isStarted.value || _isPaused.value) return;

    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    final int elapsed = nowMs - _lastMoveMs;

    // Update smooth interpolation fraction (drives animation between steps)
    _stepFraction = (elapsed / _moveInterval).clamp(0.0, 1.0);

    if (elapsed < _moveInterval) return; // not yet time for next grid step
    _lastMoveMs = nowMs;
    _stepFraction = 0.0;

    // Apply queued direction (prevent 180° reversal)
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
      _setDirection(dx > 0 ? const Point(1, 0) : const Point(-1, 0));
    } else {
      _setDirection(dy > 0 ? const Point(0, 1) : const Point(0, -1));
    }
  }

  void _setDirection(Point<int> direction) {
    if (!_isStarted.value || _isGameOver.value || _isPaused.value) return;
    if (direction.x + _direction.x == 0 && direction.y + _direction.y == 0) {
      return;
    }
    _nextDirection = direction;
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
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).viewPadding.top,
            ),
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
                          stepFraction: _stepFraction,
                          direction: _direction,
                        ),
                        size: Size.infinite,
                      ),
                    );
                  },
                ),

                // ── Score ─────────────────────────────────────────────────────
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
                            Shadow(color: Colors.limeAccent, blurRadius: 15),
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
                        if (started && !gameOver)
                          return const SizedBox.shrink();
                        return Center(
                          child: Container(
                            padding: const EdgeInsets.all(30),
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(200),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.limeAccent.withAlpha(100),
                                width: 2,
                              ),
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
                                        color: Colors.white,
                                        fontSize: 20,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 20),
                                const Text(
                                  'Swipe to steer the snake.\nEat the glowing orbs to grow!',
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

                // ── Back Button ───────────────────────────────────────────────
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Snake Painter — smooth movement + realistic snake appearance
// ─────────────────────────────────────────────────────────────────────────────
class SnakePainter extends CustomPainter {
  final List<Point<int>> snake;
  final Point<int> food;
  final double cellSize;
  final int cols;
  final int rows;
  final bool isGameOver;
  final GraphicsQuality graphicsQuality;
  final double stepFraction;
  final Point<int> direction;

  SnakePainter({
    required this.snake,
    required this.food,
    required this.cellSize,
    required this.cols,
    required this.rows,
    required this.isGameOver,
    required this.graphicsQuality,
    required this.stepFraction,
    required this.direction,
  });

  // Center of a grid cell in pixel space
  Offset _gridCenter(Point<int> p) =>
      Offset((p.x + 0.5) * cellSize, (p.y + 0.5) * cellSize);

  // True when two grid points are on opposite sides of a wrap boundary
  bool _isWrapping(Point<int> a, Point<int> b) =>
      (a.x - b.x).abs() > cols ~/ 2 || (a.y - b.y).abs() > rows ~/ 2;

  // Compute smooth pixel positions for every snake segment
  List<Offset> _computePositions() {
    final List<Offset> out = [];
    for (int i = 0; i < snake.length; i++) {
      if (i == 0) {
        // Head moves from its current cell toward the next cell
        final from = _gridCenter(snake[0]);
        final nextGrid = Point(
          (snake[0].x + direction.x + cols) % cols,
          (snake[0].y + direction.y + rows) % rows,
        );
        if (_isWrapping(snake[0], nextGrid)) {
          out.add(from);
        } else {
          out.add(Offset.lerp(from, _gridCenter(nextGrid), stepFraction)!);
        }
      } else {
        // Each body segment follows the one ahead of it
        final behind = _gridCenter(snake[i]);
        final ahead = _gridCenter(snake[i - 1]);
        if (_isWrapping(snake[i], snake[i - 1])) {
          out.add(behind);
        } else {
          out.add(Offset.lerp(behind, ahead, stepFraction)!);
        }
      }
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (snake.isEmpty) return;

    final positions = _computePositions();
    final r = cellSize * 0.38; // body half-width

    _drawFood(canvas);
    _drawBody(canvas, positions, r);
    if (positions.length >= 2) _drawTail(canvas, positions, r);
    _drawHead(canvas, positions, r);
  }

  // ── Food ──────────────────────────────────────────────────────────────────
  void _drawFood(Canvas canvas) {
    final center =
        Offset((food.x + 0.5) * cellSize, (food.y + 0.5) * cellSize);
    final fr = cellSize * 0.3;

    if (graphicsQuality != GraphicsQuality.low) {
      canvas.drawCircle(
        center,
        fr * 2.0,
        Paint()
          ..color = Colors.pinkAccent.withAlpha(55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
    canvas.drawCircle(center, fr, Paint()..color = Colors.pinkAccent);
    // Highlight
    canvas.drawCircle(
      center - Offset(fr * 0.28, fr * 0.28),
      fr * 0.32,
      Paint()..color = Colors.white.withAlpha(200),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────
  void _drawBody(Canvas canvas, List<Offset> positions, double r) {
    if (positions.length < 2) return;

    const baseColor = Color(0xFF1A5E20);
    const darkColor = Color(0xFF0D3311);
    final scaleColor =
        isGameOver ? Colors.orangeAccent : Colors.limeAccent;
    final tubeColor = isGameOver ? const Color(0xFF8B0000) : baseColor;

    // Connecting tubes (drawn before circles so circles sit on top)
    final tubePaint = Paint()
      ..color = tubeColor
      ..strokeWidth = r * 1.75
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 1; i < positions.length; i++) {
      canvas.drawLine(positions[i], positions[i - 1], tubePaint);
    }

    // Segment circles with scale detail (tail → neck)
    for (int i = positions.length - 1; i >= 1; i--) {
      final isTail = i == positions.length - 1;
      final segR = isTail ? r * 0.5 : r * 0.9;

      // Darken toward the tail for depth
      final t = positions.length > 2
          ? i / (positions.length - 1).toDouble()
          : 0.0;
      final segColor = isGameOver
          ? Color.lerp(const Color(0xFF8B0000), const Color(0xFF5C0000), t)!
          : Color.lerp(baseColor, darkColor, t)!;

      canvas.drawCircle(positions[i], segR, Paint()..color = segColor);

      // Scale arcs on non-tail, non-neck segments
      if (!isTail && i < positions.length - 1) {
        _drawScaleArcs(
          canvas,
          positions[i],
          positions[i - 1],
          positions[i + 1],
          segR,
          scaleColor,
        );
      }
    }
  }

  // Small arcs on each body segment to suggest scales
  void _drawScaleArcs(
    Canvas canvas,
    Offset pos,
    Offset ahead,
    Offset behind,
    double r,
    Color scaleColor,
  ) {
    final forward = ahead - behind;
    final dist = forward.distance;
    if (dist < 0.001) return;
    final norm = forward / dist;

    final scalePaint = Paint()
      ..color = scaleColor.withAlpha(80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(atan2(norm.dy, norm.dx));

    // Two scale arcs per segment (top and bottom)
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(0, -r * 0.38), width: r * 1.5, height: r * 0.95),
      pi * 0.15,
      pi * 0.7,
      false,
      scalePaint,
    );
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(0, r * 0.38), width: r * 1.5, height: r * 0.95),
      -pi * 0.85,
      pi * 0.7,
      false,
      scalePaint,
    );
    canvas.restore();
  }

  // ── Pointed tail ─────────────────────────────────────────────────────────
  void _drawTail(Canvas canvas, List<Offset> positions, double r) {
    final tail = positions.last;
    final preTail = positions[positions.length - 2];
    final dir = tail - preTail;
    final dist = dir.distance;
    if (dist < 0.001) return;

    final norm = dir / dist;
    final perp = Offset(-norm.dy, norm.dx);
    final tailColor =
        isGameOver ? const Color(0xFF8B0000) : const Color(0xFF1A5E20);

    final path = Path()
      ..moveTo((tail + norm * r * 1.1).dx, (tail + norm * r * 1.1).dy)
      ..lineTo(
          (tail - norm * r * 0.2 + perp * r * 0.5).dx,
          (tail - norm * r * 0.2 + perp * r * 0.5).dy)
      ..lineTo(
          (tail - norm * r * 0.2 - perp * r * 0.5).dx,
          (tail - norm * r * 0.2 - perp * r * 0.5).dy)
      ..close();

    canvas.drawPath(path, Paint()..color = tailColor);
  }

  // ── Head with eyes, tongue, nostrils ────────────────────────────────────
  void _drawHead(Canvas canvas, List<Offset> positions, double r) {
    final headPos = positions[0];
    final dirNorm =
        Offset(direction.x.toDouble(), direction.y.toDouble());
    final perpDir = Offset(-dirNorm.dy, dirNorm.dx);

    final headColor =
        isGameOver ? Colors.redAccent : Colors.cyanAccent;
    final headDark =
        isGameOver ? const Color(0xFF8B0000) : const Color(0xFF005522);
    final headR = r * 1.15;

    // Soft glow behind the head
    if (graphicsQuality != GraphicsQuality.low) {
      canvas.drawCircle(
        headPos,
        headR * 1.6,
        Paint()
          ..color = headColor.withAlpha(35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }

    // Head shape — elongated oval in movement direction
    canvas.save();
    canvas.translate(headPos.dx, headPos.dy);
    canvas.rotate(atan2(dirNorm.dy, dirNorm.dx));

    // Shadow/dark base
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset.zero, width: headR * 2.3, height: headR * 1.8),
      Paint()..color = headDark,
    );
    // Bright overlay
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(headR * 0.05, 0),
          width: headR * 2.1,
          height: headR * 1.65),
      Paint()..color = headColor,
    );

    // Nostril dots
    final nostrilPaint = Paint()..color = Colors.black.withAlpha(200);
    canvas.drawCircle(Offset(headR * 0.72, -r * 0.24), r * 0.11, nostrilPaint);
    canvas.drawCircle(Offset(headR * 0.72, r * 0.24), r * 0.11, nostrilPaint);

    canvas.restore();

    // Eyes (world space so they rotate with direction correctly)
    final eyeCenter1 = headPos + dirNorm * r * 0.45 + perpDir * r * 0.52;
    final eyeCenter2 = headPos + dirNorm * r * 0.45 - perpDir * r * 0.52;
    final eyeR = r * 0.27;
    final pupilR = eyeR * 0.56;

    canvas.drawCircle(eyeCenter1, eyeR, Paint()..color = Colors.white);
    canvas.drawCircle(eyeCenter2, eyeR, Paint()..color = Colors.white);

    final pupilShift = dirNorm * eyeR * 0.18;
    canvas.drawCircle(
        eyeCenter1 + pupilShift, pupilR, Paint()..color = Colors.black);
    canvas.drawCircle(
        eyeCenter2 + pupilShift, pupilR, Paint()..color = Colors.black);

    // Eye shine
    final shineOff = -dirNorm * eyeR * 0.15 - perpDir * eyeR * 0.05;
    canvas.drawCircle(eyeCenter1 + shineOff, eyeR * 0.22,
        Paint()..color = Colors.white.withAlpha(210));
    canvas.drawCircle(eyeCenter2 + shineOff, eyeR * 0.22,
        Paint()..color = Colors.white.withAlpha(210));

    // Tongue (forked) — only when alive
    if (!isGameOver) {
      final tongueBase = headPos + dirNorm * headR * 1.05;
      final tongueMid = tongueBase + dirNorm * r * 0.5;
      final fork1 = tongueMid + dirNorm * r * 0.38 + perpDir * r * 0.3;
      final fork2 = tongueMid + dirNorm * r * 0.38 - perpDir * r * 0.3;

      final tonguePaint = Paint()
        ..color = Colors.red.shade400
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawLine(tongueBase, tongueMid, tonguePaint);
      canvas.drawLine(tongueMid, fork1, tonguePaint);
      canvas.drawLine(tongueMid, fork2, tonguePaint);
    }
  }

  @override
  bool shouldRepaint(covariant SnakePainter oldDelegate) => true;
}
