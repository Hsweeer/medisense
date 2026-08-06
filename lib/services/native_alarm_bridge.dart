import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Talks to the native Android alarm system (AlarmManager + a foreground
/// service + a full-screen AlarmActivity — see android/app/.../Alarm*.kt).
/// This is intentionally a separate, additive layer: [NotificationService]
/// keeps scheduling its existing flutter_local_notifications alarm exactly
/// as before (so notification history keeps working unchanged), and now
/// also calls into this bridge so the same reminder additionally rings as a
/// full-screen alarm — like the stock Clock app — even while the phone is
/// locked or the app is fully closed.
///
/// No-ops (safely) on iOS/any non-Android platform.
class NativeAlarmBridge {
  NativeAlarmBridge._();
  static final NativeAlarmBridge instance = NativeAlarmBridge._();

  static const _channel = MethodChannel('medisense_native_channel');

  bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  /// Schedules one native alarm slot.
  ///
  /// [weekday] is 1 (Mon) .. 7 (Sun) and only meaningful when
  /// [repeatType] is `'weekly'`; pass null for `'daily'`.
  Future<void> scheduleAlarm({
    required String reminderId,
    required String title,
    required String dose,
    required String displayTime,
    required int hour,
    required int minute,
    required String repeatType, // 'daily' | 'weekly'
    String? soundRawResName,
    int? weekday,
  }) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('scheduleAlarm', {
        'reminderId': reminderId,
        'title': title,
        'dose': dose,
        'displayTime': displayTime,
        'hour': hour,
        'minute': minute,
        'repeatType': repeatType,
        'soundRawResName': soundRawResName?.isEmpty ?? true
            ? null
            : soundRawResName,
        'weekday': weekday,
      });
    } catch (e) {
      debugPrint('[NativeAlarmBridge] scheduleAlarm error: $e');
    }
  }

  /// Cancels every native alarm slot (daily + all weekdays + any pending
  /// snooze) belonging to [reminderId].
  Future<void> cancelAlarm(String reminderId) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('cancelAlarm', {'reminderId': reminderId});
    } catch (e) {
      debugPrint('[NativeAlarmBridge] cancelAlarm error: $e');
    }
  }

  Future<void> cancelAllAlarms() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('cancelAllAlarms');
    } catch (e) {
      debugPrint('[NativeAlarmBridge] cancelAllAlarms error: $e');
    }
  }

  /// On Android 14+, full-screen alarm intents require an explicit grant via
  /// Settings (below API 34 it's automatic). Best-effort — opens the system
  /// settings screen only if not already granted; safe to call every launch.
  Future<void> ensureFullScreenIntentPermission() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('ensureFullScreenIntentPermission');
    } catch (e) {
      debugPrint('[NativeAlarmBridge] ensureFullScreenIntentPermission error: $e');
    }
  }

  /// Best-effort prompt to exempt the app from battery optimizations, so
  /// Doze mode doesn't delay the exact alarm. Safe to call every launch —
  /// it's a no-op if already exempt.
  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (e) {
      debugPrint('[NativeAlarmBridge] requestIgnoreBatteryOptimizations error: $e');
    }
  }
}
