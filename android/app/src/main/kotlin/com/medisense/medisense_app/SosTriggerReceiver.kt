package com.medisense.medisense_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat

class SosTriggerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("SOS_DEBUG", "SosTriggerReceiver: Broadcast received. Action: ${intent.action}")
        if (intent.action == "com.medisense.medisense_app.ACTION_SOS_TRIGGER") {
            launchSosNotification(context)
        }
    }

    private fun launchSosNotification(context: Context) {
        Log.d("SOS_DEBUG", "SosTriggerReceiver: Preparing full-screen notification")
        
        // 1. Create Deep Link intent for MainActivity
        val deepLinkIntent = Intent(Intent.ACTION_VIEW, Uri.parse("medisense://sos")).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            setPackage(context.packageName)
        }

        val pendingIntent = PendingIntent.getActivity(
            context, 0, deepLinkIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        // 2. Ensure channel exists
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "sos_channel_v7"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "SOS Emergency Alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Critical SOS notifications that open the app immediately"
                setBypassDnd(true)
                enableVibration(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(channel)
        }

        // 3. Post full-screen notification
        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle("CRITICAL SOS ACTIVATED")
            .setContentText("Opening SOS Dashboard...")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL) // Treat like an incoming call
            .setFullScreenIntent(pendingIntent, true) // Force immediate popup
            .setAutoCancel(true)
            .setOngoing(false)
            .build()

        nm.notify(911, notification)
        Log.d("SOS_DEBUG", "SosTriggerReceiver: Full-screen notification posted")
        
        // 4. Fallback: Try waking the app directly if unlocked
        try {
            context.startActivity(deepLinkIntent)
        } catch (e: Exception) {
            Log.e("SOS_DEBUG", "SosTriggerReceiver: Direct startActivity failed: ${e.message}")
        }
    }
}
