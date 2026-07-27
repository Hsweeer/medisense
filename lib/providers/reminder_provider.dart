import 'package:flutter/foundation.dart';

import '../data/mock/mock_data.dart';
import '../data/models/models.dart';

/// Full reminder engine: per-dose status (taken / snoozed / skipped),
/// 10-minute snooze, streaks, adherence, and MedAI-created reminders.
class ReminderProvider extends ChangeNotifier {
  final List<Reminder> reminders = [...MockData.reminders];

  int get takenCount =>
      reminders.where((r) => r.status == DoseStatus.taken).length;

  int get skippedCount =>
      reminders.where((r) => r.status == DoseStatus.skipped).length;

  /// Longest current streak across reminders — the header stat.
  int get bestStreak => reminders.isEmpty
      ? 0
      : reminders.map((r) => r.streakDays).reduce((a, b) => a > b ? a : b);

  /// This-week adherence, seeded and nudged by today's progress.
  int get adherencePct {
    final active = reminders.length - skippedCount;
    if (active <= 0) return 100;
    return (72 + (takenCount / active) * 28).round().clamp(0, 100);
  }

  /// The home hero: first pending dose, else first snoozed one.
  Reminder? get nextDose {
    for (final r in reminders) {
      if (r.status == DoseStatus.pending) return r;
    }
    for (final r in reminders) {
      if (r.status == DoseStatus.snoozed) return r;
    }
    return null;
  }

  void take(Reminder r) {
    r.status = DoseStatus.taken;
    r.snoozeLabel = null;
    r.streakDays++;
    notifyListeners();
  }

  /// Undo back to pending (tapping the check again).
  void untake(Reminder r) {
    r.status = DoseStatus.pending;
    r.streakDays = (r.streakDays - 1).clamp(0, 9999);
    notifyListeners();
  }

  void snooze(Reminder r, {int minutes = 10}) {
    r.status = DoseStatus.snoozed;
    r.snoozeLabel = 'rings again in $minutes min';
    notifyListeners();
  }

  void skip(Reminder r) {
    r.status = DoseStatus.skipped;
    r.snoozeLabel = null;
    r.streakDays = 0;
    notifyListeners();
  }

  void add(Reminder r) {
    reminders.add(r);
    notifyListeners();
  }

  /// Used by MedAI after scanning a prescription — returns how many landed.
  int addAll(List<Reminder> newOnes) {
    reminders.addAll(newOnes);
    notifyListeners();
    return newOnes.length;
  }

  void update(Reminder r,
      {String? dose, String? time, String? schedule, String? instructions}) {
    if (dose != null && dose.isNotEmpty) r.dose = dose;
    if (time != null && time.isNotEmpty) r.time = time;
    if (schedule != null && schedule.isNotEmpty) r.schedule = schedule;
    if (instructions != null) r.instructions = instructions;
    notifyListeners();
  }

  void remove(Reminder r) {
    reminders.remove(r);
    notifyListeners();
  }
}
