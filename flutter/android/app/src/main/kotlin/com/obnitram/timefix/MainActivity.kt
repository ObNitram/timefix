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
 * Shows the app over the lock screen only while a full-screen / alarm
 * reminder is really displayed, so that the rest of the calendar never
 * appears without unlocking.
 */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (isLiveRingIntent(intent)) setShowOnLock(true)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (isLiveRingIntent(intent)) setShowOnLock(true)
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

    private fun setShowOnLock(on: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(on)
            setTurnScreenOn(on)
        } else {
            @Suppress("DEPRECATION")
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (on) window.addFlags(flags) else window.clearFlags(flags)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "timefix/reminders")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Called when the ringing screen closes.
                    "leaveRing" -> {
                        setShowOnLock(false)
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
