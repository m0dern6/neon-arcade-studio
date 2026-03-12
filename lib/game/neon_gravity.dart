import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_service.dart';
import 'audio_manager.dart';
import '../widgets/pause_overlay.dart';

class NeonGravityGame extends StatefulWidget {
  const NeonGravityGame({super.key});

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

  List<Obstacle> obstacles = [];
  double speed = 5.0;
  DateTime? lastObstacleTime;

  final Random random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(_update);
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

    // Persist score to Firebase if user is logged in
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DatabaseService(uid: user.uid).updateScore('neon_gravity', score);
    }
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
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(180),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.cyan.withAlpha(100),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.cyan.withAlpha(50),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isGameOver ? 'GAME OVER' : 'NEON GRAVITY',
                          style: TextStyle(
                            color: isGameOver
                                ? Colors.redAccent
                                : Colors.cyanAccent,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (isGameOver)
                          Text(
                            'Score: $score',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                            ),
                          ),
                        const SizedBox(height: 20),
                        Text(
                          'TAP TO ${isGameOver ? 'RESTART' : 'START'}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
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
                  isMusicEnabled: AudioManager().isMusicEnabled,
                  isSfxEnabled: AudioManager().isSfxEnabled,
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

  NeonPainter({
    required this.playerY,
    required this.playerX,
    required this.obstacles,
    required this.score,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final laneOffset = 80.0;

    // Draw Lanes
    final lanePaint = Paint()
      ..color = Colors.cyan.withAlpha(100)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    canvas.drawLine(
      Offset(0, centerY - laneOffset - 20),
      Offset(size.width, centerY - laneOffset - 20),
      lanePaint,
    );
    canvas.drawLine(
      Offset(0, centerY + laneOffset + 20),
      Offset(size.width, centerY + laneOffset + 20),
      lanePaint,
    );

    // Draw Obstacles
    final obsPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    for (var obs in obstacles) {
      final oY = centerY + (obs.isTop ? -laneOffset - 20 : laneOffset + 20);
      final path = Path();
      if (obs.isTop) {
        path.moveTo(obs.x - 20, oY);
        path.lineTo(obs.x + 20, oY);
        path.lineTo(obs.x, oY + 30);
      } else {
        path.moveTo(obs.x - 20, oY);
        path.lineTo(obs.x + 20, oY);
        path.lineTo(obs.x, oY - 30);
      }
      path.close();
      canvas.drawPath(path, obsPaint);

      // Glow for obstacles
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.red.withAlpha(150)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Draw Player
    final playerPaint = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final pY = centerY + (playerY * laneOffset);
    final playerRect = Rect.fromCenter(
      center: Offset(playerX, pY),
      width: 30,
      height: 30,
    );

    // Outer Glow
    canvas.drawRRect(
      RRect.fromRectAndRadius(playerRect, const Radius.circular(5)),
      playerPaint,
    );

    // Core
    canvas.drawRRect(
      RRect.fromRectAndRadius(playerRect.deflate(5), const Radius.circular(3)),
      Paint()..color = Colors.white,
    );

    // Speed Lines (Visual effect)
    final linePaint = Paint()
      ..color = Colors.white.withAlpha(30)
      ..strokeWidth = 1;

    for (int i = 0; i < 5; i++) {
      double lx =
          (DateTime.now().millisecondsSinceEpoch / 2 + i * 100) % size.width;
      canvas.drawLine(
        Offset(size.width - lx, i * size.height / 5),
        Offset(size.width - lx - 50, i * size.height / 5),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant NeonPainter oldDelegate) => true;
}
