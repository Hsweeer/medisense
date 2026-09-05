import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/models/models.dart';
import '../services/native_alarm_bridge.dart';
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
  StreamSubscription<List<Reminder>>? _remindersSub;

  ReminderProvider() {
    // Immediate check for current user on startup
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      debugPrint(
        '[ReminderProvider] User already logged in: ${currentUser.email}, fetching...',
      );
      _initializeReminders();
    }

    // Listen to future auth changes (login/logout)
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        debugPrint(
          '[ReminderProvider] Auth change: User logged in: ${user.email}',
        );
        // Reset initialization to force a reload for the new user
        _initialized = false;
        _initializeReminders();
      } else {
        debugPrint(
          '[ReminderProvider] Auth change: User logged out, clearing data...',
        );
        _remindersSub?.cancel();
        _remindersSub = null;
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
        '[ReminderProvider] initialized with ${reminders.length} reminders from Firestore',
      );

      // Reschedule alarms for all enabled reminders (cold start recovery),
      // and reset any status left over from a previous day — otherwise a
      // dose marked "taken" yesterday would stay marked taken forever, and
      // its (fully-cancelled) native alarm would never ring again.
      for (final r in reminders) {
        if (r.status != DoseStatus.pending && r.isStatusStale) {
          debugPrint(
            '[ReminderProvider] Resetting stale status for "${r.title}" (was ${r.status})',
          );
          r.status = DoseStatus.pending;
          r.snoozeLabel = null;
          r.lastStatusDate = DateTime.now();
          _persist(r);
        }
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

    // From here on, stay live — this is what lets a reminder a caregiver
    // adds for us (or edits/removes) take effect immediately, instead of
    // only picking it up the next time the app is cold-started.
    _subscribeToLiveUpdates();
  }

  /// Keeps [reminders] (and each one's scheduled native alarm) in sync
  /// with Firestore in real time. Without this, anything written to our
  /// reminders collection by someone else — a caregiver adding, editing,
  /// or removing a reminder on our behalf — would sit unscheduled until
  /// we happened to fully restart the app.
  void _subscribeToLiveUpdates() {
    _remindersSub?.cancel();
    _remindersSub = _firestoreService.remindersStream().listen(
      _onRemindersSnapshot,
      onError: (Object e) {
        debugPrint('[ReminderProvider] remindersStream error: $e');
      },
    );
  }

  void _onRemindersSnapshot(List<Reminder> incoming) {
    final incomingById = {
      for (final r in incoming)
        if (r.id != null) r.id!: r,
    };
    var changed = false;

    // Gone remotely — e.g. a caregiver (or another device) deleted it.
    final removed = reminders
        .where((r) => r.id != null && !incomingById.containsKey(r.id))
        .toList();
    for (final r in removed) {
      reminders.remove(r);
      NotificationService.instance.cancelForReminder(r);
      changed = true;
    }

    for (final fresh in incoming) {
      if (fresh.id == null) continue;
      final idx = reminders.indexWhere((r) => r.id == fresh.id);

      if (idx == -1) {
        // Brand new to this device — most commonly a caregiver just added
        // it for us. Schedule its alarm right away instead of waiting for
        // the next app restart.
        reminders.insert(0, fresh);
        if (fresh.enabled) {
          NotificationService.instance.scheduleReminder(fresh);
        }
        changed = true;
        continue;
      }

      final existing = reminders[idx];
      final scheduleRelevantChange =
          existing.time != fresh.time ||
          existing.schedule != fresh.schedule ||
          existing.enabled != fresh.enabled ||
          existing.dose != fresh.dose;
      final anyChange =
          scheduleRelevantChange ||
          existing.status != fresh.status ||
          existing.snoozeLabel != fresh.snoozeLabel ||
          existing.instructions != fresh.instructions;

      if (anyChange) {
        reminders[idx] = fresh;
        changed = true;
      }
      if (scheduleRelevantChange) {
        if (fresh.enabled) {
          NotificationService.instance.scheduleReminder(fresh);
        } else {
          NotificationService.instance.cancelForReminder(fresh);
        }
      }
    }

    if (changed) notifyListeners();
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
    r.lastStatusDate = DateTime.now();
    _persist(r);

    // 1. Cancel future notifications for today
    NotificationService.instance.cancelForReminder(r);

    // 2. IMMEDIATELY stop the ringing if it's currently going off
    NativeAlarmBridge.instance.stopRinging();

    notifyListeners();
  }

  /// Undo back to pending (tapping the check again).
  void untake(Reminder r) {
    r.status = DoseStatus.pending;
    r.streakDays = (r.streakDays - 1).clamp(0, 9999);
    r.lastStatusDate = DateTime.now();
    _persist(r);
    // Taking it back means today's dose should be able to ring again.
    if (r.enabled) {
      NotificationService.instance.scheduleReminder(r);
    }
    notifyListeners();
  }

  void snooze(Reminder r, {int minutes = 10}) {
    r.status = DoseStatus.snoozed;
    r.snoozeLabel = 'rings again in $minutes min';
    r.lastStatusDate = DateTime.now();
    _persist(r);

    // Schedule a real alarm/notification 10 min from now
    NotificationService.instance.snoozeReminder(r, minutes: minutes);

    notifyListeners();
  }

  void skip(Reminder r) {
    r.status = DoseStatus.skipped;
    r.snoozeLabel = null;
    r.streakDays = 0;
    r.lastStatusDate = DateTime.now();
    _persist(r);
    notifyListeners();
  }

  /// Add a new reminder: save to Firestore, schedule alarm, and update UI.
  Future<void> add(Reminder r) async {
    // Guest users can create personal reminders without an account. These
    // remain in the provider for the current guest session and still get
    // native alarms, while signed-in users continue using Firestore.
    if (!_firestoreService.isLoggedIn) {
      r.id ??= 'guest-${DateTime.now().microsecondsSinceEpoch}';
      reminders.insert(0, r);
      NotificationService.instance.scheduleReminder(r);
      notifyListeners();
      return;
    }

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
  Future<void> update(
    Reminder r, {
    String? dose,
    String? time,
    String? schedule,
    String? instructions,
  }) async {
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

  @override
  void dispose() {
    _remindersSub?.cancel();
    super.dispose();
  }
}
