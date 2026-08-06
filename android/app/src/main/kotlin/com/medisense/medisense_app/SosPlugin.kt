package com.medisense.medisense_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class SosPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d("SOS_DEBUG", "SosPlugin: onAttachedToEngine")
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "medisense_native_channel")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d("SOS_DEBUG", "SosPlugin: onDetachedFromEngine")
        channel.setMethodCallHandler(null)
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d("SOS_DEBUG", "SosPlugin: onMethodCall: ${call.method}")
        when (call.method) {
            "triggerSosNow" -> {
                triggerNativeSos()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun triggerNativeSos() {
        val ctx = context ?: return
        Log.d("SOS_DEBUG", "SosPlugin: triggerNativeSos entry")

        val intent = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("action", "OPEN_SOS")
        }

        if (intent == null) {
            Log.e("SOS_DEBUG", "SosPlugin: launch intent is null")
            return
        }

        val pendingIntent = PendingIntent.getActivity(
            ctx, 911, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "sos_emergency_channel_v4"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "SOS Emergency Alert", NotificationManager.IMPORTANCE_HIGH).apply {
                setBypassDnd(true)
                enableVibration(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(ctx, channelId)
            .setSmallIcon(ctx.applicationInfo.icon)
            .setContentTitle("CRITICAL SOS ALERT")
            .setContentText("Emergency Dashboard is activating...")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(pendingIntent, true)
            .setAutoCancel(true)
            .setOngoing(false)
            .build()

        Log.d("SOS_DEBUG", "SosPlugin: posting notification")
        nm.notify(911, notification)
        
        try {
            ctx.startActivity(intent)
        } catch (e: Exception) {
            Log.e("SOS_DEBUG", "SosPlugin: startActivity failed: ${e.message}")
        }
    }
}
