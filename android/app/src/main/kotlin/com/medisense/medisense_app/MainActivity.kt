package com.medisense.medisense_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "medisense_native_channel"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d("SOS_DEBUG", "MainActivity: configureFlutterEngine entry")
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            Log.d("SOS_DEBUG", "MainActivity: Native method call received: ${call.method}")
            try {
                when (call.method) {
                    "triggerSosNow" -> {
                        Log.d("SOS_DEBUG", "MainActivity: triggerSosNow entry")
                        triggerNativeSos()
                        result.success(null)
                    }
                    "bringToForeground" -> {
                        Log.d("SOS_DEBUG", "MainActivity: bringToForeground entry")
                        forceAppToFront()
                        result.success(null)
                    }
                    "scheduleAlarm" -> {
                        Log.d("SOS_DEBUG", "MainActivity: scheduleAlarm entry")
                        handleScheduleAlarm(call, result)
                    }
                    "cancelAlarm" -> {
                        Log.d("SOS_DEBUG", "MainActivity: cancelAlarm entry")
                        handleCancelAlarm(call, result)
                    }
                    "cancelAllAlarms" -> {
                        Log.d("SOS_DEBUG", "MainActivity: cancelAllAlarms entry")
                        AlarmScheduler.cancelAllStored(this)
                        result.success(null)
                    }
                    "ensureFullScreenIntentPermission" -> {
                        Log.d("SOS_DEBUG", "MainActivity: ensureFullScreenIntentPermission entry")
                        result.success(null)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        Log.d("SOS_DEBUG", "MainActivity: requestIgnoreBatteryOptimizations entry")
                        handleRequestIgnoreBatteryOptimizations(result)
                    }
                    else -> {
                        Log.w("SOS_DEBUG", "MainActivity: Method not implemented: ${call.method}")
                        result.notImplemented()
                    }
                }
            } catch (e: Exception) {
                Log.e("SOS_DEBUG", "MainActivity: Method call exception: ${e.message}", e)
                result.error("NATIVE_ERROR", e.message, null)
            }
        }
        
        // Handle cold start
        handleIntent(intent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d("SOS_DEBUG", "MainActivity: onCreate entry")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d("SOS_DEBUG", "MainActivity: onNewIntent entry")
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val action = intent?.getStringExtra("action")
        val data = intent?.data
        Log.d("SOS_DEBUG", "MainActivity: handleIntent entry. action: $action, data: $data")
        
        if (action == "OPEN_SOS" || data?.scheme == "medisense") {
            Log.d("SOS_DEBUG", "MainActivity: SOS signal detected, notifying Flutter")
            methodChannel?.invokeMethod("openSosScreen", null)
        }
    }

    private fun forceAppToFront() {
        Log.d("SOS_DEBUG", "MainActivity: forceAppToFront entry")
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        if (intent != null) {
            Log.d("SOS_DEBUG", "MainActivity: forceAppToFront - launching")
            startActivity(intent)
        }
    }

    private fun triggerNativeSos() {
        Log.d("SOS_DEBUG", "MainActivity: triggerNativeSos (Full Screen Alert) starting")
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("action", "OPEN_SOS")
        }

        if (intent == null) {
            Log.e("SOS_DEBUG", "MainActivity: triggerNativeSos - launch intent is null")
            return
        }

        val pendingIntent = PendingIntent.getActivity(
            this, 911, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "sos_alert_pro_v1"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "SOS Emergency System", NotificationManager.IMPORTANCE_HIGH).apply {
                setBypassDnd(true)
                enableVibration(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("CRITICAL SOS ALERT")
            .setContentText("Emergency Dashboard is opening...")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(pendingIntent, true) // THE NUCLEAR OPTION
            .setAutoCancel(true)
            .setOngoing(false)
            .build()

        Log.d("SOS_DEBUG", "MainActivity: Posting full-screen notification")
        nm.notify(911, notification)
        
        // Backup: Try to start directly
        try {
            startActivity(intent)
        } catch (e: Exception) {
            Log.e("SOS_DEBUG", "MainActivity: triggerNativeSos direct startActivity failed: ${e.message}")
        }
    }

    private fun handleScheduleAlarm(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
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
            Log.e("SOS_DEBUG", "MainActivity: handleScheduleAlarm ERROR: ${e.message}")
            result.error("EXCEPTION", e.message, null)
        }
    }

    private fun handleCancelAlarm(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val reminderId = call.argument<String>("reminderId")
        if (reminderId != null) {
            AlarmScheduler.cancelAllForReminder(this, reminderId)
            result.success(null)
        } else {
            result.error("INVALID_ARGUMENTS", "reminderId is null", null)
        }
    }

    private fun handleRequestIgnoreBatteryOptimizations(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } catch (e: Exception) {}
        }
        result.success(null)
    }
}
