import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/models/models.dart';
import '../services/notification_service.dart';
import '../services/reminder_firestore_service.dart';

/// Full reminder engine: per-dose status (taken / snoozed / skipped),
/// 10-minute snooze, streaks, adherence, and MedAI-created reminders.
/// All reminders are persisted to Firestore.
class ReminderProvider extends ChangeNotifier {
  final List<Reminder> reminders = [];
  final ReminderFirestoreService _firestoreService =
      ReminderFirestoreService.instance;
  bool isLoading = false;
  bool _initialized = false;

  ReminderProvider() {
    // Immediate check for current user on startup
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      debugPrint('[ReminderProvider] User already logged in: ${currentUser.email}, fetching...');
      _initializeReminders();
    }

    // Listen to future auth changes (login/logout)
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        debugPrint('[ReminderProvider] Auth change: User logged in: ${user.email}');
        // Reset initialization to force a reload for the new user
        _initialized = false;
        _initializeReminders();
      } else {
        debugPrint('[ReminderProvider] Auth change: User logged out, clearing data...');
        reminders.clear();
        NotificationService.instance.cancelAll();
        _initialized = false;
        notifyListeners();
      }
    });
  }

  /// Load reminders from Firestore on app startup.
  Future<void> _initializeReminders() async {
    if (_initialized) return;
    isLoading = true;
    notifyListeners();

    try {
      final loaded = await _firestoreService.fetchReminders();
      reminders.clear();
      reminders.addAll(loaded);
      debugPrint(
          '[ReminderProvider] initialized with ${reminders.length} reminders from Firestore');

      // Reschedule alarms for all enabled reminders (cold start recovery)
      for (final r in reminders) {
        if (r.enabled) {
          NotificationService.instance.scheduleReminder(r);
        }
      }
    } catch (e) {
      debugPrint('[ReminderProvider] _initializeReminders: error — $e');
    }

    _initialized = true;
    isLoading = false;
    notifyListeners();
  }

  /// Force a refresh from Firestore (useful after auth state changes).
  Future<void> refresh() async {
    // If logging out, stop all alarms from the previous user
    if (FirebaseAuth.instance.currentUser == null) {
      await NotificationService.instance.cancelAll();
    }

    _initialized = false;
    await _initializeReminders();
  }

  /// Re-arms enabled reminders after a global scheduling setting changes,
  /// such as the selected alarm sound. The reminder data itself is unchanged.
  Future<void> rescheduleEnabledReminders() async {
    for (final reminder in reminders) {
      if (reminder.enabled) {
        await NotificationService.instance.scheduleReminder(reminder);
      }
    }
  }

  int get takenCount =>
      reminders.where((r) => r.status == DoseStatus.taken).length;

  int get skippedCount =>
      reminders.where((r) => r.status == DoseStatus.skipped).length;

  /// Longest current streak across reminders — the header stat.
  int get bestStreak => reminders.isEmpty
      ? 0
      : reminders.map((r) => r.streakDays).reduce((a, b) => a > b ? a : b);

  /// This-week adherence, accurately calculated from today's progress.
  int get adherencePct {
    if (reminders.isEmpty) return 100;
    // Real calculation: (Taken / Total scheduled for today)
    final pct = (takenCount / reminders.length) * 100;
    return pct.round().clamp(0, 100);
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
    _persist(r);
    
    // Stop the alarm for today immediately
    NotificationService.instance.cancelForReminder(r);

    notifyListeners();
  }

  /// Undo back to pending (tapping the check again).
  void untake(Reminder r) {
    r.status = DoseStatus.pending;
    r.streakDays = (r.streakDays - 1).clamp(0, 9999);
    _persist(r);
    notifyListeners();
  }

  void snooze(Reminder r, {int minutes = 10}) {
    r.status = DoseStatus.snoozed;
    r.snoozeLabel = 'rings again in $minutes min';
    _persist(r);
    notifyListeners();
  }

  void skip(Reminder r) {
    r.status = DoseStatus.skipped;
    r.snoozeLabel = null;
    r.streakDays = 0;
    _persist(r);
    notifyListeners();
  }

  /// Add a new reminder: save to Firestore, schedule alarm, and update UI.
  Future<void> add(Reminder r) async {
    final saved = await _firestoreService.createReminder(r);
    if (saved != null) {
      reminders.insert(0, saved); // Insert at top (newest)
      NotificationService.instance.scheduleReminder(saved);
      notifyListeners();
    }
  }

  /// Used by MedAI after scanning a prescription — returns how many landed.
  Future<int> addAll(List<Reminder> newOnes) async {
    int count = 0;
    for (final r in newOnes) {
      final saved = await _firestoreService.createReminder(r);
      if (saved != null) {
        reminders.insert(0, saved); // Insert at top
        NotificationService.instance.scheduleReminder(saved);
        count++;
      }
    }
    notifyListeners();
    return count;
  }

  /// Update a reminder: save to Firestore, reschedule alarm, and update UI.
  Future<void> update(Reminder r,
      {String? dose, String? time, String? schedule, String? instructions}) async {
    if (dose != null && dose.isNotEmpty) r.dose = dose;
    if (time != null && time.isNotEmpty) r.time = time;
    if (schedule != null && schedule.isNotEmpty) r.schedule = schedule;
    if (instructions != null) r.instructions = instructions;

    final updated = await _firestoreService.updateReminder(r);
    if (updated) {
      // Reschedule the alarm with new time/schedule
      NotificationService.instance.scheduleReminder(r);
      notifyListeners();
    }
  }

  /// Delete a reminder: remove from Firestore, cancel alarm, and update UI.
  Future<void> remove(Reminder r) async {
    if (r.id == null) return;

    final deleted = await _firestoreService.deleteReminder(r.id!);
    if (deleted) {
      reminders.remove(r);
      NotificationService.instance.cancelForReminder(r);
      notifyListeners();
    }
  }

  /// Enable a reminder: reschedule its alarm.
  Future<void> enable(Reminder r) async {
    r.enabled = true;
    final updated = await _firestoreService.updateReminder(r);
    if (updated) {
      NotificationService.instance.scheduleReminder(r);
      notifyListeners();
    }
  }

  /// Disable a reminder: cancel its alarm.
  Future<void> disable(Reminder r) async {
    r.enabled = false;
    final updated = await _firestoreService.updateReminder(r);
    if (updated) {
      NotificationService.instance.cancelForReminder(r);
      notifyListeners();
    }
  }

  /// Delete all reminders for the current user.
  Future<void> clearAll() async {
    isLoading = true;
    notifyListeners();

    try {
      for (final r in List.from(reminders)) {
        if (r.id != null) {
          await _firestoreService.deleteReminder(r.id!);
          await NotificationService.instance.cancelForReminder(r);
        }
      }
      reminders.clear();
      debugPrint('[ReminderProvider] All reminders cleared');
    } catch (e) {
      debugPrint('[ReminderProvider] clearAll error: $e');
    }

    isLoading = false;
    notifyListeners();
  }

  /// Internal: persist status changes to Firestore without triggering
  /// alarm rescheduling (used for take/untake/snooze/skip).
  void _persist(Reminder r) {
    if (r.id != null) {
      _firestoreService.updateReminder(r);
    }
  }
}
