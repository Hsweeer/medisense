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
import android.speech.tts.TextToSpeech
import androidx.core.app.NotificationCompat
import com.medisense.medisense_app.R
import java.util.Locale

class AlarmRingingService : Service(), TextToSpeech.OnInitListener {

    companion object {
        const val ACTION_RING = "com.medisense.medisense_app.action.RING"
        const val ACTION_STOP = "com.medisense.medisense_app.action.STOP"
        const val ACTION_SNOOZE = "com.medisense.medisense_app.action.SNOOZE"

        private const val CHANNEL_ID = "medisense_alarm_ringing_v2"
        private const val FOREGROUND_NOTIFICATION_ID = 991_001
        private const val SNOOZE_MINUTES = 10
    }

    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var tts: TextToSpeech? = null
    private var ttsInitialized = false

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

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            tts?.let {
                val result = it.setLanguage(Locale.US)
                if (result != TextToSpeech.LANG_MISSING_DATA && result != TextToSpeech.LANG_NOT_SUPPORTED) {
                    ttsInitialized = true
                    speakMedicineTime()
                }
            }
        }
    }

    private fun speakMedicineTime() {
        if (ttsInitialized) {
            val text = "It's your medicine time."
            for (i in 1..3) {
                tts?.speak(text, TextToSpeech.QUEUE_ADD, null, "medicine_alert_$i")
                tts?.playSilentUtterance(1500, TextToSpeech.QUEUE_ADD, null)
            }
        }
    }

    private fun startRinging(intent: Intent?) {
        currentAlarmId = intent?.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, -1) ?: -1
        currentReminderId = intent?.getStringExtra(AlarmScheduler.EXTRA_REMINDER_ID) ?: ""
        currentTitle = intent?.getStringExtra(AlarmScheduler.EXTRA_TITLE) ?: "Medicine Reminder"
        currentDose = intent?.getStringExtra(AlarmScheduler.EXTRA_DOSE) ?: ""
        currentDisplayTime = intent?.getStringExtra(AlarmScheduler.EXTRA_DISPLAY_TIME) ?: ""
        currentSoundRawResName = intent?.getStringExtra(AlarmScheduler.EXTRA_SOUND_RAW_RES_NAME) ?: ""

        // 1. UI FIRST: Launch activity before anything else
        launchAlarmActivity()
        
        // 2. IMMEDIATE WAKE LOCK
        acquireWakeLock()

        // 3. START FOREGROUND
        val notification = buildForegroundNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(FOREGROUND_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(FOREGROUND_NOTIFICATION_ID, notification)
        }

        // 4. AUDIO / VIBE
        startSound()
        startVibration()
        tts = TextToSpeech(this, this)
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        @Suppress("DEPRECATION")
        wakeLock = pm.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
            "medisense:alarm_instant_wakeup",
        ).apply {
            setReferenceCounted(false)
            acquire(60 * 1000L)
        }
    }

    private fun launchAlarmActivity() {
        val activityIntent = Intent(this, AlarmActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                Intent.FLAG_ACTIVITY_NO_USER_ACTION
            putExtra(AlarmScheduler.EXTRA_ALARM_ID, currentAlarmId)
            putExtra(AlarmScheduler.EXTRA_REMINDER_ID, currentReminderId)
            putExtra(AlarmScheduler.EXTRA_TITLE, currentTitle)
            putExtra(AlarmScheduler.EXTRA_DOSE, currentDose)
            putExtra(AlarmScheduler.EXTRA_DISPLAY_TIME, currentDisplayTime)
            putExtra(AlarmScheduler.EXTRA_SOUND_RAW_RES_NAME, currentSoundRawResName)
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
                description = "Urgent medicine reminder"
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(channel)
        }

        val fullScreenIntent = Intent(this, AlarmActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(AlarmScheduler.EXTRA_ALARM_ID, currentAlarmId)
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            this,
            currentAlarmId,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Medicine Alarm")
            .setContentText("Time for your medication")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setOngoing(true)
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
        tts?.let { it.stop(); it.shutdown() }
        tts = null
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(FOREGROUND_NOTIFICATION_ID)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(Service.STOP_FOREGROUND_REMOVE)
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
