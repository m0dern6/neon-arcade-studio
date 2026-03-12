import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_service.dart';
import 'audio_manager.dart';
import '../widgets/pause_overlay.dart';

class VectorVoidGame extends StatefulWidget {
  const VectorVoidGame({super.key});

  @override
  State<VectorVoidGame> createState() => _VectorVoidGameState();
}

class _VectorVoidGameState extends State<VectorVoidGame>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Game State
  int score = 0;
  bool isGameOver = false;
  bool isStarted = false;
  bool isPaused = false;

  Offset playerPos = Offset.zero;
  List<VoidEnemy> enemies = [];
  double speedFactor = 1.0;
  DateTime? lastSpawnTime;

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
      enemies = [];
      speedFactor = 1.0;
      playerPos = Offset(
        MediaQuery.of(context).size.width / 2,
        MediaQuery.of(context).size.height / 2,
      );
      lastSpawnTime = DateTime.now();
    });
    AudioManager().playSfx('start.mp3');
    _controller.repeat();
  }

  void _update() {
    if (isGameOver || !isStarted || isPaused) return;

    setState(() {
      // Update Enemies
      for (var enemy in enemies) {
        enemy.pos += Offset(
          enemy.dir.dx * enemy.speed,
          enemy.dir.dy * enemy.speed,
        );
      }

      // Remove off-screen enemies
      enemies.removeWhere(
        (e) =>
            e.pos.dx < -50 ||
            e.pos.dx > MediaQuery.of(context).size.width + 50 ||
            e.pos.dy < -50 ||
            e.pos.dy > MediaQuery.of(context).size.height + 50,
      );

      // Spawn Enemies - Increasing difficulty
      if (lastSpawnTime == null ||
          DateTime.now().difference(lastSpawnTime!).inMilliseconds >
              (1200 / speedFactor).clamp(300, 1500)) {
        enemies.add(_createEnemy());
        lastSpawnTime = DateTime.now();
        speedFactor += 0.01;
        score += 10;
      }

      // Collision Check
      for (var enemy in enemies) {
        if ((enemy.pos - playerPos).distance < 25) {
          _gameOver();
          break;
        }
      }
    });
  }

  VoidEnemy _createEnemy() {
    // Spawn from edges
    double side = random.nextDouble();
    Offset pos;
    if (side < 0.25) {
      // Top
      pos = Offset(
        random.nextDouble() * MediaQuery.of(context).size.width,
        -30,
      );
    } else if (side < 0.5) {
      // Bottom
      pos = Offset(
        random.nextDouble() * MediaQuery.of(context).size.width,
        MediaQuery.of(context).size.height + 30,
      );
    } else if (side < 0.75) {
      // Left
      pos = Offset(
        -30,
        random.nextDouble() * MediaQuery.of(context).size.height,
      );
    } else {
      // Right
      pos = Offset(
        MediaQuery.of(context).size.width + 30,
        random.nextDouble() * MediaQuery.of(context).size.height,
      );
    }

    // Direction towards center with some randomness
    Offset target = Offset(
      MediaQuery.of(context).size.width / 2 + (random.nextDouble() - 0.5) * 100,
      MediaQuery.of(context).size.height / 2 +
          (random.nextDouble() - 0.5) * 100,
    );
    Offset dir = (target - pos);
    dir = Offset(dir.dx / dir.distance, dir.dy / dir.distance);

    return VoidEnemy(
      pos: pos,
      dir: dir,
      speed: (3.0 + random.nextDouble() * 2) * speedFactor,
      color: Colors.greenAccent,
    );
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
      DatabaseService(uid: user.uid).updateScore('vector_void', score);
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
          onPanUpdate: (details) {
            if (isStarted && !isGameOver && !isPaused) {
              setState(() {
                playerPos += details.delta;
              });
            }
          },
          onTapDown: (_) {
            if (isPaused) return;
            if (!isStarted || isGameOver) _startGame();
          },
          child: Stack(
            children: [
              // Background Grid Overlay
              CustomPaint(painter: GridPainter(), size: Size.infinite),

              // Game Visualizer
              CustomPaint(
                painter: VoidPainter(
                  playerPos: playerPos,
                  enemies: enemies,
                  isGameOver: isGameOver,
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
                        Shadow(color: Colors.greenAccent, blurRadius: 15),
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
                        color: Colors.greenAccent.withAlpha(100),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isGameOver ? 'VOIDED' : 'VECTOR VOID',
                          style: const TextStyle(
                            color: Colors.greenAccent,
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
                          'Drag to dodge incoming vectors.\nSurvive the void!',
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

class VoidEnemy {
  Offset pos;
  Offset dir;
  double speed;
  Color color;
  VoidEnemy({
    required this.pos,
    required this.dir,
    required this.speed,
    required this.color,
  });
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(5)
      ..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class VoidPainter extends CustomPainter {
  final Offset playerPos;
  final List<VoidEnemy> enemies;
  final bool isGameOver;

  VoidPainter({
    required this.playerPos,
    required this.enemies,
    required this.isGameOver,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Player
    final playerPaint = Paint()
      ..color = isGameOver ? Colors.red : Colors.greenAccent
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    canvas.drawCircle(playerPos, 15, playerPaint);
    canvas.drawCircle(playerPos, 8, Paint()..color = Colors.white);

    // Enemies
    final enemyPaint = Paint()
      ..color = Colors.greenAccent.withAlpha(150)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    for (var enemy in enemies) {
      Path path = Path();
      path.moveTo(enemy.pos.dx, enemy.pos.dy - 10);
      path.lineTo(enemy.pos.dx + 8, enemy.pos.dy + 8);
      path.lineTo(enemy.pos.dx - 8, enemy.pos.dy + 8);
      path.close();
      canvas.drawPath(path, enemyPaint);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withAlpha(50)
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant VoidPainter oldDelegate) => true;
}
