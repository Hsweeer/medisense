package com.medisense.medisense_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar

/**
 * Arms/disarms the native [AlarmManager] entries that back the full-screen
 * ringing alarm. Kept separate from [AlarmStore] (bookkeeping) and
 * [AlarmReceiver] (what happens when an alarm fires) so each file has one
 * job.
 *
 * IDs: every reminder gets a stable base id derived from its Firestore
 * document id (`reminderId.hashCode()`, masked positive). A "daily" alarm
 * uses that id directly; a "weekly" alarm adds the ISO weekday (1..7) so
 * each selected day gets its own distinct, stable id — matching the
 * pattern already used on the Dart side for flutter_local_notifications,
 * just in a separate id namespace (different PendingIntent target class),
 * so the two systems can never collide.
 */
object AlarmScheduler {

    const val EXTRA_ALARM_ID = "extra_alarm_id"
    const val EXTRA_REMINDER_ID = "extra_reminder_id"
    const val EXTRA_TITLE = "extra_title"
    const val EXTRA_DOSE = "extra_dose"
    const val EXTRA_DISPLAY_TIME = "extra_display_time"
    const val EXTRA_HOUR = "extra_hour"
    const val EXTRA_MINUTE = "extra_minute"
    const val EXTRA_REPEAT_TYPE = "extra_repeat_type"
    const val EXTRA_WEEKDAY = "extra_weekday"

    /** Reserved sub-id (see [idFor]) for a one-off snooze fire. */
    const val SNOOZE_SUB_ID = 8

    fun baseIdFor(reminderId: String): Int = (reminderId.hashCode() and 0x7FFFFFFF) % 100_000

    /**
     * Every reminder occupies ids `base*10 + 0` (daily / no weekday) through
     * `base*10 + 7` (Sunday), with `base*10 + 8` reserved for a snooze
     * one-shot — so a snooze can never collide with, or overwrite the
     * stored metadata of, the recurring alarm it came from.
     */
    fun idFor(reminderId: String, weekday: Int?): Int {
        val base = baseIdFor(reminderId)
        return base * 10 + (weekday ?: 0)
    }

    fun snoozeIdFor(reminderId: String): Int = baseIdFor(reminderId) * 10 + SNOOZE_SUB_ID

    /** Schedules (or replaces) one alarm and records it in [AlarmStore]. */
    fun schedule(context: Context, entry: AlarmStore.AlarmEntry) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val triggerAt = nextTriggerMillis(entry.hour, entry.minute, entry.weekday.takeIf { entry.repeatType == "weekly" })

        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra(EXTRA_ALARM_ID, entry.alarmId)
            putExtra(EXTRA_REMINDER_ID, entry.reminderId)
            putExtra(EXTRA_TITLE, entry.title)
            putExtra(EXTRA_DOSE, entry.dose)
            putExtra(EXTRA_DISPLAY_TIME, entry.displayTime)
            putExtra(EXTRA_HOUR, entry.hour)
            putExtra(EXTRA_MINUTE, entry.minute)
            putExtra(EXTRA_REPEAT_TYPE, entry.repeatType)
            putExtra(EXTRA_WEEKDAY, entry.weekday)
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            entry.alarmId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        armExact(am, triggerAt, pendingIntent)
        AlarmStore.save(context, entry)
    }

    /** Re-arms a single already-fired alarm for its next occurrence. */
    fun rescheduleNext(context: Context, entry: AlarmStore.AlarmEntry) {
        schedule(context, entry)
    }

    fun cancel(context: Context, alarmId: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            alarmId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        am.cancel(pendingIntent)
        pendingIntent.cancel()
        AlarmStore.remove(context, alarmId)
    }

    /** Cancels every native alarm (daily/weekday slots 0-7 + the snooze slot) for [reminderId]. */
    fun cancelAllForReminder(context: Context, reminderId: String) {
        val base = baseIdFor(reminderId)
        for (sub in 0..SNOOZE_SUB_ID) cancel(context, base * 10 + sub)
        AlarmStore.removeAllForReminder(context, reminderId)
    }

    fun cancelAllStored(context: Context) {
        for (entry in AlarmStore.all(context)) cancel(context, entry.alarmId)
    }

    /** Re-arms every alarm currently recorded in [AlarmStore] — used after a reboot. */
    fun rescheduleAllStored(context: Context) {
        for (entry in AlarmStore.all(context)) schedule(context, entry)
    }

    private fun armExact(am: AlarmManager, triggerAt: Long, pendingIntent: PendingIntent) {
        val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()
        if (canExact) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            }
        } else {
            // Exact-alarm permission not granted — fall back to a best-effort
            // inexact alarm rather than silently scheduling nothing.
            am.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        }
    }

    /**
     * Next epoch millis at [hour]:[minute]. If [weekday] is null, this is
     * simply the next occurrence of that time (today if still upcoming,
     * otherwise tomorrow) — i.e. a daily repeat. If [weekday] is set
     * (1=Mon..7=Sun), returns the next occurrence of that time on that
     * specific weekday.
     */
    private fun nextTriggerMillis(hour: Int, minute: Int, weekday: Int?): Long {
        val cal = Calendar.getInstance()
        val now = cal.timeInMillis
        cal.set(Calendar.HOUR_OF_DAY, hour)
        cal.set(Calendar.MINUTE, minute)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)

        if (weekday != null) {
            // Calendar.DAY_OF_WEEK: Sunday=1..Saturday=7. Our weekday is ISO: Monday=1..Sunday=7.
            val calendarDow = if (weekday == 7) Calendar.SUNDAY else weekday + 1
            while (cal.get(Calendar.DAY_OF_WEEK) != calendarDow || cal.timeInMillis <= now) {
                cal.add(Calendar.DAY_OF_MONTH, 1)
            }
        } else {
            if (cal.timeInMillis <= now) cal.add(Calendar.DAY_OF_MONTH, 1)
        }
        return cal.timeInMillis
    }
}
