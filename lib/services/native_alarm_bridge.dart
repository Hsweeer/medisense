import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Talks to the native Android alarm system (AlarmManager + a foreground
/// service + a full-screen AlarmActivity — see android/app/.../Alarm*.kt).
class NativeAlarmBridge {
  NativeAlarmBridge._();
  static final NativeAlarmBridge instance = NativeAlarmBridge._();

  static const _channel = MethodChannel('medisense_native_channel');

  bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  /// Schedules one native alarm slot.
  Future<void> scheduleAlarm({
    required String reminderId,
    required String title,
    required String dose,
    required String displayTime,
    required int hour,
    required int minute,
    required String repeatType, // 'daily' | 'weekly' | 'interval'
    String? soundRawResName,
    int? weekday,
    int? intervalDays, // only meaningful when repeatType == 'interval'
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
        'soundRawResName': soundRawResName?.isEmpty ?? true ? null : soundRawResName,
        'weekday': weekday,
        'intervalDays': intervalDays,
      });
    } catch (e) {
      debugPrint('[NativeAlarmBridge] scheduleAlarm error: $e');
    }
  }

  /// Schedules a one-off snooze alarm for [minutes] from now.
  Future<void> snoozeAlarm({
    required String reminderId,
    required String title,
    int minutes = 10,
    String? soundRawResName,
  }) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('snoozeAlarm', {
        'reminderId': reminderId,
        'title': title,
        'minutes': minutes,
        'soundRawResName': soundRawResName?.isEmpty ?? true ? null : soundRawResName,
      });
      debugPrint('[NativeAlarmBridge] snoozeAlarm scheduled for $minutes min');
    } catch (e) {
      debugPrint('[NativeAlarmBridge] snoozeAlarm error: $e');
    }
  }

  /// Cancels future alarms for this reminder.
  Future<void> cancelAlarm(String reminderId) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('cancelAlarm', {'reminderId': reminderId});
    } catch (e) {
      debugPrint('[NativeAlarmBridge] cancelAlarm error: $e');
    }
  }

  /// IMMEDIATELY stops the alarm if it is currently ringing.
  Future<void> stopRinging() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('stopRinging');
      debugPrint('[NativeAlarmBridge] stopRinging command sent');
    } catch (e) {
      debugPrint('[NativeAlarmBridge] stopRinging error: $e');
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

  Future<void> ensureFullScreenIntentPermission() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('ensureFullScreenIntentPermission');
    } catch (e) {
      debugPrint('[NativeAlarmBridge] ensureFullScreenIntentPermission error: $e');
    }
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (e) {
      debugPrint('[NativeAlarmBridge] requestIgnoreBatteryOptimizations error: $e');
    }
  }
}