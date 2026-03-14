import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_service.dart';
import '../services/settings_manager.dart';
import 'audio_manager.dart';
import '../widgets/pause_overlay.dart';

class OrbitalStrikeGame extends StatefulWidget {
  const OrbitalStrikeGame({super.key});

  @override
  State<OrbitalStrikeGame> createState() => _OrbitalStrikeGameState();
}

class _OrbitalStrikeGameState extends State<OrbitalStrikeGame>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Game State
  double shieldAngle = 0;
  double shieldRotationDirection = 1.0; // 1 for clockwise, -1 for counter
  double shieldWidth = pi / 2; // 90 degrees

  List<Enemy> enemies = [];
  int score = 0;
  bool isGameOver = false;
  bool isStarted = false;
  bool isPaused = false;
  double spawnRate = 2000; // ms
  DateTime? lastSpawnTime;

  final Random random = Random();
  late GraphicsQuality _graphicsQuality;

  @override
  void initState() {
    super.initState();
    _graphicsQuality = SettingsManager().graphicsQuality;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
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
      enemies = [];
      shieldAngle = 0;
      spawnRate = 2000;
      lastSpawnTime = DateTime.now();
    });
    AudioManager().playSfx('start.mp3');
    _controller.repeat();
  }

  void _update() {
    if (isGameOver || !isStarted || isPaused) return;

    setState(() {
      // Rotate shield - Speed increases with score
      double rotationSpeed = 0.08 + (score * 0.002);
      shieldAngle += rotationSpeed * shieldRotationDirection;

      // Dynamic Shield Width - Gets smaller as score increases
      shieldWidth = (pi / 2) - (score * 0.01).clamp(0, pi / 4);

      // Update enemies
      for (var enemy in enemies) {
        // Base speed + acceleration based on score
        enemy.distance -=
            (2.0 + (score / 8) + (random.nextDouble() * (score / 20)));
      }

      // Check for collisions or score
      _checkCollisions();

      // Spawn enemies
      if (lastSpawnTime == null ||
          DateTime.now().difference(lastSpawnTime!).inMilliseconds >
              spawnRate) {
        enemies.add(Enemy(angle: random.nextDouble() * 2 * pi, distance: 400));

        // Advanced mechanics: Spawn 2 enemies at once past score 15
        if (score >= 15 && random.nextDouble() < 0.2) {
          enemies.add(
            Enemy(
              angle: (enemies.last.angle + pi) % (2 * pi), // Opposite side
              distance: 450,
            ),
          );
        }

        lastSpawnTime = DateTime.now();
        // Faster spawn rate decay
        if (spawnRate > 450) spawnRate -= 35;
      }
    });
  }

  void _checkCollisions() {
    final List<Enemy> toRemove = [];

    for (var enemy in enemies) {
      if (enemy.distance < 45) {
        // Threshold for center interaction
        // Check if shield blocks it
        // Normalize angles to 0..2PI
        double normShield = shieldAngle % (2 * pi);
        double normEnemy = enemy.angle % (2 * pi);

        // Simple angular distance check
        double diff = (normShield - normEnemy).abs();
        if (diff > pi) diff = 2 * pi - diff;

        if (diff < shieldWidth / 2) {
          // Blocked!
          score++;
          toRemove.add(enemy);
          AudioManager().playSfx('hit.mp3');
        } else {
          // Hit core!
          _gameOver();
          break;
        }
      }
    }

    enemies.removeWhere((e) => toRemove.contains(e));
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
      DatabaseService(uid: user.uid).updateScore('orbital', score);
    }
  }

  void _onTap() {
    if (isPaused) return;
    if (!isStarted || isGameOver) {
      _startGame();
    } else {
      setState(() {
        shieldRotationDirection = -shieldRotationDirection;
      });
      AudioManager().playSfx(
        'jump.mp3',
      ); // Using jump sound for direction switch
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
          onTap: _onTap,
          child: Stack(
            children: [
              CustomPaint(
                painter: OrbitalPainter(
                  shieldAngle: shieldAngle,
                  shieldWidth: shieldWidth,
                  enemies: enemies,
                  isGameOver: isGameOver,
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
                      shadows: [
                        Shadow(color: Colors.pinkAccent, blurRadius: 15),
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
                        color: Colors.pinkAccent.withAlpha(100),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isGameOver ? 'CORE BREACHED' : 'ORBITAL STRIKE',
                          style: const TextStyle(
                            color: Colors.pinkAccent,
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
                        Text(
                          'TAP TO ${isGameOver ? 'RETRY' : 'DEFEND'}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Tap to change shield direction',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
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

class Enemy {
  double angle;
  double distance;
  Enemy({required this.angle, required this.distance});
}

class OrbitalPainter extends CustomPainter {
  final double shieldAngle;
  final double shieldWidth;
  final List<Enemy> enemies;
  final bool isGameOver;
  final GraphicsQuality graphicsQuality;

  OrbitalPainter({
    required this.shieldAngle,
    required this.shieldWidth,
    required this.enemies,
    required this.isGameOver,
    required this.graphicsQuality,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Draw Background Grid/Rings
    final ringPaint = Paint()
      ..color = Colors.white.withAlpha(10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, i * 100.0, ringPaint);
    }

    // Draw Core
    final corePaint = Paint()
      ..color = isGameOver ? Colors.red : Colors.pinkAccent;

    if (graphicsQuality != GraphicsQuality.low) {
      corePaint.maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        graphicsQuality == GraphicsQuality.high ? 15 : 10,
      );
      if (graphicsQuality == GraphicsQuality.high) {
        canvas.drawCircle(
          center,
          30,
          Paint()
            ..color = (isGameOver ? Colors.red : Colors.pink).withAlpha(100)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
        );
      }
    }

    canvas.drawCircle(center, 25, corePaint);
    canvas.drawCircle(center, 15, Paint()..color = Colors.white);

    // Draw Shield
    final shieldPaint = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    if (graphicsQuality != GraphicsQuality.low) {
      shieldPaint.maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        graphicsQuality == GraphicsQuality.high ? 8 : 5,
      );
      if (graphicsQuality == GraphicsQuality.high) {
        // extra shield glow
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: 45),
          shieldAngle - shieldWidth / 2,
          shieldWidth,
          false,
          Paint()
            ..color = Colors.cyanAccent.withAlpha(100)
            ..strokeWidth = 12
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15),
        );
      }
    }

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 45),
      shieldAngle - shieldWidth / 2,
      shieldWidth,
      false,
      shieldPaint,
    );

    // Shield Inner Line
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 45),
      shieldAngle - shieldWidth / 2,
      shieldWidth,
      false,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // Draw Enemies
    final enemyPaint = Paint()..color = Colors.amberAccent;
    if (graphicsQuality != GraphicsQuality.low) {
      enemyPaint.maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        graphicsQuality == GraphicsQuality.high ? 6 : 4,
      );
    }

    for (var enemy in enemies) {
      double ex = center.dx + cos(enemy.angle) * enemy.distance;
      double ey = center.dy + sin(enemy.angle) * enemy.distance;

      canvas.drawCircle(Offset(ex, ey), 8, enemyPaint);
      canvas.drawCircle(Offset(ex, ey), 4, Paint()..color = Colors.white);

      // Tail effect
      canvas.drawLine(
        Offset(ex, ey),
        Offset(
          center.dx + cos(enemy.angle) * (enemy.distance + 20),
          center.dy + sin(enemy.angle) * (enemy.distance + 20),
        ),
        Paint()
          ..color = Colors.amber.withAlpha(100)
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant OrbitalPainter oldDelegate) => true;
}
