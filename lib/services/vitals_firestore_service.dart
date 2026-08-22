import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class VitalsRecord {
  const VitalsRecord({
    required this.bpm,
    required this.date,
    this.id,
  });

  final String? id;
  final double bpm;
  final DateTime date;

  factory VitalsRecord.fromMap(Map<String, dynamic> map, String id) {
    return VitalsRecord(
      id: id,
      bpm: (map['bpm'] as num?)?.toDouble() ?? 0,
      date: map['dateMs'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['dateMs'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'bpm': bpm,
    'dateMs': date.millisecondsSinceEpoch,
  };
}

class VitalsFirestoreService {
  VitalsFirestoreService._();

  static final VitalsFirestoreService instance = VitalsFirestoreService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  Future<void> saveScan(double bpm, {DateTime? date}) async {
    final uid = _uid;
    if (uid == null) {
      debugPrint('[VitalsFirestoreService] saveScan: user not logged in');
      return;
    }
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('vitals')
          .add(VitalsRecord(bpm: bpm, date: date ?? DateTime.now()).toMap());
      debugPrint('[VitalsFirestoreService] saveScan: saved $bpm BPM');
    } catch (e) {
      debugPrint('[VitalsFirestoreService] saveScan: error — $e');
    }
  }

  Future<List<VitalsRecord>> fetchScans() async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('vitals')
          .get();
      final records = snapshot.docs
          .map((doc) => VitalsRecord.fromMap(doc.data(), doc.id))
          .toList();
      records.sort((a, b) => b.date.compareTo(a.date));
      return records;
    } catch (e) {
      debugPrint('[VitalsFirestoreService] fetchScans: error — $e');
      return [];
    }
  }

  Future<double?> averageBpmLastDays(int days) async {
    final records = await fetchScans();
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final recent = records.where((r) => r.date.isAfter(cutoff)).toList();
    if (recent.isEmpty) return null;
    final average = recent.map((r) => r.bpm).reduce((a, b) => a + b) / recent.length;
    return average;
  }
}
