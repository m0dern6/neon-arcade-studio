import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/game_data.dart';
import '../game/neon_gravity.dart';
import '../game/orbital_strike.dart';
import '../game/pulse_dash.dart';
import '../game/cyber_stack.dart';
import '../game/vector_void.dart';
import '../game/audio_manager.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

class StudioHomeScreen extends StatefulWidget {
  const StudioHomeScreen({super.key});

  @override
  State<StudioHomeScreen> createState() => _StudioHomeScreenState();
}

class _StudioHomeScreenState extends State<StudioHomeScreen> {
  final AuthService _authService = AuthService();
  Map<String, int> bestScores = {};

  @override
  void initState() {
    super.initState();
    AudioManager().playMusic('background.mp3');
    _autoSignIn(); // Call auto sign-in when the widget initializes
  }

  void _autoSignIn() async {
    try {
      await _authService.signInSilently();
    } catch (e) {
      print("Auto sign-in failed: $e");
    }
  }

  Widget _buildProfileHeader(User? user) {
    if (user == null) {
      return ElevatedButton.icon(
        onPressed: () => _authService.signInWithPlayGames(),
        icon: const Icon(Icons.games),
        label: const Text('PLAY GAMES'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withAlpha(20),
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withAlpha(50)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  user.displayName ?? 'Player',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                GestureDetector(
                  onTap: () => _authService.signOut(),
                  child: Text(
                    'SIGN OUT',
                    style: TextStyle(
                      color: Colors.white.withAlpha(150),
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            CircleAvatar(
              radius: 20,
              backgroundImage: user.photoURL != null
                  ? NetworkImage(user.photoURL!)
                  : null,
              child: user.photoURL == null ? const Icon(Icons.person) : null,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.user,
      builder: (context, authSnapshot) {
        final user = authSnapshot.data;

        return StreamBuilder<DocumentSnapshot>(
          stream: user != null
              ? DatabaseService(uid: user.uid).userData
              : const Stream.empty(),
          builder: (context, scoreSnapshot) {
            if (scoreSnapshot.hasData && scoreSnapshot.data!.exists) {
              final data = scoreSnapshot.data!.data() as Map<String, dynamic>;
              bestScores = data.map(
                (key, value) => MapEntry(key, value is int ? value : 0),
              );
            }

            final List<GameMetadata> games = [
              GameMetadata(
                id: 'neon_gravity',
                title: 'Neon Gravity',
                description: 'Defy gravity in a high-speed neon runner.',
                icon: Icons.unfold_more,
                themeColor: Colors.cyanAccent,
                gameWidget: const NeonGravityGame(),
              ),
              GameMetadata(
                id: 'orbital',
                title: 'Orbital Strike',
                description: 'Defend the core from circular threats.',
                icon: Icons.blur_circular,
                themeColor: Colors.pinkAccent,
                gameWidget: const OrbitalStrikeGame(),
              ),
              GameMetadata(
                id: 'pulse_dash',
                title: 'Pulse Dash',
                description: 'Master the rhythm in this reaction test.',
                icon: Icons.bolt,
                themeColor: Colors.yellowAccent,
                gameWidget: const PulseDashGame(),
              ),
              GameMetadata(
                id: 'cyber_stack',
                title: 'Cyber Stack',
                description: 'Stack the blocks with perfect precision.',
                icon: Icons.layers,
                themeColor: Colors.purpleAccent,
                gameWidget: const CyberStackGame(),
              ),
              GameMetadata(
                id: 'vector_void',
                title: 'Vector Void',
                description: 'Dodge the incoming geometric vectors.',
                icon: Icons.change_history,
                themeColor: Colors.greenAccent,
                gameWidget: const VectorVoidGame(),
              ),
            ];

            return Scaffold(
              body: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0D0D2B),
                      Color(0xFF1A1A4A),
                      Color(0xFF0D0D2B),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: CustomScrollView(
                    slivers: [
                      // Header
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                        'NEON ARCADE',
                                        style: TextStyle(
                                          color: Colors.white.withAlpha(200),
                                          fontSize: 14,
                                          letterSpacing: 4,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                      .animate()
                                      .fadeIn(duration: 600.ms)
                                      .slideX(begin: -0.2),
                                  const SizedBox(height: 8),
                                  const Text(
                                        'STUDIO',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 42,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -1,
                                        ),
                                      )
                                      .animate()
                                      .fadeIn(delay: 200.ms)
                                      .slideX(begin: -0.1),
                                  const SizedBox(height: 20),
                                  Container(
                                    height: 4,
                                    width: 60,
                                    decoration: BoxDecoration(
                                      color: Colors.cyanAccent,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.cyanAccent.withAlpha(
                                            150,
                                          ),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              _buildProfileHeader(user),
                            ],
                          ),
                        ),
                      ),

                      // Game Grid
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 10,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final game = games[index];
                            final best = bestScores[game.id] ?? 0;
                            return Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: GameCard(game: game, bestScore: best),
                                )
                                .animate(delay: (100 * index).ms)
                                .fadeIn(duration: 500.ms)
                                .slideY(begin: 0.2, curve: Curves.easeOutQuad);
                          }, childCount: games.length),
                        ),
                      ),

                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              'STAY TUNED FOR MORE GAMES',
                              style: TextStyle(
                                color: Colors.white.withAlpha(50),
                                fontSize: 12,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class GameCard extends StatelessWidget {
  final GameMetadata game;
  final int bestScore;

  const GameCard({super.key, required this.game, required this.bestScore});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => game.gameWidget),
        );
      },
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Colors.white.withAlpha(10),
          border: Border.all(color: Colors.white.withAlpha(20), width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -30,
              top: -30,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: game.themeColor.withAlpha(40),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: game.themeColor.withAlpha(30),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          game.icon,
                          color: game.themeColor,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            game.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'BEST: $bestScore',
                            style: TextStyle(
                              color: game.themeColor.withAlpha(200),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Text(
                    game.description,
                    style: TextStyle(
                      color: Colors.white.withAlpha(150),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
