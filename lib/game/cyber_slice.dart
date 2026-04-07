import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../services/database_service.dart';
import '../services/settings_manager.dart';
import 'audio_manager.dart';
import '../widgets/pause_overlay.dart';

class CyberSliceGame extends ConsumerStatefulWidget {
  final String? uid;
  const CyberSliceGame({super.key, this.uid});

  @override
  ConsumerState<CyberSliceGame> createState() => _CyberSliceGameState();
}

class _CyberSliceGameState extends ConsumerState<CyberSliceGame>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random random = Random();

  // ── Game state ────────────────────────────────────────────────────────────
  List<SliceNode> activeNodes = [];
  List<Offset> swipePath = [];
  int _lastSpawnMs = 0;

  // ── Cached screen size ────────────────────────────────────────────────────
  double _screenWidth = 0;
  double _screenHeight = 0;

  final ValueNotifier<int> _score = ValueNotifier(0);
  final ValueNotifier<int> _combo = ValueNotifier(0);
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
    _combo.value = 0;
    _isGameOver.value = false;
    _isStarted.value = true;
    activeNodes = [];
    swipePath = [];
    _lastSpawnMs = DateTime.now().millisecondsSinceEpoch;
    AudioManager().playSfx('start.mp3');
    _controller.repeat();
  }

  void _update() {
    if (_isGameOver.value || !_isStarted.value || _isPaused.value) return;

    for (final node in activeNodes) {
      node.update();
    }

    activeNodes.removeWhere((node) {
      if (node.isOffScreen) {
        if (!node.isSliced && !node.isBomb) {
          _combo.value = 0;
        }
        return true;
      }
      return false;
    });

    final int score = _score.value;
    final double spawnInterval = (1200 / (1 + (score / 500))).clamp(400, 1500);
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastSpawnMs > spawnInterval) {
      _spawnNode();
      _lastSpawnMs = nowMs;
    }
  }

  void _spawnNode() {
    activeNodes.add(SliceNode(
      position: Offset(
        50 + random.nextDouble() * (_screenWidth - 100),
        _screenHeight + 50,
      ),
      velocity: Offset(
        (random.nextDouble() - 0.5) * 4,
        -8 - random.nextDouble() * 6,
      ),
      type: random.nextDouble() < 0.15 ? NodeType.bomb : NodeType.shape,
      shape: ShapeType.values[random.nextInt(ShapeType.values.length)],
      color: _getRandomNeonColor(),
    ));
  }

  Color _getRandomNeonColor() {
    const colors = [
      Colors.cyanAccent,
      Colors.pinkAccent,
      Colors.yellowAccent,
      Colors.purpleAccent,
      Colors.greenAccent,
    ];
    return colors[random.nextInt(colors.length)];
  }

  void _handlePanStart(DragStartDetails details) {
    if (!_isStarted.value || _isGameOver.value || _isPaused.value) return;
    swipePath = [details.localPosition];
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!_isStarted.value || _isGameOver.value || _isPaused.value) return;
    final pos = details.localPosition;
    swipePath.add(pos);
    if (swipePath.length > 10) swipePath.removeAt(0);

    for (final node in activeNodes) {
      if (!node.isSliced && (node.position - pos).distance < 45) {
        _sliceNode(node);
      }
    }
  }

  void _handlePanEnd(DragEndDetails _) {
    swipePath = [];
  }

  void _sliceNode(SliceNode node) {
    if (node.isBomb) {
      _gameOver();
      return;
    }
    node.isSliced = true;
    final combo = _combo.value;
    _score.value += 10 * (1 + combo ~/ 5);
    _combo.value = combo + 1;
    AudioManager().playSfx('hit.mp3');
  }

  void _gameOver() {
    _isGameOver.value = true;
    swipePath = [];
    AudioManager().playSfx('gameover.mp3');
    _controller.stop();
    DatabaseService(uid: widget.uid).updateScore('pulse_dash', _score.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    _score.dispose();
    _combo.dispose();
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
          onPanStart: _handlePanStart,
          onPanUpdate: _handlePanUpdate,
          onPanEnd: _handlePanEnd,
          onTapDown: (_) {
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
                      painter: SlicePainter(
                        nodes: activeNodes,
                        swipePath: swipePath,
                        graphicsQuality: graphicsQuality,
                      ),
                      size: Size.infinite,
                    ),
                  );
                },
              ),

              // ── Score / Combo ─────────────────────────────────────────────
              Positioned(
                top: 60,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: _score,
                      builder: (context, score, _) => Text(
                        '$score',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          shadows: [
                            Shadow(color: Colors.cyanAccent, blurRadius: 15)
                          ],
                        ),
                      ),
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: _combo,
                      builder: (context, combo, _) {
                        if (combo <= 1) return const SizedBox.shrink();
                        return Text(
                          'COMBO X${combo ~/ 5 + 1}',
                          style: const TextStyle(
                              color: Colors.yellowAccent,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                  ],
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
                                color: Colors.cyanAccent.withAlpha(100),
                                width: 2),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                gameOver ? 'CORE BREACHED' : 'CYBER SLICE',
                                style: const TextStyle(
                                    color: Colors.cyanAccent,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2),
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
                                'Swipe to slice neon nodes.\nAvoid the red data bombs!',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                gameOver ? 'TAP TO RETRY' : 'TAP TO START',
                                style: const TextStyle(
                                    color: Colors.white,
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

enum NodeType { shape, bomb }

enum ShapeType { square, triangle, circle }

class SliceNode {
  Offset position;
  Offset velocity;
  NodeType type;
  ShapeType shape;
  Color color;
  bool isSliced = false;
  double rotation = 0;
  final double rotationSpeed;

  SliceNode({
    required this.position,
    required this.velocity,
    required this.type,
    required this.shape,
    required this.color,
  }) : rotationSpeed = (Random().nextDouble() - 0.5) * 0.2;

  void update() {
    position += velocity;
    velocity = Offset(velocity.dx, velocity.dy + 0.15);
    rotation += rotationSpeed;
  }

  bool get isBomb => type == NodeType.bomb;
  bool get isOffScreen =>
      position.dy > 1000 || position.dx < -100 || position.dx > 1000;
}

class SlicePainter extends CustomPainter {
  final List<SliceNode> nodes;
  final List<Offset> swipePath;
  final GraphicsQuality graphicsQuality;

  // ── Cached Paint objects ──────────────────────────────────────────────────
  static final Paint _swipeCorePaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;

  static final Paint _swipeGlowPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4
    ..strokeCap = StrokeCap.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

  static final Paint _innerCore = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;

  SlicePainter({
    required this.nodes,
    required this.swipePath,
    required this.graphicsQuality,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Swipe path
    if (swipePath.length > 1) {
      final path = Path();
      path.moveTo(swipePath.first.dx, swipePath.first.dy);
      for (int i = 1; i < swipePath.length; i++) {
        path.lineTo(swipePath[i].dx, swipePath[i].dy);
      }
      if (graphicsQuality != GraphicsQuality.low) {
        canvas.drawPath(path, _swipeGlowPaint);
      }
      canvas.drawPath(path, _swipeCorePaint);
    }

    for (final node in nodes) {
      if (node.isSliced) {
        _drawSlicedNode(canvas, node);
      } else {
        _drawNode(canvas, node);
      }
    }
  }

  void _drawNode(Canvas canvas, SliceNode node) {
    final paint = Paint()
      ..color = node.type == NodeType.bomb ? Colors.redAccent : node.color
      ..style = PaintingStyle.fill;

    if (graphicsQuality != GraphicsQuality.low) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal,
          graphicsQuality == GraphicsQuality.high ? 12 : 6);
    }

    canvas.save();
    canvas.translate(node.position.dx, node.position.dy);
    canvas.rotate(node.rotation);

    if (node.type == NodeType.bomb) {
      final bombPath = Path();
      for (int i = 0; i < 8; i++) {
        final angle = i * pi / 4;
        final r = i % 2 == 0 ? 30.0 : 15.0;
        bombPath.lineTo(cos(angle) * r, sin(angle) * r);
      }
      bombPath.close();
      canvas.drawPath(bombPath, paint);
      canvas.drawCircle(Offset.zero, 10, _innerCore);
    } else {
      switch (node.shape) {
        case ShapeType.square:
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(
                      center: Offset.zero, width: 40, height: 40),
                  const Radius.circular(8)),
              paint);
          break;
        case ShapeType.triangle:
          final path = Path()
            ..moveTo(0, -25)
            ..lineTo(22, 15)
            ..lineTo(-22, 15)
            ..close();
          canvas.drawPath(path, paint);
          break;
        case ShapeType.circle:
          canvas.drawCircle(Offset.zero, 22, paint);
          break;
      }
      canvas.drawCircle(
          Offset.zero,
          5,
          Paint()..color = Colors.white.withAlpha(150));
    }
    canvas.restore();
  }

  void _drawSlicedNode(Canvas canvas, SliceNode node) {
    final paint = Paint()..color = node.color.withAlpha(100);
    canvas.save();
    canvas.translate(node.position.dx - 15, node.position.dy);
    canvas.drawCircle(Offset.zero, 15, paint);
    canvas.restore();

    canvas.save();
    canvas.translate(node.position.dx + 15, node.position.dy);
    canvas.drawCircle(Offset.zero, 15, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SlicePainter old) {
    return old.graphicsQuality != graphicsQuality ||
        old.nodes.length != nodes.length ||
        old.swipePath.length != swipePath.length;
  }
}
