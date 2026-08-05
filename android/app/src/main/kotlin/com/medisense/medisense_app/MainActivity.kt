package com.medisense.medisense_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.medisense.medisense_app/native_alarm"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "bringToForeground" -> {
                    try {
                        val intent = packageManager.getLaunchIntentForPackage(packageName)
                        if (intent != null) {
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                            intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                            startActivity(intent)
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("FAILED", e.message, null)
                    }
                }
                "scheduleAlarm" -> {
                    try {
                        val reminderId = call.argument<String>("reminderId")
                        val title = call.argument<String>("title")
                        val dose = call.argument<String>("dose") ?: ""
                        val displayTime = call.argument<String>("displayTime") ?: ""
                        val hour = call.argument<Int>("hour")
                        val minute = call.argument<Int>("minute")
                        val repeatType = call.argument<String>("repeatType") ?: "daily"
                        val weekday = call.argument<Int>("weekday") ?: 0
                        val soundRawResName = call.argument<String>("soundRawResName") ?: ""

                        if (reminderId != null && title != null && hour != null && minute != null) {
                            val entry = AlarmStore.AlarmEntry(
                                alarmId = AlarmScheduler.idFor(reminderId, if (weekday == 0) null else weekday),
                                reminderId = reminderId,
                                title = title,
                                dose = dose,
                                displayTime = displayTime,
                                hour = hour,
                                minute = minute,
                                repeatType = repeatType,
                                weekday = weekday,
                                soundRawResName = soundRawResName
                            )
                            AlarmScheduler.schedule(this, entry)
                            result.success(null)
                        } else {
                            result.error("INVALID_ARGUMENTS", "Missing required arguments", null)
                        }
                    } catch (e: Exception) {
                        result.error("EXCEPTION", e.message, null)
                    }
                }
                "cancelAlarm" -> {
                    val reminderId = call.argument<String>("reminderId")
                    if (reminderId != null) {
                        AlarmScheduler.cancelAllForReminder(this, reminderId)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENTS", "reminderId is null", null)
                    }
                }
                "cancelAllAlarms" -> {
                    AlarmScheduler.cancelAllStored(this)
                    result.success(null)
                }
                "ensureFullScreenIntentPermission" -> {
                    result.success(null)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                        } catch (e: Exception) {
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
