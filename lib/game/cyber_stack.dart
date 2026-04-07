import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../services/database_service.dart';
import '../services/settings_manager.dart';
import 'audio_manager.dart';
import '../widgets/pause_overlay.dart';

class CyberStackGame extends ConsumerStatefulWidget {
  final String? uid;
  const CyberStackGame({super.key, this.uid});

  @override
  ConsumerState<CyberStackGame> createState() => _CyberStackGameState();
}

class _CyberStackGameState extends ConsumerState<CyberStackGame>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // ── Game state ────────────────────────────────────────────────────────────
  List<StackBlock> stack = [];
  double currentBlockX = 0;
  double blockDirection = 1.0;
  double blockWidth = 200.0;
  double lastBlockX = 0;
  double speed = 3.0;

  // ── Cached screen size ────────────────────────────────────────────────────
  double _screenWidth = 0;

  final ValueNotifier<int> _score = ValueNotifier(0);
  final ValueNotifier<bool> _isGameOver = ValueNotifier(false);
  final ValueNotifier<bool> _isStarted = ValueNotifier(false);
  final ValueNotifier<bool> _isPaused = ValueNotifier(false);

  final Random random = Random();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenWidth = MediaQuery.of(context).size.width;
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(_update);
    _resetGame();
  }

  void _resetGame() {
    _score.value = 0;
    _isGameOver.value = false;
    _isStarted.value = false;
    blockWidth = 200.0;
    currentBlockX = 0;
    lastBlockX = 0;
    speed = 3.0;
    stack = [StackBlock(y: 0, x: 0, width: 200, color: Colors.purpleAccent)];
  }

  void _startGame() {
    _isStarted.value = true;
    _controller.repeat();
  }

  void _update() {
    if (_isGameOver.value || !_isStarted.value || _isPaused.value) return;

    currentBlockX += speed * blockDirection;

    final double limit = (_screenWidth - blockWidth) / 2 + 50;
    if (currentBlockX.abs() > limit) blockDirection *= -1;
  }

  void _onTap() {
    if (_isPaused.value) return;
    if (!_isStarted.value || _isGameOver.value) {
      _resetGame();
      _startGame();
      return;
    }

    final double diff = (currentBlockX - lastBlockX).abs();
    if (diff >= blockWidth) {
      _gameOver();
      return;
    }

    final double newWidth = blockWidth - diff;
    lastBlockX = currentBlockX;
    blockWidth = newWidth;
    _score.value++;
    speed += 0.2;

    stack.add(StackBlock(
      y: stack.length.toDouble(),
      x: currentBlockX,
      width: blockWidth,
      color: Colors.purpleAccent,
    ));

    if (stack.length > 8) stack.removeAt(0);

    AudioManager().playSfx('hit.mp3');
  }

  void _gameOver() {
    _isGameOver.value = true;
    AudioManager().playSfx('gameover.mp3');
    _controller.stop();
    DatabaseService(uid: widget.uid).updateScore('cyber_stack', _score.value);
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
          onTapDown: (_) => _onTap(),
          child: Stack(
            children: [
              // ── Game Canvas ───────────────────────────────────────────────
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return RepaintBoundary(
                    child: CustomPaint(
                      painter: StackPainter(
                        stack: stack,
                        currentX: currentBlockX,
                        currentWidth: blockWidth,
                        isStarted: _isStarted.value,
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
                          Shadow(color: Colors.purpleAccent, blurRadius: 15)
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
                                color: Colors.purpleAccent.withAlpha(100),
                                width: 2),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                gameOver ? 'TOWER FELL' : 'CYBER STACK',
                                style: const TextStyle(
                                  color: Colors.purpleAccent,
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
                                'Tap to stack the moving blocks.\nPrecision is everything!',
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

class StackBlock {
  double y, x, width;
  Color color;
  StackBlock({
    required this.y,
    required this.x,
    required this.width,
    required this.color,
  });
}

class StackPainter extends CustomPainter {
  final List<StackBlock> stack;
  final double currentX;
  final double currentWidth;
  final bool isStarted;
  final GraphicsQuality graphicsQuality;

  // ── Cached border Paint ───────────────────────────────────────────────────
  static final Paint _borderPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  StackPainter({
    required this.stack,
    required this.currentX,
    required this.currentWidth,
    required this.isStarted,
    required this.graphicsQuality,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final bottomY = size.height - 150;
    const blockHeight = 40.0;

    for (int i = 0; i < stack.length; i++) {
      final b = stack[i];
      final drawX = centerX + b.x - (b.width / 2);
      final drawY = bottomY - (i * blockHeight);
      _drawNeonBlock(
          canvas, Rect.fromLTWH(drawX, drawY, b.width, blockHeight), b.color, 1.0);
    }

    if (isStarted) {
      final movingX = centerX + currentX - (currentWidth / 2);
      final movingY = bottomY - (stack.length * blockHeight);
      _drawNeonBlock(
          canvas,
          Rect.fromLTWH(movingX, movingY, currentWidth, blockHeight),
          Colors.purpleAccent,
          0.8);
    }
  }

  void _drawNeonBlock(Canvas canvas, Rect rect, Color color, double opacity) {
    final paint = Paint()
      ..color = color.withAlpha((opacity * 255).toInt())
      ..style = PaintingStyle.fill;

    if (graphicsQuality != GraphicsQuality.low) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal,
          graphicsQuality == GraphicsQuality.high ? 10 : 5);

      if (graphicsQuality == GraphicsQuality.high) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(2), const Radius.circular(6)),
          Paint()
            ..color = color.withAlpha(50)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
        );
      }
    }

    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)), paint);

    _borderPaint.color = Colors.white.withAlpha((opacity * 255).toInt());
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)), _borderPaint);
  }

  @override
  bool shouldRepaint(covariant StackPainter old) {
    return old.currentX != currentX ||
        old.currentWidth != currentWidth ||
        old.isStarted != isStarted ||
        old.graphicsQuality != graphicsQuality ||
        old.stack.length != stack.length;
  }
}
