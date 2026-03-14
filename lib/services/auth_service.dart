import 'package:firebase_auth/firebase_auth.dart';
import 'package:games_services/games_services.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isSigningIn = false;

  // The Web Client ID from Google Cloud Console (used as serverClientId)
  static const String _serverClientId =
      '280328504204-i08tpigvu33a05jevdnocrauvbrovupg.apps.googleusercontent.com';

  Stream<User?> get user => _auth.authStateChanges();

  Future<User?> signInSilently() async {
    try {
      if (_auth.currentUser != null) return _auth.currentUser;

      // For Android, we can attempt a silent sign-in with Play Games.
      if (defaultTargetPlatform == TargetPlatform.android) {
        await GamesServices.signIn();
        return await _authenticateWithPlayGames();
      }
      return null;
    } catch (e) {
      print("Silent sign-in failed: $e");
      return null;
    }
  }

  Future<User?> signInWithPlayGames() async {
    if (_auth.currentUser != null) return _auth.currentUser;
    if (_isSigningIn) return null;
    _isSigningIn = true;

    try {
      if (defaultTargetPlatform != TargetPlatform.android) {
        print("Play Games Sign-In is only supported on Android.");
        return null;
      }

      // 1. Sign in to Google Play Games (shows the "Welcome" overlay)
      await GamesServices.signIn();

      // 2. Authenticate with Firebase using the Play Games account
      return await _authenticateWithPlayGames();
    } catch (e) {
      print("Play games sign-in error: $e");
      return null;
    } finally {
      _isSigningIn = false;
    }
  }

  Future<User?> _authenticateWithPlayGames() async {
    try {
      // 1. Get the server auth code from Play Games
      final String? authCode = await GamesServices.getAuthCode(_serverClientId);
      
      if (authCode == null) {
        print("Failed to get Play Games auth code.");
        return null;
      }

      // 2. Create a Firebase credential using the auth code
      final AuthCredential credential = PlayGamesAuthProvider.credential(
        serverAuthCode: authCode,
      );

      // 3. Sign in to Firebase
      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      
      return userCredential.user;
    } catch (e) {
      print("Firebase Play Games authentication failed: $e");
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
      // games_services doesn't typically require a manual sign out for the overlay,
      // but it's good to clear Firebase state.
    } catch (e) {
      print("Sign out error: $e");
    }
  }
}
