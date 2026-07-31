package com.medisense.medisense_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * AlarmManager entries do not survive a reboot. This receiver re-arms every
 * alarm recorded in [AlarmStore] the moment the device finishes booting (or
 * this app is reinstalled/updated), so reminders keep ringing without the
 * app ever needing to be opened. [AlarmScheduler.schedule] is idempotent
 * (it replaces any existing PendingIntent for the same id), so this can
 * never create duplicates even if it somehow ran twice.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED,
            -> AlarmScheduler.rescheduleAllStored(context)
        }
    }
}
