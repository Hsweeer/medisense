import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../data/models/food_models.dart';

class FoodLogService {
  FoodLogService._();
  static final instance = FoodLogService._();

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? get _log {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('food_log');
  }

  Future<void> save(FoodLogEntry entry) async {
    final log = _log;
    // No signed-in account (e.g. guest mode) — nothing to save to. The UI
    // already gates the "save" actions that call this behind a login
    // prompt, so this is just a defensive no-op, not the normal path.
    if (log == null) return;
    await log.add(entry.toMap());
  }

  Future<void> delete(String entryId) async {
    final log = _log;
    if (log == null) return;
    await log.doc(entryId).delete();
  }

  Stream<List<FoodLogEntry>> entriesForDay(DateTime day) {
    final log = _log;
    if (log == null) return Stream.value(const []);

    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    return log
        .where(
          'loggedAtMs',
          isGreaterThanOrEqualTo: start.millisecondsSinceEpoch,
        )
        .where('loggedAtMs', isLessThan: end.millisecondsSinceEpoch)
        .snapshots()
        .map(
          (s) =>
              s.docs.map((d) => FoodLogEntry.fromMap(d.data(), d.id)).toList(),
        );
  }

  /// Everything the user has ever logged. Returns an empty stream (never
  /// throws) for a guest browsing without an account — the history
  /// screen then shows its normal "No nutrition history yet." state
  /// instead of crashing on a null uid.
  Stream<List<FoodLogEntry>> allEntries() {
    final log = _log;
    if (log == null) return Stream.value(const []);

    return log
        .orderBy('loggedAtMs', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (document) =>
                    FoodLogEntry.fromMap(document.data(), document.id),
              )
              .toList(),
        );
  }

  Stream<Map<String, double>> dailyTotals(DateTime day) {
    return entriesForDay(day).map((entries) {
      double calories = 0, carbs = 0, fat = 0, protein = 0;
      for (final e in entries) {
        calories += e.nutrition.calories;
        carbs += e.nutrition.carbsG;
        fat += e.nutrition.fatG;
        protein += e.nutrition.proteinG;
      }
      return {
        'calories': calories,
        'carbs': carbs,
        'fat': fat,
        'protein': protein,
      };
    });
  }
}
