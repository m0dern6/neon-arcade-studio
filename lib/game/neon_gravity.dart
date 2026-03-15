import 'dart:math';
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/settings_manager.dart';
import 'audio_manager.dart';
import '../widgets/pause_overlay.dart';

class NeonGravityGame extends StatefulWidget {
  final String? uid;
  const NeonGravityGame({super.key, this.uid});

  @override
  State<NeonGravityGame> createState() => _NeonGravityGameState();
}

class _NeonGravityGameState extends State<NeonGravityGame>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Game State
  double playerY = 0; // -1 for top, 1 for bottom
  double playerTargetY = 1;
  double playerX = 50;
  int score = 0;
  bool isGameOver = false;
  bool isStarted = false;
  bool isPaused = false;
  List<Offset> trail = []; // Player trail

  List<Obstacle> obstacles = [];
  double speed = 5.0;
  DateTime? lastObstacleTime;

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
      isGameOver = false;
      isStarted = true;
      playerY = 1;
      playerTargetY = 1;
      obstacles = [];
      speed = 5.0;
      lastObstacleTime = DateTime.now();
    });
    AudioManager().playSfx('start.mp3');
    _controller.repeat();
  }

  void _update() {
    if (isGameOver || !isStarted || isPaused) return;

    setState(() {
      // Smooth player movement
      playerY += (playerTargetY - playerY) * 0.15;

      // Update trail
      final screenHeight = MediaQuery.of(context).size.height;
      final laneOffset = 80.0;
      final pY = (screenHeight / 2) + (playerY * laneOffset);
      trail.insert(0, Offset(playerX, pY));
      if (trail.length > 15) trail.removeLast();

      // Move obstacles
      int level = (score / 10).floor();
      double dynamicSpeed = speed + (level * 0.8);

      for (var obs in obstacles) {
        obs.x -= dynamicSpeed;
      }

      // Remove off-screen obstacles and update score
      obstacles.removeWhere((obs) {
        if (obs.x < -40) {
          score += 1;
          return true;
        }
        return false;
      });

      // Spawn new obstacles - Frequency increases with level
      double spawnInterval = (1600 / (1 + (level * 0.25))).clamp(400, 2000);

      if (lastObstacleTime == null ||
          DateTime.now().difference(lastObstacleTime!).inMilliseconds >
              spawnInterval) {
        obstacles.add(
          Obstacle(
            x: MediaQuery.of(context).size.width + 50,
            isTop: random.nextBool(),
          ),
        );

        // Rare double-obstacle pattern for level 2+
        if (level >= 2 && random.nextDouble() < (level * 0.08).clamp(0, 0.4)) {
          obstacles.add(
            Obstacle(
              x: MediaQuery.of(context).size.width + 180,
              isTop: !obstacles.last.isTop, // Reverse side for tricky jumps
            ),
          );
        }

        lastObstacleTime = DateTime.now();
      }

      // Collision Detection
      _checkCollision();
    });
  }

  void _checkCollision() {
    // final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Player bounds approx
    double pX = playerX;
    double pY = (screenHeight / 2) + (playerY * 80);
    // double pSize = 30;

    for (var obs in obstacles) {
      double oX = obs.x;
      double oY = (screenHeight / 2) + (obs.isTop ? -80 : 80);

      // Simple circle-square collision approximation for speed
      double dx = (pX - oX).abs();
      double dy = (pY - oY).abs();

      if (dx < 40 && dy < 30) {
        _gameOver();
        break;
      }
    }
  }

  void _gameOver() {
    setState(() {
      isGameOver = true;
    });
    AudioManager().playSfx('gameover.mp3');
    _controller.stop();

    // Persist score to Firebase or locally
    DatabaseService(uid: widget.uid).updateScore('neon_gravity', score);
  }

  void _onTap() {
    if (isPaused) return; // Prevent interaction when paused
    if (!isStarted) {
      _startGame();
    } else if (isGameOver) {
      _startGame();
    } else {
      setState(() {
        playerTargetY = -playerTargetY;
      });
      AudioManager().playSfx('jump.mp3');
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
      canPop:
          isGameOver || !isStarted, // Only allow system back if game not active
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
          onTap: _onTap,
          child: Stack(
            children: [
              // Game Drawing
              CustomPaint(
                painter: NeonPainter(
                  playerY: playerY,
                  playerX: playerX,
                  obstacles: obstacles,
                  score: score,
                  graphicsQuality: _graphicsQuality,
                  trail: trail,
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
                      shadows: [Shadow(color: Colors.cyan, blurRadius: 10)],
                    ),
                  ),
                ),
              ),

              // Start/Game Over Overlay
              if (!isStarted || isGameOver)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D0D2B).withAlpha(220),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: (isGameOver ? Colors.redAccent : Colors.cyanAccent).withAlpha(150),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isGameOver ? Colors.redAccent : Colors.cyanAccent).withAlpha(40),
                          blurRadius: 30,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isGameOver ? Icons.error_outline : Icons.bolt,
                          color: isGameOver ? Colors.redAccent : Colors.cyanAccent,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isGameOver ? 'SYSTEM FAILURE' : 'NEON GRAVITY',
                          style: TextStyle(
                            color: isGameOver ? Colors.redAccent : Colors.cyanAccent,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                        if (isGameOver) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Score: $score',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Text(
                          'TAP TO ${isGameOver ? 'RETRY' : 'INITIALIZE'}',
                          style: TextStyle(
                            color: Colors.white.withAlpha(180),
                            fontSize: 14,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Back Button (Moved here to be on top)
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

class Obstacle {
  double x;
  bool isTop;
  Obstacle({required this.x, required this.isTop});
}

class NeonPainter extends CustomPainter {
  final double playerY;
  final double playerX;
  final List<Obstacle> obstacles;
  final int score;
  final GraphicsQuality graphicsQuality;
  final List<Offset> trail;

  NeonPainter({
    required this.playerY,
    required this.playerX,
    required this.obstacles,
    required this.score,
    required this.graphicsQuality,
    required this.trail,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final laneOffset = 80.0;
    final time = DateTime.now().millisecondsSinceEpoch / 1000.0;

    // 0. Draw Moving Grid Background
    final gridPaint = Paint()
      ..color = Colors.cyan.withAlpha(20)
      ..strokeWidth = 1;
    
    double gridSpeed = 100.0;
    double offsetX = (time * gridSpeed) % 40;
    
    for (double x = -offsetX; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 1. Draw Lanes
    final laneCorePaint = Paint()
      ..color = Colors.white.withAlpha(180)
      ..strokeWidth = 1.5;

    final laneGlowPaint = Paint()
      ..color = Colors.cyan.withAlpha(100)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    if (graphicsQuality != GraphicsQuality.low) {
      laneGlowPaint.maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        graphicsQuality == GraphicsQuality.high ? 4 : 2, // Fixed: Reduced blur for visibility
      );
      
      if (graphicsQuality == GraphicsQuality.high) {
        // Broad outer glow
        final broadGlow = Paint()
          ..color = Colors.cyan.withAlpha(40)
          ..strokeWidth = 12
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
          
        canvas.drawLine(Offset(0, centerY - laneOffset - 20), Offset(size.width, centerY - laneOffset - 20), broadGlow);
        canvas.drawLine(Offset(0, centerY + laneOffset + 20), Offset(size.width, centerY + laneOffset + 20), broadGlow);
      }
    }

    // Draw Top Lane
    canvas.drawLine(Offset(0, centerY - laneOffset - 20), Offset(size.width, centerY - laneOffset - 20), laneGlowPaint);
    canvas.drawLine(Offset(0, centerY - laneOffset - 20), Offset(size.width, centerY - laneOffset - 20), laneCorePaint);
    
    // Draw Bottom Lane
    canvas.drawLine(Offset(0, centerY + laneOffset + 20), Offset(size.width, centerY + laneOffset + 20), laneGlowPaint);
    canvas.drawLine(Offset(0, centerY + laneOffset + 20), Offset(size.width, centerY + laneOffset + 20), laneCorePaint);

    // 2. Draw Obstacles
    final obsPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;

    if (graphicsQuality != GraphicsQuality.low) {
      obsPaint.maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        graphicsQuality == GraphicsQuality.high ? 8 : 4,
      );
    }

    for (var obs in obstacles) {
      final oY = centerY + (obs.isTop ? -laneOffset - 20 : laneOffset + 20);
      final path = Path();
      if (obs.isTop) {
        path.moveTo(obs.x - 20, oY);
        path.lineTo(obs.x + 20, oY);
        path.lineTo(obs.x, oY + 35);
      } else {
        path.moveTo(obs.x - 20, oY);
        path.lineTo(obs.x + 20, oY);
        path.lineTo(obs.x, oY - 35);
      }
      path.close();
      canvas.drawPath(path, obsPaint);

      // Sharp Core for obstacles
      final obsCore = Paint()
        ..color = Colors.white.withAlpha(200)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawPath(path, obsCore);

      if (graphicsQuality == GraphicsQuality.high) {
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.red.withAlpha(60)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 10
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
        );
      }
    }

    // 3. Draw Player Trail
    if (graphicsQuality != GraphicsQuality.low) {
      for (int i = 0; i < trail.length; i++) {
        final opacity = (1.0 - (i / trail.length)) * 0.5;
        canvas.drawCircle(
          trail[i],
          15.0 * (1.0 - (i / trail.length)),
          Paint()
            ..color = Colors.cyanAccent.withOpacity(opacity)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }
    }

    // 4. Draw Player
    final pY = centerY + (playerY * laneOffset);
    final playerRect = Rect.fromCenter(
      center: Offset(playerX, pY),
      width: 32,
      height: 32,
    );

    if (graphicsQuality != GraphicsQuality.low) {
      // Outer Glow
      canvas.drawRRect(
        RRect.fromRectAndRadius(playerRect.inflate(4), const Radius.circular(8)),
        Paint()
          ..color = Colors.cyanAccent.withAlpha(80)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, graphicsQuality == GraphicsQuality.high ? 15 : 8),
      );
    }

    // Player Body
    canvas.drawRRect(
      RRect.fromRectAndRadius(playerRect, const Radius.circular(6)),
      Paint()..color = Colors.cyanAccent,
    );

    // Player Core
    canvas.drawRRect(
      RRect.fromRectAndRadius(playerRect.deflate(6), const Radius.circular(4)),
      Paint()..color = Colors.white,
    );

    // 5. Speed Particles/Lines
    final linePaint = Paint()
      ..color = Colors.white.withAlpha(40)
      ..strokeWidth = 1.2;

    for (int i = 0; i < 8; i++) {
      double lx = (time * 400 + i * 200) % size.width;
      double ly = (i * size.height / 8 + (sin(time + i) * 20)) % size.height;
      canvas.drawLine(
        Offset(size.width - lx, ly),
        Offset(size.width - lx - 40, ly),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant NeonPainter oldDelegate) => true;
}
