package com.medisense.medisense_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
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
                triggerNativeSosWithDeepLink()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun triggerNativeSosWithDeepLink() {
        val ctx = context ?: return
        Log.d("SOS_DEBUG", "SosPlugin: triggerNativeSosWithDeepLink starting")

        // 1. Create a deep link Intent that opens the app's SOS screen
        val deepLinkIntent = Intent(Intent.ACTION_VIEW, Uri.parse("medisense://sos")).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            setPackage(ctx.packageName)
        }

        val pendingIntent = PendingIntent.getActivity(
            ctx, 0, deepLinkIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "sos_channel"

        // 2. Ensure high-importance channel exists
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "SOS Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Used to launch the SOS screen instantly, including over the lock screen"
                setBypassDnd(true)
                enableVibration(true)
            }
            nm.createNotificationChannel(channel)
        }

        // 3. Post high-priority full-screen notification
        // Note: CATEGORY_CALL is used to get "VIP" treatment for background launch
        val notification = NotificationCompat.Builder(ctx, channelId)
            .setSmallIcon(ctx.applicationInfo.icon)
            .setContentTitle("SOS Activated")
            .setContentText("Tap to open emergency dashboard")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setFullScreenIntent(pendingIntent, true) 
            .setAutoCancel(true)
            .setOngoing(false)
            .build()

        nm.notify(1001, notification)
        Log.d("SOS_DEBUG", "SosPlugin: Full-screen SOS notification posted with deep link")
        
        // backup direct wake up (might fail on Android 14 but good to try)
        try {
            ctx.startActivity(deepLinkIntent)
        } catch (e: Exception) {
            Log.e("SOS_DEBUG", "SosPlugin: direct startActivity failed (expected on background): ${e.message}")
        }
    }
}
