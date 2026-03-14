import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_service.dart';
import '../services/settings_manager.dart';
import 'audio_manager.dart';
import '../widgets/pause_overlay.dart';

class CyberStackGame extends StatefulWidget {
  const CyberStackGame({super.key});

  @override
  State<CyberStackGame> createState() => _CyberStackGameState();
}

class _CyberStackGameState extends State<CyberStackGame>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Game State
  int score = 0;
  bool isGameOver = false;
  bool isStarted = false;
  bool isPaused = false;

  List<StackBlock> stack = [];
  double currentBlockX = 0;
  double blockDirection = 1.0;
  double blockWidth = 200.0;
  double lastBlockX = 0;

  double speed = 3.0;
  final Random random = Random();
  late GraphicsQuality _graphicsQuality;

  @override
  void initState() {
    super.initState();
    _graphicsQuality = SettingsManager().graphicsQuality;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(_update);
    _resetGame();
  }

  void _cycleGraphics() {
    setState(() {
      int next = (_graphicsQuality.index + 1) % GraphicsQuality.values.length;
      _graphicsQuality = GraphicsQuality.values[next];
      SettingsManager().setGraphicsQuality(_graphicsQuality);
    });
  }

  void _resetGame() {
    setState(() {
      score = 0;
      isGameOver = false;
      isStarted = false;
      blockWidth = 200.0;
      currentBlockX = 0;
      lastBlockX = 0;
      speed = 3.0;
      stack = [StackBlock(y: 0, x: 0, width: 200, color: Colors.purpleAccent)];
    });
  }

  void _startGame() {
    setState(() {
      isStarted = true;
    });
    _controller.repeat();
  }

  void _update() {
    if (isGameOver || !isStarted || isPaused) return;

    setState(() {
      currentBlockX += speed * blockDirection;

      double limit = (MediaQuery.of(context).size.width - blockWidth) / 2 + 50;
      if (currentBlockX.abs() > limit) {
        blockDirection *= -1;
      }
    });
  }

  void _onTap() {
    if (isPaused) return;
    if (!isStarted || isGameOver) {
      _resetGame();
      _startGame();
      return;
    }

    setState(() {
      double diff = (currentBlockX - lastBlockX).abs();

      if (diff >= blockWidth) {
        _gameOver();
        return;
      }

      // Success! Calculate new width
      double newWidth = blockWidth - diff;

      // Update for visual "cut" - we move the center to the overlapping part
      lastBlockX = currentBlockX;
      blockWidth = newWidth;

      score++;
      speed += 0.2;

      stack.add(
        StackBlock(
          y: stack.length.toDouble(),
          x: currentBlockX,
          width: blockWidth,
          color: Colors.purpleAccent,
        ),
      );

      if (stack.length > 8) {
        stack.removeAt(0); // Camera follow simulation
      }

      AudioManager().playSfx('hit.mp3');
    });
  }

  void _gameOver() {
    setState(() {
      isGameOver = true;
    });
    AudioManager().playSfx('gameover.mp3');
    _controller.stop();

    // Persist score to Firebase if user is logged in
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DatabaseService(uid: user.uid).updateScore('cyber_stack', score);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: isGameOver || !isStarted,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isStarted && !isGameOver) {
          setState(() {
            isPaused = true;
          });
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D2B),
        body: GestureDetector(
          onTapDown: (_) => _onTap(),
          child: Stack(
            children: [
              // Game Visualizer
              CustomPaint(
                painter: StackPainter(
                  stack: stack,
                  currentX: currentBlockX,
                  currentWidth: blockWidth,
                  isStarted: isStarted,
                  graphicsQuality: _graphicsQuality,
                ),
                size: Size.infinite,
              ),

              // Score
              Positioned(
                top: 60,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    '$score',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      shadows: [
                        Shadow(color: Colors.purpleAccent, blurRadius: 15),
                      ],
                    ),
                  ),
                ),
              ),

              // Overlays
              if (!isStarted || isGameOver)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(200),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.purpleAccent.withAlpha(100),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isGameOver ? 'TOWER FELL' : 'CYBER STACK',
                          style: const TextStyle(
                            color: Colors.purpleAccent,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (isGameOver)
                          Text(
                            'Score: $score',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                            ),
                          ),
                        const SizedBox(height: 20),
                        const Text(
                          'Tap to stack the moving blocks.\nPrecision is everything!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'TAP TO ${isGameOver ? 'RETRY' : 'START'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Back Button (At the end to be on top)
              Positioned(
                top: 50,
                left: 20,
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    if (isStarted && !isGameOver) {
                      setState(() {
                        isPaused = true;
                      });
                    } else {
                      Navigator.pop(context);
                    }
                  },
                ),
              ),

              // Pause Menu Overlay
              if (isPaused)
                PauseOverlay(
                  onResume: () {
                    setState(() {
                      isPaused = false;
                    });
                  },
                  onHome: () {
                    Navigator.pop(context);
                  },
                  onToggleMusic: () {
                    setState(() {
                      AudioManager().toggleMusic(
                        !AudioManager().isMusicEnabled,
                      );
                    });
                  },
                  onToggleSfx: () {
                    setState(() {
                      AudioManager().toggleSfx(!AudioManager().isSfxEnabled);
                    });
                  },
                  onToggleGraphics: _cycleGraphics,
                  isMusicEnabled: AudioManager().isMusicEnabled,
                  isSfxEnabled: AudioManager().isSfxEnabled,
                  graphicsQuality: _graphicsQuality,
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

    // Draw Static Stack
    for (int i = 0; i < stack.length; i++) {
      final b = stack[i];
      final drawX = centerX + b.x - (b.width / 2);
      final drawY = bottomY - (i * blockHeight);

      _drawNeonBlock(
        canvas,
        Rect.fromLTWH(drawX, drawY, b.width, blockHeight),
        b.color,
        1.0,
      );
    }

    // Draw Moving Block
    if (isStarted) {
      final movingX = centerX + currentX - (currentWidth / 2);
      final movingY = bottomY - (stack.length * blockHeight);
      _drawNeonBlock(
        canvas,
        Rect.fromLTWH(movingX, movingY, currentWidth, blockHeight),
        Colors.purpleAccent,
        0.8,
      );
    }
  }

  void _drawNeonBlock(Canvas canvas, Rect rect, Color color, double opacity) {
    final paint = Paint()
      ..color = color.withAlpha((opacity * 255).toInt())
      ..style = PaintingStyle.fill;

    if (graphicsQuality != GraphicsQuality.low) {
      paint.maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        graphicsQuality == GraphicsQuality.high ? 10 : 5,
      );

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
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      paint,
    );

    final borderPaint = Paint()
      ..color = Colors.white.withAlpha((opacity * 255).toInt())
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant StackPainter oldDelegate) => true;
}
