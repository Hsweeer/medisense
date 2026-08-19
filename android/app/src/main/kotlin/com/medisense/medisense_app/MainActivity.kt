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
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "medisense_native_channel"
    private var methodChannel: MethodChannel? = null
    private var pendingSos = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d("SOS_DEBUG", "MainActivity: configureFlutterEngine entry")
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            Log.d("SOS_DEBUG", "MainActivity: Native method call received: ${call.method}")
            try {
                when (call.method) {
                    "flutterReady" -> {
                        Log.d("SOS_DEBUG", "MainActivity: Flutter reported ready")
                        if (pendingSos) {
                            Log.d("SOS_DEBUG", "MainActivity: Triggering stored pending SOS")
                            triggerSosInFlutter()
                        }
                        result.success(null)
                    }
                    "triggerSosNow" -> {
                        triggerNativeSosWithDeepLink()
                        result.success(null)
                    }
                    "bringToForeground" -> {
                        forceAppToFront()
                        result.success(null)
                    }
                    "scheduleAlarm" -> {
                        handleScheduleAlarm(call, result)
                    }
                    "snoozeAlarm" -> {
                        handleSnoozeAlarm(call, result)
                    }
                    "cancelAlarm" -> {
                        handleCancelAlarm(call, result)
                    }
                    "cancelAllAlarms" -> {
                        AlarmScheduler.cancelAllStored(this)
                        result.success(null)
                    }
                    "stopRinging" -> {
                        val stopIntent = Intent(this, AlarmRingingService::class.java).apply {
                            action = AlarmRingingService.ACTION_STOP
                        }
                        startService(stopIntent)
                        result.success(null)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        handleRequestIgnoreBatteryOptimizations(result)
                    }
                    "ensureFullScreenIntentPermission" -> {
                        result.success(null) 
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            } catch (e: Exception) {
                Log.e("SOS_DEBUG", "MainActivity: Method call exception: ${e.message}", e)
                result.error("NATIVE_ERROR", e.message, null)
            }
        }
        
        checkIntentForSos(intent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d("SOS_DEBUG", "MainActivity: onCreate entry")
        
        createNotificationChannel()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                "sos_channel",
                "SOS Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Used to launch the SOS screen instantly, including over the lock screen"
                setBypassDnd(true)
                enableVibration(true)
            }
            manager.createNotificationChannel(channel)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d("SOS_DEBUG", "MainActivity: onNewIntent entry")
        setIntent(intent)
        checkIntentForSos(intent)
    }

    private fun checkIntentForSos(intent: Intent?) {
        val action = intent?.action
        val data = intent?.data
        Log.d("SOS_DEBUG", "MainActivity: checkIntentForSos. action: $action, data: $data")
        
        if (data?.scheme == "medisense" && data?.host == "sos") {
            Log.d("SOS_DEBUG", "MainActivity: SOS deep link detected")
            pendingSos = true
            triggerSosInFlutter()
        } else if (intent?.getStringExtra("action") == "OPEN_SOS") {
            Log.d("SOS_DEBUG", "MainActivity: SOS intent extra detected")
            pendingSos = true
            triggerSosInFlutter()
        }
    }

    private fun triggerSosInFlutter() {
        if (methodChannel != null) {
            Log.d("SOS_DEBUG", "MainActivity: Notifying Flutter engine to open SOS screen")
            methodChannel?.invokeMethod("openSosScreen", null)
            pendingSos = false
        } else {
            Log.d("SOS_DEBUG", "MainActivity: Engine not ready yet, SOS remains pending")
        }
    }

    private fun forceAppToFront() {
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        if (intent != null) startActivity(intent)
    }

    private fun triggerNativeSosWithDeepLink() {
        Log.d("SOS_DEBUG", "MainActivity: triggerNativeSosWithDeepLink starting")
        val deepLinkIntent = Intent(Intent.ACTION_VIEW, Uri.parse("medisense://sos")).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            setPackage(packageName)
        }

        val pendingIntent = PendingIntent.getActivity(
            this, 0, deepLinkIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        val notification = NotificationCompat.Builder(this, "sos_channel")
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("SOS Activated")
            .setContentText("Opening SOS screen...")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setFullScreenIntent(pendingIntent, true)
            .setAutoCancel(true)
            .build()

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(1001, notification)
    }

    private fun handleScheduleAlarm(call: MethodCall, result: MethodChannel.Result) {
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
            val intervalDays = call.argument<Int>("intervalDays") ?: 0

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
                    soundRawResName = soundRawResName,
                    intervalDays = intervalDays
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

    private fun handleSnoozeAlarm(call: MethodCall, result: MethodChannel.Result) {
        try {
            val reminderId = call.argument<String>("reminderId")
            val title = call.argument<String>("title")
            val minutes = call.argument<Int>("minutes") ?: 10
            val soundRawResName = call.argument<String>("soundRawResName") ?: ""

            if (reminderId != null && title != null) {
                // Construct a minimal entry just to pass the data through.
                // Snooze alarms use the reserved SNOOZE_SUB_ID.
                val entry = AlarmStore.AlarmEntry(
                    alarmId = AlarmScheduler.snoozeIdFor(reminderId),
                    reminderId = reminderId,
                    title = title,
                    dose = "",
                    displayTime = "",
                    hour = 0,
                    minute = 0,
                    repeatType = "snooze",
                    weekday = 0,
                    soundRawResName = soundRawResName
                )
                AlarmScheduler.snooze(this, entry, minutes)
                result.success(null)
            } else {
                result.error("INVALID_ARGUMENTS", "Missing required arguments", null)
            }
        } catch (e: Exception) {
            result.error("EXCEPTION", e.message, null)
        }
    }

    private fun handleCancelAlarm(call: MethodCall, result: MethodChannel.Result) {
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
