package com.example.wortbit_de

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {

    private val LOCKSCREEN_CHANNEL = "com.example.wortbit_de/lockscreen"
    private val TTS_CHANNEL = "com.example.wortbit_de/tts"

    private var tts: TextToSpeech? = null
    private var isTtsReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyLockScreenFlags()
        tts = TextToSpeech(this, this)
    }

    override fun onResume() {
        super.onResume()
        // Đảm bảo luôn kích hoạt cờ hiển thị trên lockscreen mỗi khi Activity active
        applyLockScreenFlags()
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            val result = tts?.setLanguage(Locale.GERMAN)
            tts?.setSpeechRate(0.85f)
            isTtsReady = result != TextToSpeech.LANG_MISSING_DATA && result != TextToSpeech.LANG_NOT_SUPPORTED
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyLockScreenFlags()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Lockscreen controls
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCKSCREEN_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    startLockScreenService()
                    result.success(null)
                }
                "stopService" -> {
                    stopService(android.content.Intent(this, LockScreenService::class.java))
                    result.success(null)
                }
                "dismiss" -> {
                    // Đóng giao diện Lockscreen để người dùng vào màn hình chính điện thoại
                    moveTaskToBack(true)
                    result.success(null)
                }
                "isServiceRunning" -> result.success(true)
                else -> result.notImplemented()
            }
        }

        // Native TTS
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TTS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> result.success(isTtsReady)
                "speak" -> {
                    val text = call.argument<String>("text")
                    if (isTtsReady && !text.isNullOrEmpty()) {
                        tts?.stop()
                        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "wortbit_tts_${System.currentTimeMillis()}")
                    }
                    result.success(null)
                }
                "stop" -> {
                    tts?.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun applyLockScreenFlags() {
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        km.requestDismissKeyguard(this, null)
    }

    private fun startLockScreenService() {
        val intent = android.content.Intent(this, LockScreenService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        super.onDestroy()
    }
}
