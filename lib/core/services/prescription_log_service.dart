import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../data/models/prescription_models.dart';

class PrescriptionLogService {
  PrescriptionLogService._();
  static final instance = PrescriptionLogService._();

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
    final log = _log;
    // No signed-in account (e.g. guest mode) — nothing to save to. The UI
    // already skips calling this for guests (see
    // prescription_scanner_screen.dart), so this is just a defensive
    // no-op, not the normal path.
    if (log == null) return;
    await log.add(entry.toMap());
  }

  Future<void> delete(String entryId) async {
    final log = _log;
    if (log == null) return;
    await log.doc(entryId).delete();
  }

  /// Everything the user has ever scanned. Returns an empty stream (never
  /// throws) for a guest browsing without an account — the history
  /// screen then shows its normal empty state instead of crashing on a
  /// null uid.
  Stream<List<PrescriptionHistoryEntry>> allEntries() {
    final log = _log;
    if (log == null) return Stream.value(const []);

    return log
        .orderBy('scannedAtMs', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (document) => PrescriptionHistoryEntry.fromMap(
                  document.data(),
                  document.id,
                ),
              )
              .toList(),
        );
  }
}
