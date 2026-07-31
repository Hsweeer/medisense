import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../data/models/models.dart';
import '../data/models/notification_model.dart';
import 'native_alarm_bridge.dart';
import 'notification_storage_helper.dart';

/// Fires when a notification ACTION is tapped while the app is fully
/// terminated. Must stay a top-level (or static) function — the OS
/// launches a fresh, minimal background isolate to run this, so it can't
/// reach any running instance/state. It can, however, safely touch the
/// filesystem, which is enough to append the tapped notification into
/// local JSON history.
///
/// NOTE: this only fires for notification ACTION buttons. A plain tap on
/// the notification body while the app is terminated does NOT invoke
/// this — that case is a cold app launch and is handled separately via
/// `getNotificationAppLaunchDetails()` in [NotificationService.initialize].
@pragma('vm:entry-point')
void notificationTapBackgroundHandler(NotificationResponse response) {
  debugPrint(
      '[NotificationService] tapped (background isolate) payload=${response.payload}');
  NotificationService._saveFromPayload(response.payload);
}

/// Owns everything notification-related: scheduling reminder alarms,
/// cancelling them, reacting to taps, and reading/writing local history.
/// All business logic for notifications lives here, per the existing
/// project convention of keeping providers thin and services fat
/// (see ProfileProvider/AuthProvider + their Firebase-backed services).
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Set by NotificationProvider so a tap (which can happen while the
  /// provider isn't listening, e.g. cold start) still refreshes the UI
  /// the moment it's available.
  static VoidCallback? onHistoryChanged;

  static const _androidChannel = AndroidNotificationChannel(
    'medisense_reminders',
    'Medicine Reminders',
    description: 'Scheduled medicine and health reminders',
    importance: Importance.max,
  );

  // ── Initialization ───────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    debugPrint('[NotificationService] initialize() start');

    tz_data.initializeTimeZones();
    try {
      final localTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings =
    InitializationSettings(android: androidInit, iOS: iosInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint(
            '[NotificationService] tapped (foreground) payload=${response.payload}');
        _saveFromPayload(response.payload);
      },
      onDidReceiveBackgroundNotificationResponse:
      notificationTapBackgroundHandler,
    );
    debugPrint('[NotificationService] plugin.initialize() done');

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(_androidChannel);
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();

    final iosImpl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosImpl?.requestPermissions(
        alert: true, badge: true, sound: true);

    // ── Native Alarm Permissions ──────────────────────────────────────
    await NativeAlarmBridge.instance.ensureFullScreenIntentPermission();
    await NativeAlarmBridge.instance.requestIgnoreBatteryOptimizations();

    // ── Cold-launch tap handling ──────────────────────────────────────
    //
    // THE FIX: if the app was fully terminated when the reminder fired,
    // tapping the notification body launches the app fresh. That's a
    // cold start, not a "response while running" event, so neither
    // onDidReceiveNotificationResponse nor
    // onDidReceiveBackgroundNotificationResponse (which only covers
    // notification ACTIONS, and this app defines none) ever fires for
    // it. getNotificationAppLaunchDetails() is the only way to recover
    // that payload, so we check it here and route it through the same
    // _saveFromPayload() used everywhere else.
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    debugPrint(
        '[NotificationService] didNotificationLaunchApp=${launchDetails?.didNotificationLaunchApp}');
    if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
      final payload = launchDetails.notificationResponse?.payload;
      debugPrint(
          '[NotificationService] cold-start launch payload=$payload');
      await _saveFromPayload(payload);
    }

    _initialized = true;
    debugPrint('[NotificationService] initialize() complete');
  }

  // ── Scheduling ────────────────────────────────────────────────────────

  /// Schedules (or reschedules) the native alarm(s) for [reminder] so a
  /// local notification fires at its time, with no internet required and
  /// no app process needed to be alive.
  Future<void> scheduleReminder(Reminder reminder) async {
    await cancelForReminder(reminder);

    final time = _parseTimeOfDay(reminder.time);
    if (time == null) {
      debugPrint(
          '[NotificationService] scheduleReminder: unparseable time "${reminder.time}" for "${reminder.title}" — skipped');
      return; // unparseable time — nothing to schedule
    }

    final baseId = _baseIdFor(reminder.title);
    final message = reminder.dose.trim().isEmpty
        ? 'Time to take ${reminder.title}'
        : 'Time to take ${reminder.title} · ${reminder.dose}';
    final payload = jsonEncode({
      'title': 'Medicine Reminder',
      'message': message,
      'time': reminder.time,
    });
    debugPrint(
        '[NotificationService] scheduling "${reminder.title}" baseId=$baseId payload=$payload');

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
    );

    final weekdays = _weekdaysFor(reminder.schedule);

    if (weekdays == null) {
      // "Daily" (and "Custom", as a sane fallback) — repeats every day.
      final when = _nextInstanceOfTime(time);
      await _plugin.zonedSchedule(
        baseId,
        'Medicine Reminder',
        message,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: payload,
      );
      debugPrint(
          '[NotificationService] scheduled id=$baseId (daily) next=$when');

      // ── Native Alarm Bridge ──────────────────────────────────────────
      await NativeAlarmBridge.instance.scheduleAlarm(
        reminderId: reminder.id ?? reminder.title,
        title: reminder.title,
        dose: reminder.dose,
        displayTime: reminder.time,
        hour: time.hour,
        minute: time.minute,
        repeatType: 'daily',
      );
    } else {
      // "Weekdays" or "Mon · Wed · Fri" — one recurring alarm per weekday.
      for (final weekday in weekdays) {
        final when = _nextInstanceOfWeekdayTime(weekday, time);
        await _plugin.zonedSchedule(
          baseId + weekday,
          'Medicine Reminder',
          message,
          when,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          payload: payload,
        );
        debugPrint(
            '[NotificationService] scheduled id=${baseId + weekday} (weekday=$weekday) next=$when');

        // ── Native Alarm Bridge ──────────────────────────────────────────
        await NativeAlarmBridge.instance.scheduleAlarm(
          reminderId: reminder.id ?? reminder.title,
          title: reminder.title,
          dose: reminder.dose,
          displayTime: reminder.time,
          hour: time.hour,
          minute: time.minute,
          repeatType: 'weekly',
          weekday: weekday,
        );
      }
    }
  }

  /// Cancels every alarm belonging to [reminder] (used before rescheduling,
  /// on edit, and on delete).
  Future<void> cancelForReminder(Reminder reminder) async {
    final baseId = _baseIdFor(reminder.title);
    await _plugin.cancel(baseId);
    for (var weekday = 1; weekday <= 7; weekday++) {
      await _plugin.cancel(baseId + weekday);
    }
    // ── Native Alarm Bridge ────────────────────────────────────────────
    await NativeAlarmBridge.instance.cancelAlarm(reminder.id ?? reminder.title);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
    await NativeAlarmBridge.instance.cancelAllAlarms();
  }

  /// A stable id derived from the reminder's title. Titles are locked
  /// once a reminder is created (see reminders_screen.dart), so this stays
  /// consistent across edits without needing an `id` field on [Reminder].
  int _baseIdFor(String title) => (title.hashCode.abs() % 100000) * 10;

  TimeOfDay? _parseTimeOfDay(String input) {
    final text = input.trim().toUpperCase();
    final match =
    RegExp(r'^(\d{1,2}):(\d{1,2})\s*(AM|PM)?$').firstMatch(text);
    if (match == null) return null;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final period = match.group(3);
    if (period == 'PM' && hour != 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;
    if (hour > 23 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  List<int>? _weekdaysFor(String schedule) {
    switch (schedule) {
      case 'Weekdays':
        return const [1, 2, 3, 4, 5];
      case 'Mon · Wed · Fri':
        return const [1, 3, 5];
      default:
        return null; // Daily / Custom
    }
  }

  tz.TZDateTime _nextInstanceOfTime(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  tz.TZDateTime _nextInstanceOfWeekdayTime(int weekday, TimeOfDay time) {
    var scheduled = _nextInstanceOfTime(time);
    while (scheduled.weekday != weekday) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  // ── Tap handling → local JSON history ───────────────────────────────

  static Future<void> _saveFromPayload(String? payload) async {
    debugPrint('[NotificationService] _saveFromPayload payload=$payload');
    if (payload == null || payload.isEmpty) {
      debugPrint(
          '[NotificationService] _saveFromPayload: null/empty payload — nothing to save');
      return;
    }
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      final now = DateTime.now();
      final item = NotificationItem(
        id: now.microsecondsSinceEpoch.toString(),
        title: map['title'] as String? ?? 'Medicine Reminder',
        message: map['message'] as String? ?? '',
        date: formatDate(now),
        time: map['time'] as String? ?? formatTime(now),
        createdAt: now,
        isRead: false,
      );
      debugPrint(
          '[NotificationService] saving item id=${item.id} title=${item.title} time=${item.time}');
      await NotificationStorageHelper.append(item);
      debugPrint('[NotificationService] saved to JSON history');
      onHistoryChanged?.call();
      debugPrint(
          '[NotificationService] onHistoryChanged invoked=${onHistoryChanged != null}');
    } catch (e) {
      debugPrint(
          '[NotificationService] _saveFromPayload: failed to parse payload — $e');
      // Malformed payload — nothing worth saving.
    }
  }

  /// Also used by NotificationProvider's foreground due-time watcher, so
  /// a notification that fires while the app happens to be open gets
  /// logged immediately too (flutter_local_notifications has no
  /// cross-platform "was just displayed" callback — only a tap callback —
  /// so this foreground check plus the tap handler above together cover
  /// the realistic cases).
  Future<void> logFiredReminder(
      {required String title, required String message, required String time}) async {
    debugPrint(
        '[NotificationService] logFiredReminder title=$title time=$time');
    final now = DateTime.now();
    final item = NotificationItem(
      id: now.microsecondsSinceEpoch.toString(),
      title: title,
      message: message,
      date: formatDate(now),
      time: time,
      createdAt: now,
      isRead: false,
    );
    await NotificationStorageHelper.append(item);
    debugPrint('[NotificationService] logFiredReminder saved to JSON history');
    onHistoryChanged?.call();
    debugPrint(
        '[NotificationService] onHistoryChanged invoked=${onHistoryChanged != null}');
  }

  static String formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  static String formatTime(DateTime d) {
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final period = d.hour >= 12 ? 'PM' : 'AM';
    final minute = d.minute.toString().padLeft(2, '0');
    return '$hour12:$minute $period';
  }

  // ── History CRUD (delegates to the local JSON storage helper) ────────

  Future<List<NotificationItem>> loadHistory() =>
      NotificationStorageHelper.readAll();

  Future<List<NotificationItem>> markAsRead(String id) =>
      NotificationStorageHelper.markAsRead(id);

  Future<List<NotificationItem>> deleteNotification(String id) =>
      NotificationStorageHelper.delete(id);

  Future<List<NotificationItem>> clearHistory() =>
      NotificationStorageHelper.clearAll();
}