import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String? uid;

  static StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  static bool _syncInitialized = false;
  static final Map<String, Timer> _retryTimers = <String, Timer>{};
  static final Map<String, int> _retryAttempts = <String, int>{};

  static const String _localBestPrefix = 'local_best_scores_';
  static const String _pendingPrefix = 'pending_scores_';
  static const String _guestScoresKey = 'guest_best_scores';
  static const int _maxRetryDelaySeconds = 60;

  DatabaseService({this.uid});

  // Collection reference
  late final CollectionReference _scoresCollection = _db.collection('scores');

  static Future<void> initializeSync() async {
    if (_syncInitialized) return;
    _syncInitialized = true;

    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) async {
          if (results.contains(ConnectivityResult.none)) return;

          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser == null) return;

          await DatabaseService(uid: currentUser.uid).syncPendingScores();
        });
  }

  static Future<void> disposeSync() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    _syncInitialized = false;
  }

  Future<void> updateScore(String gameId, int score) async {
    // 1. Always update the local "contextual" score (either guest or specific user)
    final int localBest = await _saveLocalBestScore(gameId, score);

    // 2. If no user is signed in, we only save to the general guest pool as well
    if (uid == null) {
      await _saveGuestScore(gameId, score);
      return;
    }

    // 3. If signed in, attempt to sync with Firestore
    try {
      final doc = await _scoresCollection
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));
      int remoteBest = 0;
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        remoteBest = (data[gameId] as num?)?.toInt() ?? 0;
      }

      if (localBest > remoteBest) {
        await _pushScoreToFirestore(gameId, localBest);
        await _removePendingScore(gameId);
      } else if (remoteBest > localBest) {
        await _saveLocalBestScore(gameId, remoteBest);
      }
    } catch (e) {
      await _savePendingScore(gameId, localBest);
      print('Error updating score, saved for sync: $e');
      _scheduleRetrySync();
    }
  }

  /// Migrates scores from the guest pool to a newly signed-in account.
  /// If the account already has scores in Firebase, the guest scores are cleared
  /// without overwriting the existing cloud data (priority goes to Cloud).
  Future<void> migrateGuestScores() async {
    if (uid == null) return;

    final guestScores = await _readIntMap(_guestScoresKey);
    if (guestScores.isEmpty) return;

    try {
      final doc = await _scoresCollection.doc(uid).get();
      final bool hasRemoteData = doc.exists && doc.data() != null;

      if (!hasRemoteData) {
        // New account or no remote scores: Push all guest scores to Firestore
        final batch = _db.batch();
        final Map<String, dynamic> dataToSet = {
          'uid': uid,
          'displayName':
              FirebaseAuth.instance.currentUser?.displayName ?? 'Player',
          'last_updated': FieldValue.serverTimestamp(),
        };

        guestScores.forEach((gameId, score) {
          dataToSet[gameId] = score;
          _saveLocalBestScore(gameId, score); // Also update user-specific local
        });

        batch.set(_scoresCollection.doc(uid), dataToSet, SetOptions(merge: true));
        await batch.commit();
      } else {
        // Account exists: Discard guest scores as per user request
        print("Account already has scores. Discarding local guest scores.");
      }

      // In both cases, clear the guest pool once we've crossed the "login" threshold
      await _clearGuestScores();
    } catch (e) {
      print("Migration failed: $e");
    }
  }

  Future<void> syncPendingScores() async {
    if (uid == null) return;
    final pending = await _readIntMap(_pendingStorageKey);
    if (pending.isEmpty) return;

    final keys = List<String>.from(pending.keys);
    var hasFailures = false;
    for (final gameId in keys) {
      final score = pending[gameId] ?? 0;
      try {
        final doc = await _scoresCollection
            .doc(uid)
            .get(const GetOptions(source: Source.serverAndCache));
        int remoteBest = 0;
        if (doc.exists && doc.data() != null) {
          final data = doc.data() as Map<String, dynamic>;
          remoteBest = (data[gameId] as num?)?.toInt() ?? 0;
        }

        if (score > remoteBest) {
          await _pushScoreToFirestore(gameId, score);
        } else if (remoteBest > score) {
          await _saveLocalBestScore(gameId, remoteBest);
        }
        pending.remove(gameId);
      } catch (_) {
        hasFailures = true;
      }
    }

    await _writeIntMap(_pendingStorageKey, pending);

    if (hasFailures && pending.isNotEmpty) {
      _scheduleRetrySync();
    } else {
      _clearRetryState();
    }
  }

  Future<Map<String, int>> getCachedBestScores() async {
    if (uid == null) {
      return _readIntMap(_guestScoresKey);
    }
    return _readIntMap(_localBestStorageKey);
  }

  // Get single game best score
  Future<int> getBestScore(String gameId) async {
    try {
      final localScores = await getCachedBestScores();
      final localBest = localScores[gameId] ?? 0;

      if (uid == null) return localBest;

      final doc = await _scoresCollection.doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        final remoteBest = (data[gameId] as num?)?.toInt() ?? 0;
        return remoteBest > localBest ? remoteBest : localBest;
      }
      return localBest;
    } catch (e) {
      print("Error getting best score: $e");
      final localScores = await getCachedBestScores();
      return localScores[gameId] ?? 0;
    }
  }

  // Get all high scores for current user
  Stream<DocumentSnapshot> get userData {
    if (uid == null) return const Stream.empty();
    return _scoresCollection.doc(uid).snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> leaderboardStream(
    String gameId, {
    int limit = 20,
  }) {
    return FirebaseFirestore.instance
        .collection('scores')
        .where(gameId, isGreaterThan: 0)
        .orderBy(gameId, descending: true)
        .limit(limit)
        .snapshots();
  }

  Future<void> _pushScoreToFirestore(String gameId, int score) async {
    if (uid == null) return;
    final docRef = _scoresCollection.doc(uid);
    await docRef.set({
      gameId: score,
      'uid': uid,
      'displayName': FirebaseAuth.instance.currentUser?.displayName ?? 'Player',
      'last_updated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<int> _saveLocalBestScore(String gameId, int score) async {
    final key = uid == null ? _guestScoresKey : _localBestStorageKey;
    final map = await _readIntMap(key);
    final current = map[gameId] ?? 0;
    final next = score > current ? score : current;
    map[gameId] = next;
    await _writeIntMap(key, map);
    return next;
  }

  Future<void> _saveGuestScore(String gameId, int score) async {
    final map = await _readIntMap(_guestScoresKey);
    final current = map[gameId] ?? 0;
    if (score > current) {
      map[gameId] = score;
      await _writeIntMap(_guestScoresKey, map);
    }
  }

  Future<void> _clearGuestScores() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_guestScoresKey);
  }

  Future<void> _savePendingScore(String gameId, int score) async {
    if (uid == null) return;
    final pending = await _readIntMap(_pendingStorageKey);
    final current = pending[gameId] ?? 0;
    pending[gameId] = score > current ? score : current;
    await _writeIntMap(_pendingStorageKey, pending);
  }

  Future<void> _removePendingScore(String gameId) async {
    if (uid == null) return;
    final pending = await _readIntMap(_pendingStorageKey);
    pending.remove(gameId);
    await _writeIntMap(_pendingStorageKey, pending);
  }

  Future<Map<String, int>> _readIntMap(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};

      return decoded.map((k, v) {
        final value = v is int ? v : int.tryParse(v.toString()) ?? 0;
        return MapEntry(k, value);
      });
    } catch (e) {
      return {};
    }
  }

  Future<void> _writeIntMap(String key, Map<String, int> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
  }

  void _scheduleRetrySync() {
    if (uid == null) return;
    _retryTimers[uid!]?.cancel();

    final nextAttempt = (_retryAttempts[uid!] ?? 0) + 1;
    _retryAttempts[uid!] = nextAttempt;

    final delaySeconds = (1 << (nextAttempt - 1)).clamp(
      2,
      _maxRetryDelaySeconds,
    );
    _retryTimers[uid!] = Timer(Duration(seconds: delaySeconds), () async {
      await syncPendingScores();
    });
  }

  void _clearRetryState() {
    if (uid == null) return;
    _retryTimers[uid!]?.cancel();
    _retryTimers.remove(uid);
    _retryAttempts.remove(uid);
  }

  String get _localBestStorageKey => '$_localBestPrefix$uid';
  String get _pendingStorageKey => '$_pendingPrefix$uid';
}
