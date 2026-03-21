import 'dart:math';
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/settings_manager.dart';
import 'audio_manager.dart';
import '../widgets/pause_overlay.dart';

class CyberSliceGame extends StatefulWidget {
  final String? uid;
  const CyberSliceGame({super.key, this.uid});

  @override
  State<CyberSliceGame> createState() => _CyberSliceGameState();
}

class _CyberSliceGameState extends State<CyberSliceGame>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random random = Random();

  // Game State
  int score = 0;
  int combo = 0;
  bool isGameOver = false;
  bool isStarted = false;
  bool isPaused = false;
  
  List<SliceNode> activeNodes = [];
  List<Offset> swipePath = [];
  DateTime? lastSpawnTime;
  
  late GraphicsQuality _graphicsQuality;

  @override
  void initState() {
    super.initState();
    _graphicsQuality = SettingsManager().graphicsQuality;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(_update);
  }

  void _cycleGraphics() {
    setState(() {
      int next = (_graphicsQuality.index + 1) % GraphicsQuality.values.length;
      _graphicsQuality = GraphicsQuality.values[next];
      SettingsManager().setGraphicsQuality(_graphicsQuality);
    });
  }

  void _startGame() {
    setState(() {
      score = 0;
      combo = 0;
      isGameOver = false;
      isStarted = true;
      activeNodes = [];
      swipePath = [];
      lastSpawnTime = DateTime.now();
    });
    AudioManager().playSfx('start.mp3');
    _controller.repeat();
  }

  void _update() {
    if (isGameOver || !isStarted || isPaused) return;

    setState(() {
      // Move nodes
      for (var node in activeNodes) {
        node.update();
      }

      // Remove off-screen nodes
      activeNodes.removeWhere((node) {
        if (node.isOffScreen) {
          if (!node.isSliced && !node.isBomb) {
            // MISS!
            combo = 0;
            // Optionally lose a life here if we had lives. 
            // For now, just let it pass but reset combo.
          }
          return true;
        }
        return false;
      });

      // Spawn new nodes
      double spawnInterval = (1200 / (1 + (score / 500))).clamp(400, 1500);
      if (lastSpawnTime == null ||
          DateTime.now().difference(lastSpawnTime!).inMilliseconds > spawnInterval) {
        _spawnNode();
        lastSpawnTime = DateTime.now();
      }
    });
  }

  void _spawnNode() {
    final size = MediaQuery.of(context).size;
    activeNodes.add(
      SliceNode(
        position: Offset(50 + random.nextDouble() * (size.width - 100), size.height + 50),
        velocity: Offset((random.nextDouble() - 0.5) * 4, -8 - random.nextDouble() * 6),
        type: random.nextDouble() < 0.15 ? NodeType.bomb : NodeType.shape,
        shape: ShapeType.values[random.nextInt(ShapeType.values.length)],
        color: _getRandomNeonColor(),
      ),
    );
  }

  Color _getRandomNeonColor() {
    final colors = [
      Colors.cyanAccent,
      Colors.pinkAccent,
      Colors.yellowAccent,
      Colors.purpleAccent,
      Colors.greenAccent,
    ];
    return colors[random.nextInt(colors.length)];
  }

  void _handlePanStart(DragStartDetails details) {
    if (!isStarted || isGameOver || isPaused) return;
    setState(() {
      swipePath = [details.localPosition];
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!isStarted || isGameOver || isPaused) return;
    
    setState(() {
      final pos = details.localPosition;
      swipePath.add(pos);
      if (swipePath.length > 10) swipePath.removeAt(0);

      // Check for collisions with nodes
      for (var node in activeNodes) {
        if (!node.isSliced) {
          final dist = (node.position - pos).distance;
          if (dist < 45) { // Collision radius
            _sliceNode(node);
          }
        }
      }
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    setState(() {
      swipePath = [];
    });
  }

  void _sliceNode(SliceNode node) {
    if (node.isBomb) {
      _gameOver();
      return;
    }

    node.isSliced = true;
    score += (10 * (1 + combo ~/ 5));
    combo++;
    AudioManager().playSfx('hit.mp3');
    
    // Tiny haptic-like effect or visual pop is handled in painter
  }

  void _gameOver() {
    setState(() {
      isGameOver = true;
      swipePath = [];
    });
    AudioManager().playSfx('gameover.mp3');
    _controller.stop();
    DatabaseService(uid: widget.uid).updateScore('pulse_dash', score); // We'll keep id for leaderboard compatibility or change it
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
          setState(() => isPaused = true);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D2B),
        body: GestureDetector(
          onPanStart: _handlePanStart,
          onPanUpdate: _handlePanUpdate,
          onPanEnd: _handlePanEnd,
          onTapDown: (_) {
            if (!isStarted || isGameOver) _startGame();
          },
          child: Stack(
            children: [
              CustomPaint(
                painter: SlicePainter(
                  nodes: activeNodes,
                  swipePath: swipePath,
                  graphicsQuality: _graphicsQuality,
                ),
                size: Size.infinite,
              ),

              // UI Overlay
              Positioned(
                top: 60,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    Text(
                      '$score',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        shadows: [Shadow(color: Colors.cyanAccent, blurRadius: 15)],
                      ),
                    ),
                    if (combo > 1)
                      Text(
                        'COMBO X${combo ~/ 5 + 1}',
                        style: const TextStyle(color: Colors.yellowAccent, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                  ],
                ),
              ),

              if (!isStarted || isGameOver)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(200),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.cyanAccent.withAlpha(100), width: 2),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isGameOver ? 'CORE BREACHED' : 'CYBER SLICE',
                          style: const TextStyle(color: Colors.cyanAccent, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2),
                        ),
                        const SizedBox(height: 10),
                        if (isGameOver) Text('Score: $score', style: const TextStyle(color: Colors.white, fontSize: 20)),
                        const SizedBox(height: 20),
                        const Text('Swipe to slice neon nodes.\nAvoid the red data bombs!', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                        const SizedBox(height: 20),
                        Text('TAP TO ${isGameOver ? 'RETRY' : 'START'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),

              Positioned(
                top: 50,
                left: 20,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                  onPressed: () {
                    if (isStarted && !isGameOver) {
                      setState(() => isPaused = true);
                    } else {
                      Navigator.pop(context);
                    }
                  },
                ),
              ),

              if (isPaused)
                PauseOverlay(
                  onResume: () => setState(() => isPaused = false),
                  onHome: () => Navigator.pop(context),
                  onToggleMusic: () => setState(() => AudioManager().toggleMusic(!AudioManager().isMusicEnabled)),
                  onToggleSfx: () => setState(() => AudioManager().toggleSfx(!AudioManager().isSfxEnabled)),
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
  double rotationSpeed = (Random().nextDouble() - 0.5) * 0.2;

  SliceNode({
    required this.position,
    required this.velocity,
    required this.type,
    required this.shape,
    required this.color,
  });

  void update() {
    position += velocity;
    velocity = Offset(velocity.dx, velocity.dy + 0.15); // Gravity
    rotation += rotationSpeed;
  }

  bool get isBomb => type == NodeType.bomb;
  bool get isOffScreen => position.dy > 1000 || position.dx < -100 || position.dx > 1000; 
}

class SlicePainter extends CustomPainter {
  final List<SliceNode> nodes;
  final List<Offset> swipePath;
  final GraphicsQuality graphicsQuality;

  SlicePainter({required this.nodes, required this.swipePath, required this.graphicsQuality});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Swipe Path
    if (swipePath.length > 1) {
      final path = Path();
      path.moveTo(swipePath.first.dx, swipePath.first.dy);
      for (int i = 1; i < swipePath.length; i++) {
        path.lineTo(swipePath[i].dx, swipePath[i].dy);
      }
      
      final swipePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      
      if (graphicsQuality != GraphicsQuality.low) {
        swipePaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawPath(path, swipePaint); // Glow
        swipePaint.maskFilter = null;
        swipePaint.strokeWidth = 2;
      }
      canvas.drawPath(path, swipePaint);
    }

    // 2. Draw Nodes
    for (var node in nodes) {
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
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, graphicsQuality == GraphicsQuality.high ? 12 : 6);
    }

    canvas.save();
    canvas.translate(node.position.dx, node.position.dy);
    canvas.rotate(node.rotation);

    if (node.type == NodeType.bomb) {
      // Draw a spikey bomb
      final bombPath = Path();
      for (int i = 0; i < 8; i++) {
        double angle = i * pi / 4;
        double r = i % 2 == 0 ? 30 : 15;
        bombPath.lineTo(cos(angle) * r, sin(angle) * r);
      }
      bombPath.close();
      canvas.drawPath(bombPath, paint);
      canvas.drawCircle(Offset.zero, 10, Paint()..color = Colors.white);
    } else {
      switch (node.shape) {
        case ShapeType.square:
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 40, height: 40), const Radius.circular(8)), paint);
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
      // Inner Core
      canvas.drawCircle(Offset.zero, 5, Paint()..color = Colors.white.withAlpha(150));
    }
    canvas.restore();
  }

  void _drawSlicedNode(Canvas canvas, SliceNode node) {
    final paint = Paint()..color = node.color.withAlpha(100);
    // Draw two halves flying apart
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
  bool shouldRepaint(covariant SlicePainter oldDelegate) => true;
}
