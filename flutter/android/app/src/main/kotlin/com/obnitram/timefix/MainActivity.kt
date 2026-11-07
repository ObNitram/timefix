package com.obnitram.timefix

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Full-screen / alarm reminders over the lock screen.
 *
 * When a ringing reminder opens the activity, the screen is turned on at
 * once, but the app is shown over the keyguard only after Dart reports that
 * the ringing screen is displayed ("enterRing"), so that the calendar itself
 * never appears without unlocking.
 */
class MainActivity : FlutterActivity() {
    private var ringPending = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        onRingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        onRingIntent(intent)
    }

    private fun onRingIntent(i: Intent?) {
        if (!isLiveRingIntent(i)) return
        ringPending = true
        setTurnScreenOnCompat(true)
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
                    // The ringing screen is displayed: show it over the keyguard.
                    "enterRing" -> {
                        if (ringPending) setShowWhenLockedCompat(true)
                        result.success(null)
                    }
                    // The ringing screen closed.
                    "leaveRing" -> {
                        ringPending = false
                        setShowWhenLockedCompat(false)
                        setTurnScreenOnCompat(false)
                        if (call.argument<Boolean>("background") == true) moveTaskToBack(true)
                        result.success(null)
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
    }
}
