import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/services/alarm_sound_catalog.dart';
import '../core/services/alarm_sound_prefs.dart';
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

    // Medications can carry more than one dose time a day, e.g.
    // "8:00 AM, 8:00 PM" for "Twice daily" — schedule each separately.
    final rawTimes = reminder.time
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (rawTimes.isEmpty) {
      debugPrint(
          '[NotificationService] scheduleReminder: no time set for "${reminder.title}" — skipped');
      return;
    }

    final weekdays = _weekdaysFor(reminder.schedule);
    final selectedSound = await AlarmSoundPrefs.instance.getSelected();

    for (var timeIndex = 0; timeIndex < rawTimes.length; timeIndex++) {
      final time = _parseTimeOfDay(rawTimes[timeIndex]);
      if (time == null) {
        debugPrint(
            '[NotificationService] scheduleReminder: unparseable time "${rawTimes[timeIndex]}" for "${reminder.title}" — skipped');
        continue;
      }
      await _scheduleOneTime(
        reminder: reminder,
        time: time,
        displayTime: rawTimes[timeIndex],
        timeIndex: timeIndex,
        weekdays: weekdays,
        selectedSound: selectedSound,
      );
    }
  }

  Future<void> _scheduleOneTime({
    required Reminder reminder,
    required TimeOfDay time,
    required String displayTime,
    required int timeIndex,
    required List<int>? weekdays,
    required AlarmSoundOption selectedSound,
  }) async {
    final baseId = _baseIdFor(reminder.title, timeIndex);
    final message = reminder.dose.trim().isEmpty
        ? 'Time to take ${reminder.title}'
        : 'Time to take ${reminder.title} · ${reminder.dose}';
    final payload = jsonEncode({
      'title': 'Medicine Reminder',
      'message': message,
      'time': displayTime,
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
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
        sound: selectedSound.id.isEmpty ? null : selectedSound.iosFilename,
      ),
    );

    // Reminder IDs the native alarm layer needs to be unique per dose time,
    // not just per reminder — otherwise a second dose time for the same
    // medication would overwrite the first alarm instead of adding to it.
    final nativeReminderId =
        '${reminder.id ?? reminder.title}#$timeIndex';

    // The native alarm owns Android's visible alarm notification. Do not also
    // schedule flutter_local_notifications here: two independent Android
    // schedulers firing together produce two notifications for one reminder.
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (weekdays == null) {
        await NativeAlarmBridge.instance.scheduleAlarm(
          reminderId: nativeReminderId,
          title: reminder.title,
          dose: reminder.dose,
          displayTime: displayTime,
          hour: time.hour,
          minute: time.minute,
          repeatType: 'daily',
          soundRawResName: selectedSound.id,
        );
      } else {
        for (final weekday in weekdays) {
          await NativeAlarmBridge.instance.scheduleAlarm(
            reminderId: nativeReminderId,
            title: reminder.title,
            dose: reminder.dose,
            displayTime: displayTime,
            hour: time.hour,
            minute: time.minute,
            repeatType: 'weekly',
            soundRawResName: selectedSound.id,
            weekday: weekday,
          );
        }
      }
      return;
    }

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
        reminderId: nativeReminderId,
        title: reminder.title,
        dose: reminder.dose,
        displayTime: displayTime,
        hour: time.hour,
        minute: time.minute,
        repeatType: 'daily',
        soundRawResName: selectedSound.id,
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
          reminderId: nativeReminderId,
          title: reminder.title,
          dose: reminder.dose,
          displayTime: displayTime,
          hour: time.hour,
          minute: time.minute,
          repeatType: 'weekly',
          soundRawResName: selectedSound.id,
          weekday: weekday,
        );
      }
    }
  }

  /// Cancels every alarm belonging to [reminder] (used before rescheduling,
  /// on edit, and on delete). Covers every dose-time slot (a medication can
  /// have up to a few times a day) crossed with every weekday offset.
  Future<void> cancelForReminder(Reminder reminder) async {
    const maxTimeSlots = 5;
    for (var timeIndex = 0; timeIndex < maxTimeSlots; timeIndex++) {
      final baseId = _baseIdFor(reminder.title, timeIndex);
      await _plugin.cancel(baseId);
      for (var weekday = 1; weekday <= 7; weekday++) {
        await _plugin.cancel(baseId + weekday);
      }
      // ── Native Alarm Bridge ──────────────────────────────────────────
      await NativeAlarmBridge.instance
          .cancelAlarm('${reminder.id ?? reminder.title}#$timeIndex');
    }
    // Cancel the pre-multi-dose id scheme too, for reminders created before
    // this change (their alarms were registered without a "#index" suffix).
    await NativeAlarmBridge.instance.cancelAlarm(reminder.id ?? reminder.title);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
    await NativeAlarmBridge.instance.cancelAllAlarms();
  }

  /// A stable id derived from the reminder's title plus which dose-time
  /// slot this is (0, 1, 2…) so a medication with several times a day gets
  /// a distinct alarm per time instead of one overwriting another. Titles
  /// are locked once a reminder is created (see reminders_screen.dart), so
  /// this stays consistent across edits without needing an `id` field.
  int _baseIdFor(String title, [int timeIndex = 0]) =>
      (title.hashCode.abs() % 100000) * 10 + timeIndex * 1000;

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
    if (schedule == 'Daily') return null;
    if (schedule == 'Weekdays') return const [1, 2, 3, 4, 5];
    if (schedule == 'Mon · Wed · Fri') return const [1, 3, 5];

    // Handle custom list: "Mon · Tue · Sat"
    const dayMap = {
      'Mon': 1,
      'Tue': 2,
      'Wed': 3,
      'Thu': 4,
      'Fri': 5,
      'Sat': 6,
      'Sun': 7
    };
    final parts = schedule.split(' · ');
    final result = <int>[];
    for (var p in parts) {
      if (dayMap.containsKey(p)) result.add(dayMap[p]!);
    }

    return result.isEmpty ? null : result;
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