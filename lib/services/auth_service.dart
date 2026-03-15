import 'package:firebase_auth/firebase_auth.dart';
import 'package:games_services/games_services.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isSigningIn = false;
  final ValueNotifier<bool> isSyncingProfile = ValueNotifier(false);

  // The Web Client ID from Google Cloud Console (used as serverClientId)
  static const String _serverClientId =
      '280328504204-i08tpigvu33a05jevdnocrauvbrovupg.apps.googleusercontent.com';
  
  static const String _syncPrefsKey = 'google_profile_synced';

  Stream<User?> get user => _auth.authStateChanges();

  Future<User?> signInSilently() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        // 1. Silent sign-in to Google Play Games
        final String? authCode = await GamesServices.getAuthCode(_serverClientId);
        if (authCode != null) {
          final User? user = await _authenticateWithPlayGames(authCode);
          if (user != null) {
            print("AuthService: Silent Play Games Sign-In Success!");
            // Automatically ensure profile is correct
            await ensureProfileSynced(user);
          }
          return _auth.currentUser;
        }
      }
      return _auth.currentUser;
    } catch (e) {
      print("Silent sign-in failed: $e");
      return _auth.currentUser;
    }
  }

  Future<User?> signInWithPlayGames() async {
    if (_isSigningIn) return _auth.currentUser;
    _isSigningIn = true;

    try {
      if (defaultTargetPlatform != TargetPlatform.android) {
        print("Play Games Sign-In is only supported on Android.");
        return _auth.currentUser;
      }

      // 1. Explicitly sign in to Google Play Games (shows the "Welcome" overlay)
      await GamesServices.signIn();

      // 2. Get the auth code
      final String? authCode = await GamesServices.getAuthCode(_serverClientId);

      if (authCode == null) return _auth.currentUser;

      // 3. Authenticate with Firebase
      User? user = await _authenticateWithPlayGames(authCode);

      // 4. Force sync (can show UI since this is already an interactive flow)
      if (user != null) {
        await ensureProfileSynced(user, forceInteractive: true);
      }
      return _auth.currentUser;
    } catch (e) {
      print("Play games sign-in error: $e");
      return _auth.currentUser;
    } finally {
      _isSigningIn = false;
    }
  }

  Future<User?> _authenticateWithPlayGames(String authCode) async {
    try {
      // Create a Firebase credential using the auth code
      // Create a Firebase credential using the auth code
      final AuthCredential credential = PlayGamesAuthProvider.credential(
        serverAuthCode: authCode,
      );

      // Sign in to Firebase
      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );

      final User? user = userCredential.user;
      if (user != null) {
        print("AuthService: Firebase Sign-In Success!");
        print("AuthService: UID - ${user.uid}");
        print("AuthService: Display Name - ${user.displayName}");
        print("AuthService: Photo URL - ${user.photoURL}");
        print(
          "AuthService: Provider Data - ${user.providerData.map((p) => p.providerId).toList()}",
        );
      }
      return user;
    } catch (e) {
      print("Firebase Play Games authentication failed: $e");
      return null;
    }
  }

  /// Attempts to fetch the user's primary Google profile silently.
  /// Ensures the Firebase user profile matches their Google Identity.
  /// It tries silently first. If it has NEVER synced before, it allows one interactive prompt.
  Future<void> ensureProfileSynced(User user, {bool forceInteractive = false}) async {
    isSyncingProfile.value = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool alreadySynced = prefs.getBool(_syncPrefsKey) ?? false;
      
      print("AuthService: Starting Profile Sync Check. AlreadySynced: $alreadySynced");

      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: _serverClientId,
        scopes: ['profile', 'email'],
      );

      // 1. Always try silent first
      GoogleSignInAccount? googleAccount = await googleSignIn.signInSilently();
      
      // 2. If silent fails, and we haven't synced ever OR we are forcing it, try interactive
      if (googleAccount == null && (!alreadySynced || forceInteractive)) {
        print("AuthService: Silent sync failed and never synced before. Prompting once...");
        googleAccount = await googleSignIn.signIn();
      }
      
      if (googleAccount != null) {
        print("AuthService: Syncing with Google Account: ${googleAccount.displayName}");
        
        await user.updateDisplayName(googleAccount.displayName);
        await user.updatePhotoURL(googleAccount.photoUrl);
        await user.reload();
        
        // Mark as synced
        await prefs.setBool(_syncPrefsKey, true);
        print("AuthService: Profile Sync Complete.");
      } else {
        print("AuthService: No Google account selected for sync.");
      }
    } catch (e, stack) {
      print("AuthService: Profile Sync Error: $e");
      print(stack);
    } finally {
      isSyncingProfile.value = false;
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
      await GoogleSignIn().signOut();
    } catch (e) {
      print("Sign out error: $e");
    }
  }
}
