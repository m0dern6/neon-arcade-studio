import 'dart:async';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'studio_home.dart';
import '../game/audio_manager.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  double _progress = 0.0;
  String _statusText = "INITIALIZING CORE...";
  bool _isUpdateRequired = false;
  late AnimationController _pulseController;
  final String _playStoreUrl = "https://play.google.com/store/apps/details?id=com.google.android.play.games"; // Placeholder

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    AudioManager().playMusic('background.mp3');
    _startBootSequence();
  }

  Future<void> _startBootSequence() async {
    // 1. Initial Load
    await _updateProgress(0.2, "CHECKING ENCRYPTION...");
    await Future.delayed(const Duration(milliseconds: 500));

    // 2. Check for Updates
    await _updateProgress(0.4, "SCANNING FOR PATCHES...");
    await _checkForUpdates();

    if (_isUpdateRequired) {
      await _updateProgress(0.5, "VERSION EXPIRED");
      if (mounted) _showPlayStoreDialog();
      return; // Stop boot if update is required
    }

    // 3. Simulate In-game Asset Patching
    // Even if no "binary" update, we can simulate asset syncing for theme consistency
    await _simulateAssetPatching();

    await _updateProgress(1.0, "READY");
    await Future.delayed(const Duration(milliseconds: 500));
    _navigateToHome();
  }

  Future<void> _checkForUpdates() async {
    try {
      final Info = await PackageInfo.fromPlatform();
      int currentBuild = int.tryParse(Info.buildNumber) ?? 0;
      
      // MOCK logic: Suppose latest remote build is 10 (current is 6)
      // If build < 10, we require an update
      const int latestRemoteBuild = 10; 
      
      if (currentBuild < latestRemoteBuild) {
        // Only require update if it's a major jump
        // For minor jumps, we just do the "ingame themed update" simulation
        if (latestRemoteBuild - currentBuild > 5) {
           _isUpdateRequired = true;
        }
      }
    } catch (e) {
      _isUpdateRequired = false;
    }
  }

  Future<void> _simulateAssetPatching() async {
    final stages = [
      "FETCHING ASSETS...",
      "EXTRACTING SHADERS...",
      "SYNCING NEON DATA...",
      "FINALIZING PATCH..."
    ];

    for (int i = 0; i < stages.length; i++) {
      await _updateProgress(0.4 + (i + 1) * 0.15, stages[i]);
      await Future.delayed(Duration(milliseconds: 700 + (i * 100)));
    }
  }

  Future<void> _updateProgress(double target, String status) async {
    if (!mounted) return;
    setState(() => _statusText = status);
    
    const steps = 15;
    double start = _progress;
    double increment = (target - start) / steps;

    for (int i = 0; i < steps; i++) {
      await Future.delayed(const Duration(milliseconds: 15));
      if (mounted) {
        setState(() => _progress += increment);
      }
    }
  }

  void _showPlayStoreDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF13133A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.cyanAccent, width: 1)),
        title: const Text("UPDATE REQUIRED", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2)),
        content: const Text(
          "A major system update (v1.1.0) is available on the Play Store. Update now to continue the neon drift.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => _navigateToHome(), // Continue anyway for testing convenience
            child: const Text("SKIP (DEV MODE)", style: TextStyle(color: Colors.white24)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (await canLaunchUrl(Uri.parse(_playStoreUrl))) {
                await launchUrl(Uri.parse(_playStoreUrl));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent.withAlpha(50), foregroundColor: Colors.cyanAccent),
            child: const Text("UPDATE NOW"),
          ),
        ],
      ),
    );
  }

  void _navigateToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const StudioHomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 1000),
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030311),
      body: Stack(
        children: [
          // Background Glow
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [Colors.cyanAccent.withAlpha(20), Colors.transparent],
                  radius: 1.2,
                ),
              ),
            ),
          ),

          // Main Logo
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: Tween(begin: 0.98, end: 1.02).animate(
                    CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
                  ),
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.cyanAccent.withAlpha(80), blurRadius: 30, spreadRadius: 2)],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/splash.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, e, s) => const Icon(Icons.blur_circular, color: Colors.cyanAccent, size: 80),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                const Text(
                  "NEON ARCADE",
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 10, shadows: [Shadow(color: Colors.cyanAccent, blurRadius: 10)]),
                ),
              ],
            ),
          ),

          // Bottom UI
          Positioned(
            bottom: 80,
            left: 40,
            right: 40,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_statusText, style: TextStyle(color: Colors.cyanAccent.withAlpha(200), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    Text("${(_progress * 100).toInt()}%", style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace')),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Sliding Indicator
                Container(
                  height: 4,
                  width: double.infinity,
                  decoration: BoxDecoration(color: Colors.white.withAlpha(15), borderRadius: BorderRadius.circular(2)),
                  child: Stack(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: (MediaQuery.of(context).size.width - 80) * _progress,
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [BoxShadow(color: Colors.cyanAccent.withAlpha(200), blurRadius: 8, spreadRadius: 1)],
                        ),
                      ),
                      // Sliding Tip
                      Positioned(
                        left: ((MediaQuery.of(context).size.width - 80) * _progress) - 20,
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [Colors.transparent, Colors.white.withAlpha(150), Colors.transparent]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Text("BUILD: 1.0.0+6", style: TextStyle(color: Colors.white24, fontSize: 7, letterSpacing: 4)),
            ),
          ),
        ],
      ),
    );
  }
}
