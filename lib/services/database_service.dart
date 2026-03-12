import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String uid;

  DatabaseService({required this.uid});

  // Collection reference
  late final CollectionReference _scoresCollection = _db.collection('scores');

  // Update user score in Firestore
  Future<void> updateScore(String gameId, int score) async {
    try {
      final docRef = _scoresCollection.doc(uid);
      final doc = await docRef.get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final currentBest = (data[gameId] ?? 0) as int;

        if (score > currentBest) {
          await docRef.update({
            gameId: score,
            'last_updated': FieldValue.serverTimestamp(),
          });
        }
      } else {
        await docRef.set({
          gameId: score,
          'uid': uid,
          'displayName': FirebaseAuth.instance.currentUser?.displayName,
          'last_updated': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print("Error updating score: $e");
    }
  }

  // Get single game best score for current user
  Future<int> getBestScore(String gameId) async {
    try {
      final doc = await _scoresCollection.doc(uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        return (data[gameId] ?? 0) as int;
      }
      return 0;
    } catch (e) {
      print("Error getting best score: $e");
      return 0;
    }
  }

  // Get all high scores for current user
  Stream<DocumentSnapshot> get userData {
    return _scoresCollection.doc(uid).snapshots();
  }
}
