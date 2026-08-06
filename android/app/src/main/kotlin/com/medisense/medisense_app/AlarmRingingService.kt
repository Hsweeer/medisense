package com.medisense.medisense_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat

class AlarmRingingService : Service() {

    companion object {
        const val ACTION_RING = "com.medisense.medisense_app.action.RING"
        const val ACTION_STOP = "com.medisense.medisense_app.action.STOP"
        const val ACTION_SNOOZE = "com.medisense.medisense_app.action.SNOOZE"

        private const val CHANNEL_ID = "medisense_alarm_ringing"
        private const val FOREGROUND_NOTIFICATION_ID = 991_001
        private const val SNOOZE_MINUTES = 10
    }

    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private var currentAlarmId: Int = -1
    private var currentReminderId: String = ""
    private var currentTitle: String = ""
    private var currentDose: String = ""
    private var currentDisplayTime: String = ""
    private var currentSoundRawResName: String = ""

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopRinging()
                stopSelf()
            }
            ACTION_SNOOZE -> {
                snooze()
                stopRinging()
                stopSelf()
            }
            else -> startRinging(intent)
        }
        return START_NOT_STICKY
    }

    private fun startRinging(intent: Intent?) {
        currentAlarmId = intent?.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, -1) ?: -1
        currentReminderId = intent?.getStringExtra(AlarmScheduler.EXTRA_REMINDER_ID) ?: ""
        currentTitle = intent?.getStringExtra(AlarmScheduler.EXTRA_TITLE) ?: "Medicine Reminder"
        currentDose = intent?.getStringExtra(AlarmScheduler.EXTRA_DOSE) ?: ""
        currentDisplayTime = intent?.getStringExtra(AlarmScheduler.EXTRA_DISPLAY_TIME) ?: ""
        currentSoundRawResName = intent?.getStringExtra(AlarmScheduler.EXTRA_SOUND_RAW_RES_NAME) ?: ""

        // 1. Immediate Wake Lock to light up screen
        acquireWakeLock()

        // 2. Build and Start Foreground Service immediately
        val notification = buildForegroundNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(FOREGROUND_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(FOREGROUND_NOTIFICATION_ID, notification)
        }

        // 3. FORCE launch AlarmActivity immediately (removing the locked check for better reliability)
        launchAlarmActivity()

        // 4. Start Sound and Vibration
        startSound()
        startVibration()
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        @Suppress("DEPRECATION")
        wakeLock = pm.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
            "medisense:alarm_ringing_wakeup",
        ).apply {
            setReferenceCounted(false)
            acquire(60 * 1000L) // 1 minute is plenty
        }
    }

    private fun launchAlarmActivity() {
        val activityIntent = Intent(this, AlarmActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            putExtra(AlarmScheduler.EXTRA_ALARM_ID, currentAlarmId)
            putExtra(AlarmScheduler.EXTRA_REMINDER_ID, currentReminderId)
            putExtra(AlarmScheduler.EXTRA_TITLE, currentTitle)
            putExtra(AlarmScheduler.EXTRA_DOSE, currentDose)
            putExtra(AlarmScheduler.EXTRA_DISPLAY_TIME, currentDisplayTime)
            putExtra(AlarmScheduler.EXTRA_SOUND_RAW_RES_NAME, currentSoundRawResName)
        }
        try {
            startActivity(activityIntent)
        } catch (e: Exception) {
            // Log if needed
        }
    }

    private fun buildForegroundNotification(): android.app.Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Medicine Alarm",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Full-screen medicine alarm"
                setSound(null, null)
                enableVibration(false)
            }
            nm.createNotificationChannel(channel)
        }

        val fullScreenIntent = Intent(this, AlarmActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(AlarmScheduler.EXTRA_ALARM_ID, currentAlarmId)
            putExtra(AlarmScheduler.EXTRA_REMINDER_ID, currentReminderId)
            putExtra(AlarmScheduler.EXTRA_TITLE, currentTitle)
            putExtra(AlarmScheduler.EXTRA_DOSE, currentDose)
            putExtra(AlarmScheduler.EXTRA_DISPLAY_TIME, currentDisplayTime)
            putExtra(AlarmScheduler.EXTRA_SOUND_RAW_RES_NAME, currentSoundRawResName)
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            this,
            currentAlarmId,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        val message = if (currentDose.isBlank()) "Time to take $currentTitle" else "Time to take $currentTitle · $currentDose"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Medicine Alarm")
            .setContentText(message)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()
    }

    private fun startSound() {
        try {
            val alarmUri = selectedSoundUri() ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                setDataSource(this@AlarmRingingService, alarmUri)
                isLooping = true
                prepare()
                start()
            }
        } catch (_: Exception) {}
    }

    private fun selectedSoundUri(): Uri? {
        val rawName = currentSoundRawResName
        if (!rawName.matches(Regex("[a-z0-9_]+"))) return RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_ALARM)
        val resourceId = resources.getIdentifier(rawName, "raw", packageName)
        return if (resourceId != 0) Uri.parse("android.resource://$packageName/$resourceId") else RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_ALARM)
    }

    private fun startVibration() {
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION") getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        val pattern = longArrayOf(0, 1000, 500)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION") vibrator?.vibrate(pattern, 0)
        }
    }

    private fun snooze() {
        if (currentReminderId.isBlank()) return
        val snoozeAt = System.currentTimeMillis() + SNOOZE_MINUTES * 60 * 1000L
        val cal = java.util.Calendar.getInstance().apply { timeInMillis = snoozeAt }
        val entry = AlarmStore.AlarmEntry(
            alarmId = AlarmScheduler.snoozeIdFor(currentReminderId),
            reminderId = currentReminderId,
            title = currentTitle,
            dose = currentDose,
            displayTime = currentDisplayTime,
            hour = cal.get(java.util.Calendar.HOUR_OF_DAY),
            minute = cal.get(java.util.Calendar.MINUTE),
            repeatType = "once",
            weekday = 0,
            soundRawResName = currentSoundRawResName,
        )
        AlarmScheduler.schedule(this, entry)
    }

    private fun stopRinging() {
        mediaPlayer?.let { try { if (it.isPlaying) it.stop(); it.release() } catch (_: Exception) {} }
        mediaPlayer = null
        vibrator?.cancel()
        vibrator = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(FOREGROUND_NOTIFICATION_ID)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true)
    }

    override fun onDestroy() {
        stopRinging()
        super.onDestroy()
    }
}
