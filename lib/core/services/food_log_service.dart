import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../data/models/food_models.dart';

class FoodLogService {
  FoodLogService._();
  static final instance = FoodLogService._();

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _log => FirebaseFirestore
      .instance
      .collection('users')
      .doc(_uid)
      .collection('food_log');

  Future<void> save(FoodLogEntry entry) async {
    await _log.add(entry.toMap());
  }

  Stream<List<FoodLogEntry>> entriesForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    return _log
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
