import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/models/models.dart';

/// Stores the short personalized facts MedAI picks up while chatting
/// (symptoms mentioned, ongoing concerns, preferences) so the Profile
/// screen can surface "what MedAI has learned about you" — separate from
/// the raw chat transcripts.
///
/// Schema: users/{uid}/aiInsights/{insightId}
class AiInsightsFirestoreService {
  AiInsightsFirestoreService._();

  static final AiInsightsFirestoreService instance =
  AiInsightsFirestoreService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? _ref() {
    final uid = _uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).collection('aiInsights');
  }

  /// Live stream of every insight, newest first — used by ProfileProvider
  /// so the profile screen updates the moment MedAI learns something new.
  Stream<List<AiInsight>> watchInsights({int limit = 30}) {
    final ref = _ref();
    if (ref == null) return const Stream.empty();
    return ref
        .orderBy('createdAtMs', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
        snap.docs.map((d) => AiInsight.fromMap(d.data(), d.id)).toList());
  }

  Future<void> addInsight(AiInsight insight) async {
    final ref = _ref();
    if (ref == null) return;
    try {
      await ref.add(insight.toMap());
    } catch (e) {
      debugPrint('[AiInsightsFirestoreService] addInsight: error — $e');
    }
  }

  Future<void> deleteInsight(String id) async {
    final ref = _ref();
    if (ref == null) return;
    try {
      await ref.doc(id).delete();
    } catch (e) {
      debugPrint('[AiInsightsFirestoreService] deleteInsight: error — $e');
    }
  }
}