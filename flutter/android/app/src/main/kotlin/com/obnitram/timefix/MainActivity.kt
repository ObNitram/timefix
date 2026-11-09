package com.obnitram.timefix

import android.app.KeyguardManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Full-screen / alarm reminders over the lock screen.
 *
 * When a ringing reminder opens the activity, it is shown over the keyguard
 * and turns the screen on right away (an activity hidden by the keyguard is
 * stopped, and Flutter draws no frame while stopped). While the phone is
 * locked, an opaque cover in the ringing screen's colour hides the calendar
 * until Dart reports that the ringing screen is displayed ("enterRing").
 * Without that report, the activity leaves the lock screen after a delay.
 */
class MainActivity : FlutterActivity() {
    private var ringPending = false
    private var cover: View? = null
    private val handler = Handler(Looper.getMainLooper())
    private val ringTimeout = Runnable { endRing() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        onRingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        onRingIntent(intent)
    }

    override fun onDestroy() {
        handler.removeCallbacks(ringTimeout)
        super.onDestroy()
    }

    private fun onRingIntent(i: Intent?) {
        if (!isLiveRingIntent(i)) return
        ringPending = true
        setShowWhenLockedCompat(true)
        setTurnScreenOnCompat(true)
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (keyguard.isKeyguardLocked) showCover()
        handler.removeCallbacks(ringTimeout)
        handler.postDelayed(ringTimeout, RING_START_TIMEOUT_MS)
    }

    /**
     * flutter_local_notifications opens the app with the action
     * "SELECT_NOTIFICATION" and the extras "notificationId" / "payload".
     * The activity is exported, so the intent is trusted only if the matching
     * ringing notification is currently shown.
     */
    private fun isLiveRingIntent(i: Intent?): Boolean {
        if (i?.action != "SELECT_NOTIFICATION") return false
        if (i.getStringExtra("payload")?.startsWith(RING_PREFIX) != true) return false
        val id = i.getIntExtra("notificationId", Int.MIN_VALUE)
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return nm.activeNotifications.any { sbn ->
            sbn.id == id && sbn.notification.channelId?.startsWith(RING_CHANNEL_PREFIX) == true
        }
    }

    /** Opaque view above the Flutter view; it also swallows touches. */
    private fun showCover() {
        if (cover != null) return
        val v = View(this).apply {
            setBackgroundColor(RING_BACKGROUND)
            isClickable = true
            isFocusable = true
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }
        addContentView(v, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        cover = v
    }

    private fun removeCover() {
        val v = cover ?: return
        cover = null
        (v.parent as? ViewGroup)?.removeView(v)
    }

    /** Leaves the lock screen (ringing screen closed, or never displayed). */
    private fun endRing() {
        handler.removeCallbacks(ringTimeout)
        ringPending = false
        removeCover()
        setShowWhenLockedCompat(false)
        setTurnScreenOnCompat(false)
    }

    private fun setShowWhenLockedCompat(on: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(on)
        } else {
            @Suppress("DEPRECATION")
            val flag = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
            if (on) window.addFlags(flag) else window.clearFlags(flag)
        }
    }

    private fun setTurnScreenOnCompat(on: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setTurnScreenOn(on)
        } else {
            @Suppress("DEPRECATION")
            val flag = WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (on) window.addFlags(flag) else window.clearFlags(flag)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "timefix/reminders")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // The ringing screen is displayed: uncover it, once its
                    // first frame has reached the screen.
                    "enterRing" -> {
                        if (ringPending) {
                            handler.removeCallbacks(ringTimeout)
                            val v = cover
                            if (v != null) v.postDelayed({ if (cover === v) removeCover() }, UNCOVER_DELAY_MS)
                        }
                        result.success(null)
                    }
                    // The last ringing screen closed.
                    "leaveRing" -> {
                        endRing()
                        if (call.argument<Boolean>("background") == true) moveTaskToBack(true)
                        result.success(null)
                    }
                    // Pending alarms of flutter_local_notifications still
                    // exist (they are dropped when the app is force-stopped).
                    "areScheduled" -> {
                        val ids = call.argument<List<Int>>("ids") ?: emptyList()
                        val receiver = Intent().setClassName(this, SCHEDULED_RECEIVER)
                        val flags = PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
                        result.success(ids.all { PendingIntent.getBroadcast(this, it, receiver, flags) != null })
                    }
                    "canUseFullScreenIntent" -> result.success(
                        Build.VERSION.SDK_INT < 34 ||
                            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                                .canUseFullScreenIntent()
                    )
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        const val RING_PREFIX = "ring:"
        const val RING_CHANNEL_PREFIX = "timefix_ring_"
        const val SCHEDULED_RECEIVER =
            "com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"
        /** Background colour of the Dart ringing screen (0xFF0B1F3A). */
        const val RING_BACKGROUND = 0xFF0B1F3A.toInt()
        /** Cold start included: DB, notifications plugin, first frame. */
        const val RING_START_TIMEOUT_MS = 15_000L
        const val UNCOVER_DELAY_MS = 150L
    }
}
