package com.medisense.medisense_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Fires at the exact moment a scheduled reminder alarm is due. Its only two
 * jobs: (1) hand off to [AlarmRingingService] so the actual ringing/full
 * screen experience is a well-behaved foreground service rather than work
 * done on this short-lived receiver, and (2) re-arm the same alarm for its
 * next occurrence (AlarmManager one-shots do not repeat on their own).
 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, -1)
        if (alarmId == -1) return

        val reminderId = intent.getStringExtra(AlarmScheduler.EXTRA_REMINDER_ID) ?: return
        val title = intent.getStringExtra(AlarmScheduler.EXTRA_TITLE) ?: "Medicine Reminder"
        val dose = intent.getStringExtra(AlarmScheduler.EXTRA_DOSE) ?: ""
        val displayTime = intent.getStringExtra(AlarmScheduler.EXTRA_DISPLAY_TIME) ?: ""
        val hour = intent.getIntExtra(AlarmScheduler.EXTRA_HOUR, 0)
        val minute = intent.getIntExtra(AlarmScheduler.EXTRA_MINUTE, 0)
        val repeatType = intent.getStringExtra(AlarmScheduler.EXTRA_REPEAT_TYPE) ?: "daily"
        val weekday = intent.getIntExtra(AlarmScheduler.EXTRA_WEEKDAY, 0)
        val soundRawResName = intent.getStringExtra(AlarmScheduler.EXTRA_SOUND_RAW_RES_NAME) ?: ""

        val serviceIntent = Intent(context, AlarmRingingService::class.java).apply {
            action = AlarmRingingService.ACTION_RING
            putExtra(AlarmScheduler.EXTRA_ALARM_ID, alarmId)
            putExtra(AlarmScheduler.EXTRA_REMINDER_ID, reminderId)
            putExtra(AlarmScheduler.EXTRA_TITLE, title)
            putExtra(AlarmScheduler.EXTRA_DOSE, dose)
            putExtra(AlarmScheduler.EXTRA_DISPLAY_TIME, displayTime)
            putExtra(AlarmScheduler.EXTRA_SOUND_RAW_RES_NAME, soundRawResName)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }

        if (repeatType == "once") {
            // A snooze fire — one-shot, does not repeat. Just clear its
            // bookkeeping; the original daily/weekly alarm this snooze came
            // from was untouched and is still scheduled separately.
            AlarmStore.remove(context, alarmId)
        } else {
            // Re-arm for the next occurrence so daily/weekly reminders keep firing.
            val entry = AlarmStore.AlarmEntry(
                alarmId = alarmId,
                reminderId = reminderId,
                title = title,
                dose = dose,
                displayTime = displayTime,
                hour = hour,
                minute = minute,
                repeatType = repeatType,
                weekday = weekday,
                soundRawResName = soundRawResName,
            )
            AlarmScheduler.rescheduleNext(context, entry)
        }
    }
}
