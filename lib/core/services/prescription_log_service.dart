import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/prescription_models.dart';
import 'prescription_history_preferences.dart';

class PrescriptionLogService {
  PrescriptionLogService._();
  static final instance = PrescriptionLogService._();

  static const _localKey = 'local_prescription_history_entries';

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? get _log {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('prescription_log');
  }

  Future<void> save(PrescriptionHistoryEntry entry) async {
    final enabled = await PrescriptionHistoryPreferences.instance.isEnabled();
    if (!enabled) return;

    final log = _log;
    if (log == null) {
      await _saveLocal(entry);
      return;
    }

    try {
      await log.add(entry.toMap());
      debugPrint('[PrescriptionLogService] saved remotely');
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'unauthenticated') {
        debugPrint('[PrescriptionLogService] Firestore denied; saving locally instead: ${e.code}');
        await _saveLocal(entry);
        return;
      }
      rethrow;
    } catch (e) {
      debugPrint('[PrescriptionLogService] save failed: $e');
      await _saveLocal(entry);
    }
  }

  Future<void> delete(String entryId) async {
    final log = _log;
    if (log == null) {
      await _deleteLocal(entryId);
      return;
    }

    try {
      await log.doc(entryId).delete();
      await _deleteLocal(entryId);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'unauthenticated') {
        await _deleteLocal(entryId);
        return;
      }
      rethrow;
    } catch (e) {
      debugPrint('[PrescriptionLogService] delete failed: $e');
      await _deleteLocal(entryId);
    }
  }

  Future<List<PrescriptionHistoryEntry>> _readLocalEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_localKey) ?? const <String>[];
    return raw
        .map((item) => jsonDecode(item))
        .whereType<Map<String, dynamic>>()
        .map((map) => PrescriptionHistoryEntry.fromMap(map, map['id']?.toString() ?? 'local-${DateTime.now().microsecondsSinceEpoch}'))
        .toList();
  }

  Future<void> _saveLocal(PrescriptionHistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await _readLocalEntries();
    final next = [...existing, entry];
    final encoded = next
        .map((item) => jsonEncode({...item.toMap(), 'id': item.id ?? 'local-${DateTime.now().microsecondsSinceEpoch}'}))
        .toList();
    await prefs.setStringList(_localKey, encoded);
  }

  Future<void> _deleteLocal(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await _readLocalEntries();
    final filtered = entries.where((entry) => entry.id != entryId).toList();
    final encoded = filtered
        .map((entry) => jsonEncode({...entry.toMap(), 'id': entry.id ?? 'local-${DateTime.now().microsecondsSinceEpoch}'}))
        .toList();
    await prefs.setStringList(_localKey, encoded);
  }

  /// Everything the user has ever scanned. If Firestore is blocked by rules,
  /// local entries still appear so the history remains usable.
  Stream<List<PrescriptionHistoryEntry>> allEntries() {
    final log = _log;
    if (log == null) {
      return Stream.fromFuture(_readLocalEntries());
    }

    return Stream<List<PrescriptionHistoryEntry>>.multi((controller) async {
      try {
        final remote = await log.orderBy('scannedAtMs', descending: true).get();
        final remoteEntries = remote.docs
            .map((document) => PrescriptionHistoryEntry.fromMap(document.data(), document.id))
            .toList();
        final localEntries = await _readLocalEntries();
        final merged = _merge(remoteEntries, localEntries);
        controller.add(merged);
      } catch (e) {
        debugPrint('[PrescriptionLogService] failed to read remote log: $e');
        controller.add(await _readLocalEntries());
      }
      controller.close();
    });
  }

  List<PrescriptionHistoryEntry> _merge(
    List<PrescriptionHistoryEntry> remote, 
    List<PrescriptionHistoryEntry> local,
  ) {
    final merged = [...remote, ...local];
    final seen = <String>{};
    final unique = <PrescriptionHistoryEntry>[];
    for (final entry in merged
      ..sort((a, b) => b.scannedAt.compareTo(a.scannedAt))) {
      final key = entry.id ??
          '${entry.scannedAt.millisecondsSinceEpoch}|${entry.summary}|${entry.photoUrl ?? ''}';
      if (seen.add(key)) unique.add(entry);
    }
    return unique;
  }
}
