import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:games_services/games_services.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isSigningIn = false;

  // Revert back to the fully integrated Google Sign-In structure
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId:
        '280328504204-i08tpigvu33a05jevdnocrauvbrovupg.apps.googleusercontent.com',
    scopes: ['email'],
  );

  Stream<User?> get user => _auth.authStateChanges();

  Future<User?> signInSilently() async {
    try {
      // Silent flow should never trigger UI.
      if (_auth.currentUser != null) return _auth.currentUser;

      final GoogleSignInAccount? googleUser = await _googleSignIn
          .signInSilently();
      if (googleUser == null) return null;
      return await _authenticateWithGoogle(googleUser);
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
      // Authenticate with Firebase first; this should always drive the UI popup.
      GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final user = await _authenticateWithGoogle(googleUser);

      // Best-effort Play Games link. Don't fail sign-in if this step fails.
      try {
        await GamesServices.signIn();
      } catch (e) {
        print("Play Games overlay warning: $e");
      }

      return user;
    } catch (e) {
      print("Play games pure sign-in error: $e");
      return null;
    } finally {
      _isSigningIn = false;
    }
  }

  Future<User?> _authenticateWithGoogle(GoogleSignInAccount googleUser) async {
    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final UserCredential userCredential = await _auth.signInWithCredential(
      credential,
    );
    return userCredential.user;
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      print("Sign out error: $e");
    }
  }
}
