import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/game_data.dart';
import '../game/neon_gravity.dart';
import '../game/orbital_strike.dart';
import '../game/cyber_slice.dart';
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
  Map<String, int> localBestScores = {};
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      _loadUserScores(user);
    });
    _autoSignIn(); // Call auto sign-in when the widget initializes
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUserScores(User? user) async {
    final db = DatabaseService(uid: user?.uid);
    
    if (user != null) {
      await db.migrateGuestScores(); // Ensure migration on every login/refresh
      await db.syncPendingScores();
    }
    
    final cached = await db.getCachedBestScores();
    if (mounted) {
      setState(() {
        localBestScores = cached;
      });
    }
  }

  void _autoSignIn() async {
    try {
      // 1. Try to initialize and recover the unified session
      User? user = await _authService.initializeAuth();
      
      // 2. If no account is recovered, automatically open the sign-in box after frame
      if (user == null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted) {
            await _authService.signInWithGoogleMaster(context);
          }
        });
      }
    } catch (e) {
      print("Auto sign-in failed: $e");
    }
  }

  Future<void> _handleSignOut() async {
    bool isCanceled = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withAlpha(200),
      builder: (context) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.cyanAccent),
              const SizedBox(height: 24),
              const Text(
                'SIGNING OUT...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Tap anywhere or press back to cancel',
                style: TextStyle(
                  color: Colors.white.withAlpha(150),
                  fontSize: 12,
                  decoration: TextDecoration.none,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      isCanceled = true;
    });

    try {
      // 1.5 second delay to give user time to cancel
      await Future.delayed(const Duration(milliseconds: 1500));

      if (!isCanceled) {
        await _authService.signOut();
        if (mounted) {
          Navigator.of(context).pop(); // Close the dialog
        }
      }
    } catch (e) {
      if (!isCanceled && mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Map<String, int> _mergeBestScores(
    Map<String, int> local,
    Map<String, int> remote,
  ) {
    final merged = <String, int>{...local};
    for (final entry in remote.entries) {
      final current = merged[entry.key] ?? 0;
      merged[entry.key] = entry.value > current ? entry.value : current;
    }
    return merged;
  }

  void _showLeaderboard(BuildContext context, GameMetadata game) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF13133A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(game.icon, color: game.themeColor),
                    const SizedBox(width: 10),
                    Text(
                      '${game.title} Leaderboard',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: DatabaseService.leaderboardStream(game.id),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snapshot.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return const Center(
                          child: Text(
                            'No scores yet',
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final row = docs[index].data();
                          final name =
                              (row['displayName'] as String?) ?? 'Player';
                          final score = (row[game.id] as int?) ?? 0;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(14),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 34,
                                  child: Text(
                                    '#${index + 1}',
                                    style: TextStyle(
                                      color: game.themeColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                Text(
                                  '$score',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileHeader(User? user) {
    if (user == null) {
      return ElevatedButton(
        onPressed: () => _authService.signInWithGoogleMaster(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withAlpha(20),
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withAlpha(50)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Text(
          'SIGN IN',
          style: TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.bold),
        ),
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: _authService.isSyncingProfile,
      builder: (context, isSyncing, _) {
        if (isSyncing) {
          return Row(
            children: [
              Text(
                'SYNCING...',
                style: TextStyle(
                  color: Colors.white.withAlpha(150),
                  fontSize: 10,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 8),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                ),
              ),
            ],
          );
        }

        // Use the absolute latest user data after sync finishes
        final latestUser = FirebaseAuth.instance.currentUser ?? user;

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          latestUser.displayName ?? 'Player',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: _handleSignOut,
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
                      backgroundColor: Colors.white10,
                      backgroundImage: latestUser.photoURL != null
                          ? NetworkImage(latestUser.photoURL!)
                          : null,
                      child: latestUser.photoURL == null ? const Icon(Icons.person, color: Colors.white54) : null,
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.user,
      builder: (context, authSnapshot) {
        final user = authSnapshot.data;
        if (user != null) {
          print("StudioHomeScreen: Building UI for User: ${user.uid}");
          print("StudioHomeScreen: User Data -> Name: ${user.displayName}, Photo: ${user.photoURL}");
        } else {
          print("StudioHomeScreen: Building UI for Guest Mode");
        }

        return StreamBuilder<Map<String, dynamic>>(
          stream: DatabaseService(uid: user?.uid).userDataStream,
          initialData: user == null ? Map<String, dynamic>.from(localBestScores) : null,
          builder: (context, scoreSnapshot) {
            final remoteBestScores = <String, int>{};
            if (scoreSnapshot.hasData && scoreSnapshot.data != null) {
              final data = scoreSnapshot.data!;
              for (final entry in data.entries) {
                if (entry.value is num) {
                  remoteBestScores[entry.key] = (entry.value as num).toInt();
                }
              }
            }

            final bestScores = _mergeBestScores(
              localBestScores,
              remoteBestScores,
            );

            final String? currentUid = user?.uid;

            final List<GameMetadata> games = [
              GameMetadata(
                id: 'neon_gravity',
                title: 'Neon Gravity',
                description: 'Defy gravity in a high-speed neon runner.',
                icon: Icons.unfold_more,
                themeColor: Colors.cyanAccent,
                gameWidget: NeonGravityGame(uid: currentUid),
              ),
              GameMetadata(
                id: 'orbital',
                title: 'Orbital Strike',
                description: 'Defend the core from circular threats.',
                icon: Icons.blur_circular,
                themeColor: Colors.pinkAccent,
                gameWidget: OrbitalStrikeGame(uid: currentUid),
              ),
              GameMetadata(
                id: 'pulse_dash', // Keeping ID same for score compatibility
                title: 'Cyber Slice',
                description: 'Slice the neon cores and avoid data bombs.',
                icon: Icons.content_cut,
                themeColor: Colors.cyanAccent,
                gameWidget: CyberSliceGame(uid: currentUid),
              ),
              GameMetadata(
                id: 'cyber_stack',
                title: 'Cyber Stack',
                description: 'Stack the blocks with perfect precision.',
                icon: Icons.layers,
                themeColor: Colors.purpleAccent,
                gameWidget: CyberStackGame(uid: currentUid),
              ),
              GameMetadata(
                id: 'vector_void',
                title: 'Vector Void',
                description: 'Dodge the incoming geometric vectors.',
                icon: Icons.change_history,
                themeColor: Colors.greenAccent,
                gameWidget: VectorVoidGame(uid: currentUid),
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
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 20,
                                crossAxisSpacing: 20,
                                childAspectRatio: 0.8,
                              ),
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final game = games[index];
                            final best = bestScores[game.id] ?? 0;
                            return GameCard(
                                  game: game,
                                  bestScore: best,
                                  onLeaderboardTap: () {
                                    _showLeaderboard(context, game);
                                  },
                                )
                                .animate(delay: (100 * index).ms)
                                .fadeIn(duration: 500.ms)
                                .scaleXY(begin: 0.8, curve: Curves.easeOutBack);
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
  final VoidCallback onLeaderboardTap;

  const GameCard({
    super.key,
    required this.game,
    required this.bestScore,
    required this.onLeaderboardTap,
  });

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
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.black.withAlpha(80),
          border: Border.all(color: game.themeColor.withAlpha(120), width: 2),
          boxShadow: [
            BoxShadow(
              color: game.themeColor.withAlpha(50),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Background neon glow
            Positioned(
              right: -30,
              bottom: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: game.themeColor.withAlpha(30),
                  boxShadow: [
                    BoxShadow(
                      color: game.themeColor.withAlpha(60),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: game.themeColor.withAlpha(20),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: game.themeColor.withAlpha(100),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: game.themeColor.withAlpha(40),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Icon(
                          game.icon,
                          color: game.themeColor,
                          size: 28,
                        ),
                      ),
                      IconButton(
                        onPressed: onLeaderboardTap,
                        icon: Icon(
                          Icons.emoji_events,
                          color: game.themeColor,
                          size: 24,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: game.themeColor.withAlpha(20),
                          minimumSize: const Size(40, 40),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: game.themeColor.withAlpha(50),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          game.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                            shadows: [
                              Shadow(color: game.themeColor, blurRadius: 10),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: game.themeColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: game.themeColor.withAlpha(50),
                            ),
                          ),
                          child: Text(
                            'BEST: $bestScore',
                            style: TextStyle(
                              color: game.themeColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
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
