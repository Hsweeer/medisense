import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// One saved skin scan result — enough to show a history list and
/// simple progress-over-time comparison, without needing to re-parse
/// chat messages.
class SkinScanRecord {
  const SkinScanRecord({
    this.id,
    required this.metrics, // label -> score (0.0-1.0)
    required this.imagePath,
    required this.date,
  });

  final String? id;
  final Map<String, double> metrics;
  final String? imagePath;
  final DateTime date;

  factory SkinScanRecord.fromMap(Map<String, dynamic> map, String id) {
    final rawMetrics = (map['metrics'] as Map?) ?? {};
    return SkinScanRecord(
      id: id,
      metrics: rawMetrics.map(
            (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
      ),
      imagePath: map['imagePath'],
      date: map['dateMs'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['dateMs'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'metrics': metrics,
    'imagePath': imagePath,
    'dateMs': date.millisecondsSinceEpoch,
  };
}

/// Handles all Firestore operations for skin scan history.
/// Stored at: users/{uid}/skinScans/{scanId}
class SkinScanFirestoreService {
  SkinScanFirestoreService._();

  static final SkinScanFirestoreService instance = SkinScanFirestoreService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  Future<void> saveScan(SkinScanRecord record) async {
    final uid = _uid;
    if (uid == null) {
      debugPrint('[SkinScanFirestoreService] saveScan: user not logged in');
      return;
    }
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('skinScans')
          .add(record.toMap());
      debugPrint('[SkinScanFirestoreService] saveScan: saved');
    } catch (e) {
      debugPrint('[SkinScanFirestoreService] saveScan: error — $e');
    }
  }

  /// Most recent scans first.
  Future<List<SkinScanRecord>> fetchScans() async {
    final uid = _uid;
    if (uid == null) {
      debugPrint('[SkinScanFirestoreService] fetchScans: user not logged in');
      return [];
    }
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('skinScans')
          .get();

      final records = snapshot.docs
          .map((doc) => SkinScanRecord.fromMap(doc.data(), doc.id))
          .toList();
      records.sort((a, b) => b.date.compareTo(a.date));

      debugPrint('[SkinScanFirestoreService] fetchScans: loaded ${records.length}');
      return records;
    } catch (e) {
      debugPrint('[SkinScanFirestoreService] fetchScans: error — $e');
      return [];
    }
  }

  Future<void> deleteScan(String scanId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('skinScans')
          .doc(scanId)
          .delete();
    } catch (e) {
      debugPrint('[SkinScanFirestoreService] deleteScan: error — $e');
    }
  }
}