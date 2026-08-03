package com.medisense.medisense_app

import android.content.Context
import org.json.JSONObject

/**
 * Persists metadata for every native alarm currently scheduled, keyed by the
 * same integer alarm id used with [android.app.AlarmManager]/[android.app.PendingIntent].
 *
 * This is the single source of truth [BootReceiver] reads from to restore
 * every alarm after a device restart — AlarmManager entries do not survive
 * a reboot on their own, so without this store a restart would silently
 * drop every reminder alarm.
 *
 * Storage is plain SharedPreferences with one JSON string value per alarm
 * id; no extra dependency is required beyond `org.json`, which ships with
 * Android.
 */
object AlarmStore {
    private const val PREFS_NAME = "medisense_native_alarms"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** One entry per scheduled native alarm. */
    data class AlarmEntry(
        val alarmId: Int,
        val reminderId: String,
        val title: String,
        val dose: String,
        val displayTime: String,
        val hour: Int,
        val minute: Int,
        // "daily" repeats every day; "weekly" repeats on [weekday] only.
        val repeatType: String,
        val weekday: Int, // 1 (Mon) .. 7 (Sun), only meaningful for "weekly"
        val soundRawResName: String = "",
    ) {
        fun toJson(): String = JSONObject().apply {
            put("alarmId", alarmId)
            put("reminderId", reminderId)
            put("title", title)
            put("dose", dose)
            put("displayTime", displayTime)
            put("hour", hour)
            put("minute", minute)
            put("repeatType", repeatType)
            put("weekday", weekday)
            put("soundRawResName", soundRawResName)
        }.toString()

        companion object {
            fun fromJson(json: String): AlarmEntry {
                val o = JSONObject(json)
                return AlarmEntry(
                    alarmId = o.getInt("alarmId"),
                    reminderId = o.getString("reminderId"),
                    title = o.getString("title"),
                    dose = o.optString("dose", ""),
                    displayTime = o.optString("displayTime", ""),
                    hour = o.getInt("hour"),
                    minute = o.getInt("minute"),
                    repeatType = o.getString("repeatType"),
                    weekday = o.optInt("weekday", 0),
                    soundRawResName = o.optString("soundRawResName", ""),
                )
            }
        }
    }

    fun save(context: Context, entry: AlarmEntry) {
        prefs(context).edit()
            .putString(keyFor(entry.alarmId), entry.toJson())
            .apply()
    }

    fun remove(context: Context, alarmId: Int) {
        prefs(context).edit().remove(keyFor(alarmId)).apply()
    }

    /** Removes every stored alarm belonging to [reminderId]. */
    fun removeAllForReminder(context: Context, reminderId: String) {
        val all = all(context).filter { it.reminderId == reminderId }
        val editor = prefs(context).edit()
        for (entry in all) editor.remove(keyFor(entry.alarmId))
        editor.apply()
    }

    fun all(context: Context): List<AlarmEntry> {
        val p = prefs(context)
        return p.all.values
            .mapNotNull { it as? String }
            .mapNotNull { runCatching { AlarmEntry.fromJson(it) }.getOrNull() }
    }

    private fun keyFor(alarmId: Int) = "alarm_$alarmId"
}
