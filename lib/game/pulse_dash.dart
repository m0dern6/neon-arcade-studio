import 'dart:math';
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/settings_manager.dart';
import 'audio_manager.dart';
import '../widgets/pause_overlay.dart';

class PulseDashGame extends StatefulWidget {
  final String? uid;
  const PulseDashGame({super.key, this.uid});

  @override
  State<PulseDashGame> createState() => _PulseDashGameState();
}

class _PulseDashGameState extends State<PulseDashGame>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Game State
  int score = 0;
  bool isGameOver = false;
  bool isStarted = false;
  bool isPaused = false;
  List<PulseNode> nodes = [];

  DateTime? lastSpawnTime;
  double speedFactor = 1.0;
  int nodesHit = 0; // Added for difficulty scaling

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
      nodesHit = 0;
      isGameOver = false;
      isStarted = true;
      nodes = [];
      speedFactor = 1.0;
      lastSpawnTime = DateTime.now();
    });
    AudioManager().playSfx('start.mp3');
    _controller.repeat();
  }

  void _update() {
    if (isGameOver || !isStarted || isPaused) return;

    setState(() {
      // Dynamic speed scaling - Now based on hits, not thousands of score points
      double levelSpeed = speedFactor + (nodesHit * 0.05);

      // Advance node progress
      for (var node in nodes) {
        node.progress += 0.01 * levelSpeed;
        // Game over if pulse gets too large (missed rhythmic beat)
        if (node.progress > 1.3) {
          _gameOver();
        }
      }

      // Spawn new nodes - Accelerates with hits
      double spawnGap = (1400 / (1 + (nodesHit * 0.08))).clamp(450, 1500);

      if (lastSpawnTime == null ||
          DateTime.now().difference(lastSpawnTime!).inMilliseconds > spawnGap) {
        nodes.add(
          PulseNode(
            position: Offset(
              50 +
                  random.nextDouble() *
                      (MediaQuery.of(context).size.width - 100),
              150 +
                  random.nextDouble() *
                      (MediaQuery.of(context).size.height - 300),
            ),
            id: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        lastSpawnTime = DateTime.now();
      }
    });
  }

  void _onTapDown(TapDownDetails details) {
    if (isPaused) return;
    if (!isStarted || isGameOver) {
      _startGame();
      return;
    }

    final tapPos = details.localPosition;

    setState(() {
      // Tighter accuracy window as you hit more nodes
      double tolerance = (0.25 - (nodesHit * 0.01)).clamp(0.1, 0.25);

      for (int i = nodes.length - 1; i >= 0; i--) {
        final node = nodes[i];
        final dist = (node.position - tapPos).distance;

        if (dist < 60) {
          double accuracy = (1.0 - node.progress).abs();
          if (accuracy < tolerance) {
            // Success!
            score += (150 * (1.0 - accuracy)).round();
            nodesHit++;
            nodes.removeAt(i);
            AudioManager().playSfx('hit.mp3');
            return;
          }
        }
      }
    });
  }

  void _gameOver() {
    setState(() {
      isGameOver = true;
    });
    AudioManager().playSfx('gameover.mp3');
    _controller.stop();

    // Persist score
    DatabaseService(uid: widget.uid).updateScore('pulse_dash', score);
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
          onTapDown: _onTapDown,
          child: Stack(
            children: [
              // Background Visualizer (Subtle)
              CustomPaint(
                painter: PulsePainter(
                  nodes: nodes,
                  graphicsQuality: _graphicsQuality,
                ),
                size: Size.infinite,
              ),

              // Score Display
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
                        Shadow(color: Colors.yellowAccent, blurRadius: 15),
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
                        color: Colors.yellowAccent.withAlpha(100),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isGameOver ? 'OUT OF SYNC' : 'PULSE DASH',
                          style: const TextStyle(
                            color: Colors.yellowAccent,
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
                          'Tap the circles when the pulse\nmatches the outer ring!',
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

              // Back Button (At the top to be clickable)
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

class PulseNode {
  Offset position;
  double progress; // 0 to 1.2
  int id;
  PulseNode({required this.position, required this.id, this.progress = 0});
}

class PulsePainter extends CustomPainter {
  final List<PulseNode> nodes;
  final GraphicsQuality graphicsQuality;

  PulsePainter({required this.nodes, required this.graphicsQuality});

  @override
  void paint(Canvas canvas, Size size) {
    for (var node in nodes) {
      // Outer Fixed Ring
      final ringPaint = Paint()
        ..color = Colors.white.withAlpha(50)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(node.position, 40, ringPaint);

      final pulsePaint = Paint()
        ..color = node.progress < 0.8
            ? Colors.yellowAccent.withAlpha(100)
            : (node.progress > 1.0 ? Colors.redAccent : Colors.cyanAccent)
        ..style = PaintingStyle.fill;

      if (graphicsQuality != GraphicsQuality.low) {
        pulsePaint.maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          graphicsQuality == GraphicsQuality.high ? 12 : 8,
        );
        if (graphicsQuality == GraphicsQuality.high) {
          canvas.drawCircle(
            node.position,
            node.progress * 40 + 5,
            Paint()
              ..color = pulsePaint.color.withAlpha(50)
              ..style = PaintingStyle.fill
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
          );
        }
      }

      double radius = node.progress * 40;
      canvas.drawCircle(node.position, radius, pulsePaint);

      // Perfect Timing Indicator
      if (node.progress > 0.8 && node.progress < 1.0) {
        canvas.drawCircle(
          node.position,
          40,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    // Ambient Background Particles
    final particlePaint = Paint()..color = Colors.white.withAlpha(10);
    for (int i = 0; i < 10; i++) {
      double x =
          (DateTime.now().millisecondsSinceEpoch / 20 + i * 50) % size.width;
      double y = (i * 100) % size.height;
      canvas.drawCircle(Offset(x, y), 2, particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant PulsePainter oldDelegate) => true;
}
