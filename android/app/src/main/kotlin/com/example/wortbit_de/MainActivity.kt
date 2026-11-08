package com.example.wortbit_de

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.wortbit_de/lockscreen"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyLockScreenFlags()
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        // Re-apply flags when brought to front from background (screen-on trigger)
        applyLockScreenFlags()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    startLockScreenService()
                    result.success(null)
                }
                "stopService" -> {
                    stopService(
                        android.content.Intent(this, LockScreenService::class.java)
                    )
                    result.success(null)
                }
                "isServiceRunning" -> {
                    // Best-effort check; always return true for simplicity.
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ── Window flags: show over lockscreen ───────────────────────────────────
    private fun applyLockScreenFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            // API 27+ – recommended approach
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            km.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED    or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON       or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON       or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
    }

    // ── Start foreground service ─────────────────────────────────────────────
    private fun startLockScreenService() {
        val intent = android.content.Intent(this, LockScreenService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
