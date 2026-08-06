package com.medisense.medisense_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "medisense_native_channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "triggerSosNow" -> {
                    triggerNativeSos()
                    result.success(null)
                }
                "bringToForeground" -> {
                    forceAppToFront()
                    result.success(null)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                    }
                    result.success(null)
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
                    // Handled via manifest, but can be added here if needed for API 34+
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun forceAppToFront() {
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        if (intent != null) startActivity(intent)
    }

    private fun triggerNativeSos() {
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("action", "SOS")
        }

        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "critical_sos_alert"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "Emergency SOS", NotificationManager.IMPORTANCE_HIGH).apply {
                setBypassDnd(true)
                enableVibration(true)
            }
            nm.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("SOS TRIGGERED")
            .setContentText("Emergency Dashboard is opening...")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(pendingIntent, true)
            .setAutoCancel(true)
            .setOngoing(true)
            .build()

        nm.notify(911, notification)
        forceAppToFront()
    }
}
