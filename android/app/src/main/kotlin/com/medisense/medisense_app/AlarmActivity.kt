package com.medisense.medisense_app

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import com.medisense.medisense_app.R
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class AlarmActivity : Activity() {

    private var currentTimeHandler: Handler? = null
    private var pulseAnimatorOuter: ValueAnimator? = null
    private var pulseAnimatorInner: ValueAnimator? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Move window flags to the VERY TOP, before super.onCreate
        showOverLockScreen()
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_alarm)

        applyIntentExtras(intent)
        startClock()
        startPulse()

        findViewById<Button>(R.id.btnStop).setOnClickListener {
            sendServiceAction(AlarmRingingService.ACTION_STOP)
            finishAndRemoveTask()
        }
        findViewById<Button>(R.id.btnSnooze).setOnClickListener {
            sendServiceAction(AlarmRingingService.ACTION_SNOOZE)
            finishAndRemoveTask()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyIntentExtras(intent)
    }

    private fun applyIntentExtras(intent: Intent) {
        val title = intent.getStringExtra(AlarmScheduler.EXTRA_TITLE) ?: "Medicine Reminder"
        val dose = intent.getStringExtra(AlarmScheduler.EXTRA_DOSE) ?: ""
        val displayTime = intent.getStringExtra(AlarmScheduler.EXTRA_DISPLAY_TIME) ?: ""

        findViewById<TextView>(R.id.tvTitle).text = title
        findViewById<TextView>(R.id.tvDose).text = dose
        findViewById<TextView>(R.id.tvReminderTime).text =
            if (displayTime.isBlank()) "Medicine time" else "Scheduled for $displayTime"
    }

    private fun showOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        // Ensure screen brightness and instant pop-up
        window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
    }

    private fun startClock() {
        val tvCurrentTime = findViewById<TextView>(R.id.tvCurrentTime)
        val format = SimpleDateFormat("h:mm a", Locale.getDefault())
        currentTimeHandler = Handler(Looper.getMainLooper())
        val tick = object : Runnable {
            override fun run() {
                tvCurrentTime.text = format.format(Date())
                currentTimeHandler?.postDelayed(this, 1000)
            }
        }
        tick.run()
    }

    private fun startPulse() {
        val outer = findViewById<android.view.View>(R.id.pulseOuter)
        val inner = findViewById<android.view.View>(R.id.pulseInner)
        pulseAnimatorOuter = pulseAnimator(outer, 1300)
        pulseAnimatorInner = pulseAnimator(inner, 1300).apply { startDelay = 300 }
    }

    private fun pulseAnimator(target: android.view.View, duration: Long): ValueAnimator {
        val animator = ObjectAnimator.ofFloat(target, "scaleX", 0.7f, 1.15f).apply {
            this.duration = duration
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
        }
        animator.addUpdateListener {
            val v = it.animatedValue as Float
            target.scaleY = v
            target.alpha = 1.4f - v
        }
        animator.start()
        return animator
    }

    private fun sendServiceAction(action: String) {
        val intent = Intent(this, AlarmRingingService::class.java).apply { this.action = action }
        startService(intent)
    }

    override fun onDestroy() {
        currentTimeHandler?.removeCallbacksAndMessages(null)
        pulseAnimatorOuter?.cancel()
        pulseAnimatorInner?.cancel()
        super.onDestroy()
    }

    override fun onBackPressed() {}
}
