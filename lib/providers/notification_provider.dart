import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/models/notification_model.dart';
import '../services/notification_service.dart';
import 'reminder_provider.dart';

/// UI-facing state for the Notification screen. Holds no business logic
/// itself — every read/write is delegated to [NotificationService], this
/// just keeps `notifications` in sync and calls `notifyListeners()`.
class NotificationProvider extends ChangeNotifier with WidgetsBindingObserver {
  NotificationProvider({required ReminderProvider reminderProvider})
      : _reminderProvider = reminderProvider {
    debugPrint('[NotificationProvider] constructor — wiring onHistoryChanged');
    WidgetsBinding.instance.addObserver(this);
    NotificationService.onHistoryChanged = refresh;
    _load();
    _startWatching();
  }

  final ReminderProvider _reminderProvider;
  final _service = NotificationService.instance;

  List<NotificationItem> notifications = [];
  bool isLoading = true;

  Timer? _watchTimer;
  final Map<String, String> _lastLoggedMinuteKey = {};

  int get unreadCount => notifications.where((n) => !n.isRead).length;

  Future<void> _load() async {
    debugPrint('[NotificationProvider] _load() start');
    isLoading = true;
    notifyListeners();
    notifications = await _service.loadHistory();
    debugPrint('[NotificationProvider] _load() loaded ${notifications.length} items');
    isLoading = false;
    notifyListeners();
  }

  /// Re-reads history from disk. Safe to call as often as needed.
  Future<void> refresh() async {
    debugPrint('[NotificationProvider] refresh() called');
    notifications = await _service.loadHistory();
    debugPrint(
        '[NotificationProvider] refresh() loaded ${notifications.length} items — notifying listeners');
    notifyListeners();
  }

  Future<void> markAsRead(NotificationItem item) async {
    if (item.isRead) return;
    notifications = await _service.markAsRead(item.id);
    notifyListeners();
  }

  Future<void> delete(NotificationItem item) async {
    notifications = await _service.deleteNotification(item.id);
    notifyListeners();
  }

  Future<void> clearAll() async {
    notifications = await _service.clearHistory();
    notifyListeners();
  }

  // ── Foreground due-time watcher ────────────────────────────────────
  //
  // flutter_local_notifications has no cross-platform "notification was
  // just displayed" event — only a tap event. The OS still reliably shows
  // the notification itself even with the app closed (that part needs no
  // help). This watcher only closes the *history-logging* gap for the
  // case where the app happens to be open/foregrounded right as a
  // reminder's time arrives, by checking the same reminders the Reminders
  // screen already shows against the clock.

  void _startWatching() {
    _checkDueReminders();
    _watchTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _checkDueReminders());
  }

  void _checkDueReminders() {
    final now = DateTime.now();
    for (final r in _reminderProvider.reminders) {
      final time = _parse(r.time);
      if (time == null) continue;
      if (time.hour != now.hour || time.minute != now.minute) continue;

      final minuteKey = '${now.year}-${now.month}-${now.day}-${now.hour}-${now.minute}';
      if (_lastLoggedMinuteKey[r.title] == minuteKey) continue; // already logged this minute
      _lastLoggedMinuteKey[r.title] = minuteKey;

      final message = r.dose.trim().isEmpty
          ? 'Time to take ${r.title}'
          : 'Time to take ${r.title} · ${r.dose}';
      debugPrint(
          '[NotificationProvider] due-time watcher matched "${r.title}" at $minuteKey');
      _service.logFiredReminder(
          title: 'Medicine Reminder', message: message, time: r.time);
    }
  }

  ({int hour, int minute})? _parse(String input) {
    final text = input.trim().toUpperCase();
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$').firstMatch(text);
    if (match == null) return null;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final period = match.group(3);
    if (period == 'PM' && hour != 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;
    if (hour > 23 || minute > 59) return null;
    return (hour: hour, minute: minute);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[NotificationProvider] app resumed — checking due reminders + refreshing');
      _checkDueReminders();
      refresh();
    }
  }

  @override
  void dispose() {
    _watchTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.onHistoryChanged = null;
    super.dispose();
  }
}