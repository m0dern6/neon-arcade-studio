import 'package:firebase_auth/firebase_auth.dart';
import 'package:games_services/games_services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; 
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ValueNotifier<bool> isSyncingProfile = ValueNotifier(false);
  final ValueNotifier<bool> isPgsLinked = ValueNotifier(false);

  // The Web Client ID from Google Cloud Console (used as serverClientId)
  static const String _serverClientId =
      '280328504204-i08tpigvu33a05jevdnocrauvbrovupg.apps.googleusercontent.com';

  Stream<User?> get user => _auth.authStateChanges().map((u) {
    if (u != null) {
      isPgsLinked.value = isUserLinkedWithPlayGames(u);
    } else {
      isPgsLinked.value = false;
    }
    return u;
  });

  bool isUserLinkedWithPlayGames(User user) {
    return user.providerData.any((p) => p.providerId == 'playgames.google.com');
  }

  /// Attempts to recover existing Google Master session silently.
  Future<User?> initializeAuth() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
      final GoogleSignInAccount? masterAccount = await googleSignIn.signInSilently();
      
      if (masterAccount != null) {
        final GoogleSignInAuthentication gAuth = await masterAccount.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          idToken: gAuth.idToken,
          accessToken: gAuth.accessToken,
        );
        final UserCredential userCredential = await _auth.signInWithCredential(credential);
        final User? user = userCredential.user;
        
        if (user != null) {
          isPgsLinked.value = isUserLinkedWithPlayGames(user);
          // Try to sync Play Games silently
          await syncPlayGames(user, masterAccount.email, silentOnly: true);
        }
        return user;
      }
      return _auth.currentUser;
    } catch (e) {
      if (kDebugMode) debugPrint("AuthService: Silent initialization failed: $e");
      return _auth.currentUser;
    }
  }

  /// Interactive Google Master Login
  Future<User?> signInWithGoogleMaster(BuildContext context) async {
    isSyncingProfile.value = true;
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
      // We don't sign out first unless necessary, but let's keep it clean
      final GoogleSignInAccount? masterAccount = await googleSignIn.signIn();
      
      if (masterAccount == null) return null;

      final GoogleSignInAuthentication gAuth = await masterAccount.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        idToken: gAuth.idToken,
        accessToken: gAuth.accessToken,
      );
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        // After master login, attempt a SEAMLESS Play Games sync
        await syncPlayGames(user, masterAccount.email, silentOnly: false);
      }
      return user;
    } catch (e) {
      if (kDebugMode) debugPrint("AuthService: Google Master sign-in failed: $e");
      return null;
    } finally {
      isSyncingProfile.value = false;
    }
  }

  /// Synchronizes Play Games ID silently.
  /// No UI prompts, no dialogs. If it fails, it just returns.
  Future<void> syncPlayGames(
    User user, 
    String masterEmail, 
    {required bool silentOnly}
  ) async {
    try {
      final googleSignInGames = GoogleSignIn(
        signInOption: SignInOption.games,
        serverClientId: _serverClientId,
        scopes: ['email'],
      );

      // 1. Try silent first
      GoogleSignInAccount? pgsAccount = await googleSignInGames.signInSilently();
      
      // 2. If silent failed and we are allowed to be interactive (but still silent UI-wise)
      if (pgsAccount == null && !silentOnly) {
        try {
          await GamesServices.signIn();
          pgsAccount = await googleSignInGames.signIn();
        } catch (e) {
          if (kDebugMode) debugPrint("AuthService: Silent-ish PGS selection fail: $e");
        }
      }

      // 3. Final Verification and Linking (ONLY if emails match)
      if (pgsAccount != null && pgsAccount.email == masterEmail) {
        final String? authCode = await GamesServices.getAuthCode(_serverClientId);
        if (authCode != null) {
          final AuthCredential pgCredential = PlayGamesAuthProvider.credential(
            serverAuthCode: authCode,
          );
          
          await user.linkWithCredential(pgCredential);
          isPgsLinked.value = true;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint("AuthService: PGS Sync Error: $e");
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
      await GoogleSignIn().signOut();
      isPgsLinked.value = false;
    } catch (e) {
      if (kDebugMode) debugPrint("Sign out error: $e");
    }
  }
}
