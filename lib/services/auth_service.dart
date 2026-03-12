import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:games_services/games_services.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Use generic google sign in without forcing the web client ID into it just yet.
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'https://www.googleapis.com/auth/games_lite'],
  );

  Stream<User?> get user => _auth.authStateChanges();

  Future<User?> signInSilently() async {
    try {
      try {
        await GamesServices.signIn();
      } catch (e) {
        print("native play games sign in blocked: $e");
      }
      return null;
    } catch (e) {
      print("Silent sign-in failed: $e");
      return null;
    }
  }

  Future<User?> signInWithPlayGames() async {
    try {
      // Step 1: Force native Games Services Sign In ONLY
      print("Starting pure native Play Games Sign in...");
      try {
        await GamesServices.signIn();
        print("GamesServices.signIn() SUCCESS!");
      } catch (e) {
        print("Native play games sign in error: $e");
        // If native fails, stop here to isolate the problem.
        return null;
      }
      return null;
    } catch (e) {
      print("Play games sign-in error: $e");
      return null;
    }
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
