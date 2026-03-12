import 'package:flutter/material.dart';

class PauseOverlay extends StatelessWidget {
  final VoidCallback onResume;
  final VoidCallback onHome;
  final VoidCallback onToggleMusic;
  final VoidCallback onToggleSfx;
  final bool isMusicEnabled;
  final bool isSfxEnabled;

  const PauseOverlay({
    super.key,
    required this.onResume,
    required this.onHome,
    required this.onToggleMusic,
    required this.onToggleSfx,
    required this.isMusicEnabled,
    required this.isSfxEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withAlpha(200),
      child: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A4A),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.cyanAccent.withAlpha(100),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(color: Colors.cyanAccent.withAlpha(50), blurRadius: 20),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'PAUSED',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 40),
              _MenuButton(
                label: 'RESUME',
                icon: Icons.play_arrow,
                color: Colors.cyanAccent,
                onPressed: onResume,
              ),
              const SizedBox(height: 16),
              _MenuButton(
                label: isMusicEnabled ? 'MUSIC ON' : 'MUSIC OFF',
                icon: isMusicEnabled ? Icons.music_note : Icons.music_off,
                color: Colors.pinkAccent,
                onPressed: onToggleMusic,
              ),
              const SizedBox(height: 16),
              _MenuButton(
                label: isSfxEnabled ? 'SFX ON' : 'SFX OFF',
                icon: isSfxEnabled ? Icons.volume_up : Icons.volume_off,
                color: Colors.purpleAccent,
                onPressed: onToggleSfx,
              ),
              const SizedBox(height: 16),
              _MenuButton(
                label: 'EXIT TO HOME',
                icon: Icons.home,
                color: Colors.amberAccent,
                onPressed: onHome,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _MenuButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: color.withAlpha(30),
          border: Border.all(color: color.withAlpha(100), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
