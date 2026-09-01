import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../data/models/prescription_models.dart';

class PrescriptionLogService {
  PrescriptionLogService._();
  static final instance = PrescriptionLogService._();

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _log => FirebaseFirestore
      .instance
      .collection('users')
      .doc(_uid)
      .collection('prescription_log');

  Future<void> save(PrescriptionHistoryEntry entry) async {
    await _log.add(entry.toMap());
  }

  Future<void> delete(String entryId) async {
    await _log.doc(entryId).delete();
  }

  Stream<List<PrescriptionHistoryEntry>> allEntries() {
    return _log
        .orderBy('scannedAtMs', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
          .map(
            (document) => PrescriptionHistoryEntry.fromMap(
            document.data(), document.id),
      )
          .toList(),
    );
  }
}