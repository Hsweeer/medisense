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
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat

/**
 * Rings the alarm: loops the system default alarm sound, vibrates
 * continuously, keeps the CPU awake, and shows a full-screen-intent
 * notification that launches [AlarmActivity]. Everything stops the moment
 * Stop or Snooze is pressed on that activity.
 *
 * This channel/notification is entirely separate from
 * `medisense_reminders` (owned by the Dart NotificationService) and from
 * the JSON notification-history feature — neither is touched by this
 * service.
 */
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

        acquireWakeLock()
        
        val notification = buildForegroundNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(FOREGROUND_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(FOREGROUND_NOTIFICATION_ID, notification)
        }

        launchAlarmActivity()
        startSound()
        startVibration()
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "medisense:alarm_ringing",
        ).apply {
            setReferenceCounted(false)
            acquire(10 * 60 * 1000L) // safety cap: 10 minutes
        }
    }

    private fun launchAlarmActivity() {
        val activityIntent = Intent(this, AlarmActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(AlarmScheduler.EXTRA_ALARM_ID, currentAlarmId)
            putExtra(AlarmScheduler.EXTRA_REMINDER_ID, currentReminderId)
            putExtra(AlarmScheduler.EXTRA_TITLE, currentTitle)
            putExtra(AlarmScheduler.EXTRA_DOSE, currentDose)
            putExtra(AlarmScheduler.EXTRA_DISPLAY_TIME, currentDisplayTime)
        }
        startActivity(activityIntent)
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
                enableVibration(false) // vibration is handled manually so it never stops early
                setSound(null, null) // sound is handled manually via looping MediaPlayer
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
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            this,
            currentAlarmId,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val message = if (currentDose.isBlank()) {
            "Time to take $currentTitle"
        } else {
            "Time to take $currentTitle · $currentDose"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Medicine Alarm")
            .setContentText(message)
            .setSubText(currentDisplayTime)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setContentIntent(fullScreenPendingIntent)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()
    }

    private fun startSound() {
        try {
            val alarmUri = RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                setDataSource(this@AlarmRingingService, alarmUri)
                isLooping = true
                setVolume(1.0f, 1.0f)
                prepare()
                start()
            }
        } catch (_: Exception) {
            // Device has no accessible alarm sound URI — vibration still runs,
            // and the full-screen UI + notification still get the user's attention.
        }
    }

    private fun startVibration() {
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        val pattern = longArrayOf(0, 800, 400) // wait, buzz, pause — repeats
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }

    private fun snooze() {
        if (currentReminderId.isBlank()) return
        val snoozeAt = System.currentTimeMillis() + SNOOZE_MINUTES * 60 * 1000L
        val cal = java.util.Calendar.getInstance().apply { timeInMillis = snoozeAt }
        // Uses the reserved snooze sub-id (never the recurring alarm's own
        // id) and repeatType "once", so this single extra fire in 10
        // minutes can never overwrite the stored hour/minute of the
        // reminder's real daily/weekly schedule.
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
        )
        AlarmScheduler.schedule(this, entry)
    }

    private fun stopRinging() {
        mediaPlayer?.let {
            try {
                if (it.isPlaying) it.stop()
                it.release()
            } catch (_: Exception) {
            }
        }
        mediaPlayer = null

        vibrator?.cancel()
        vibrator = null

        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(FOREGROUND_NOTIFICATION_ID)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    override fun onDestroy() {
        stopRinging()
        super.onDestroy()
    }
}
