import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const _localKey = 'local_skin_scan_history';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  Future<void> saveScan(SkinScanRecord record) async {
    final uid = _uid;
    if (uid == null) {
      debugPrint('[SkinScanFirestoreService] saveScan: user not logged in; saving locally');
      await _saveLocal(record);
      return;
    }

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('skinScans')
          .add(record.toMap());
      debugPrint('[SkinScanFirestoreService] saveScan: saved');
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'unauthenticated') {
        debugPrint('[SkinScanFirestoreService] Firestore denied; saving locally instead: ${e.code}');
        await _saveLocal(record);
        return;
      }
      debugPrint('[SkinScanFirestoreService] saveScan: error — $e');
      await _saveLocal(record);
    } catch (e) {
      debugPrint('[SkinScanFirestoreService] saveScan: error — $e');
      await _saveLocal(record);
    }
  }

  /// Most recent scans first. If Firestore is blocked by rules, the locally
  /// stored records still populate the same history UI.
  Future<List<SkinScanRecord>> fetchScans() async {
    final uid = _uid;
    if (uid == null) {
      debugPrint('[SkinScanFirestoreService] fetchScans: user not logged in');
      return _readLocalEntries();
    }

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('skinScans')
          .get();

      final remoteRecords = snapshot.docs
          .map((doc) => SkinScanRecord.fromMap(doc.data(), doc.id))
          .toList();
      final localRecords = await _readLocalEntries();
      final merged = [...remoteRecords, ...localRecords]
        ..sort((a, b) => b.date.compareTo(a.date));
      final deduped = _dedupe(merged);

      debugPrint('[SkinScanFirestoreService] fetchScans: loaded ${deduped.length}');
      return deduped;
    } catch (e) {
      debugPrint('[SkinScanFirestoreService] fetchScans: error — $e');
      return _readLocalEntries();
    }
  }

  Future<void> deleteScan(String scanId) async {
    final uid = _uid;
    if (uid == null) {
      await _deleteLocal(scanId);
      return;
    }
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('skinScans')
          .doc(scanId)
          .delete();
      await _deleteLocal(scanId);
    } catch (e) {
      debugPrint('[SkinScanFirestoreService] deleteScan: error — $e');
      await _deleteLocal(scanId);
    }
  }

  Future<void> _saveLocal(SkinScanRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await _readLocalEntries();
    final next = [...existing, record];
    final encoded = _dedupe(next)
        .map((item) => jsonEncode({
              ...item.toMap(),
              'id': item.id ?? 'local-${DateTime.now().microsecondsSinceEpoch}-skin',
            }))
        .toList();
    await prefs.setStringList(_localKey, encoded);
  }

  Future<List<SkinScanRecord>> _readLocalEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_localKey) ?? const <String>[];
    final entries = raw
        .map((item) => jsonDecode(item))
        .whereType<Map<String, dynamic>>()
        .map((map) => SkinScanRecord.fromMap(map, map['id']?.toString() ?? 'local-skin'))
        .toList();
    entries.sort((a, b) => b.date.compareTo(a.date));
    return _dedupe(entries);
  }

  Future<void> _deleteLocal(String scanId) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await _readLocalEntries();
    final filtered = entries.where((entry) => entry.id != scanId).toList();
    final encoded = filtered
        .map((item) => jsonEncode({
              ...item.toMap(),
              'id': item.id ?? 'local-${DateTime.now().microsecondsSinceEpoch}-skin',
            }))
        .toList();
    await prefs.setStringList(_localKey, encoded);
  }

  List<SkinScanRecord> _dedupe(List<SkinScanRecord> items) {
    final seen = <String>{};
    final result = <SkinScanRecord>[];
    for (final item in items) {
      final key = item.id ?? '${item.date.millisecondsSinceEpoch}|${item.imagePath ?? ''}|${item.metrics.toString()}';
      if (seen.contains(key)) continue;
      seen.add(key);
      result.add(item);
    }
    return result;
  }
}