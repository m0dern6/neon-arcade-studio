import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/studio_home.dart';
import 'screens/splash_screen.dart';
import 'services/database_service.dart';
import 'services/settings_manager.dart';

import 'game/audio_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Enable edge-to-edge so the app draws behind the status and navigation bars
  // on all Android versions (API 21+) and iOS.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarIconBrightness: Brightness.light,
    statusBarIconBrightness: Brightness.light,
  ));

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );
  await DatabaseService.initializeSync();
  await SettingsManager().init();
  runApp(const ProviderScope(child: NeonApp()));
}

class NeonApp extends StatefulWidget {
  const NeonApp({super.key});

  @override
  State<NeonApp> createState() => _NeonAppState();
}

class _NeonAppState extends State<NeonApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      AudioManager().pauseMusic();
    } else if (state == AppLifecycleState.resumed) {
      AudioManager().resumeMusic();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neon Arcade Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0D2B),
        useMaterial3: true,
        fontFamily: 'monospace', // Gives a tech/arcade feel
      ),
      home: const SplashScreen(),
    );
  }
}
