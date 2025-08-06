package com.byshiladityamallick.neura

import android.content.Context
import android.content.Intent
import android.media.*
import android.net.Uri
import android.os.*
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.telephony.SmsManager
import android.util.Log
import android.widget.Toast
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import okhttp3.*
import org.json.JSONObject
import java.io.IOException
import java.util.*
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {
    // Constants
    private companion object {
        const val TAG = "MainActivity"
        const val WAKEWORD_CHANNEL = "neura/wakeword"
        const val TTS_CHANNEL = "neura/tts"
        const val SOS_SMS_CHANNEL = "sos.sms.native"
        const val SOS_LOGIC_CHANNEL = "sos.sosLogic"
        const val NUDGE_CHANNEL = "neura/native/nudge"
        const val PERMISSIONS_CHANNEL = "com.neura/permissions"
        const val BATTERY_CHANNEL = "com.neura/battery"
        const val PREFS_NAME = "FlutterSharedPreferences"
        const val SOS_DELAY_SCREEN_ON = 5000L
        const val SOS_DELAY_SCREEN_OFF = 8000L
    }

    // Services
    private var wakeLock: PowerManager.WakeLock? = null
    private var tts: TextToSpeech? = null
    private val ttsInitLock = Any()
    private val coroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val okHttpClient by lazy { createOkHttpClient() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FlutterEngineCache.getInstance().put("main_engine", flutterEngine)

        // Channel setup
        setupWakewordChannel(flutterEngine)
        setupTtsChannel(flutterEngine)
        setupSosSmsChannel(flutterEngine)
        setupSosLogicChannel(flutterEngine)
        setupNudgeChannel(flutterEngine)
        setupPermissionsChannel(flutterEngine)
        setupBatteryChannel(flutterEngine)
    }

    // Region: Channel Handlers
    private fun setupWakewordChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, WAKEWORD_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "startWakewordService" -> startServiceSafely<WakewordForegroundService>(result)
                    "startOverlayDotService" -> startServiceSafely<OverlayDotService>(result)
                    "stopOverlayDotService" -> stopServiceSafely<OverlayDotService>(result)
                    "acquireWakeLock" -> acquireWakeLock(result)
                    "releaseWakeLock" -> releaseWakeLock(result)
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun setupTtsChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, TTS_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "playTtsInBackground" -> call.argument<String>("url")?.let {
                        playTtsStream(it)
                        result.success(true)
                    } ?: result.error("NO_URL", "No URL provided", null)

                    "speakNativeTts" -> speakTts(
                        call.argument<String>("text") ?: "Sorry, I lost connection"
                    ).also { result.success(true) }

                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun setupSosSmsChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, SOS_SMS_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "sendSilentSms") {
                    val message = call.argument<String>("message") ?: "🚨 Emergency! I need help."
                    sendSilentSms(message, result)
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    private fun setupSosLogicChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, SOS_LOGIC_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "triggerSosFlow") {
                    triggerSosFlow(
                        engine,
                        call.argument<String>("message") ?: "Neura detected emergency keyword.",
                        call.argument<String>("location") ?: ""
                    )
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    private fun setupNudgeChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, NUDGE_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "showNudgeBubble") {
                    showNudgeBubble(
                        call.argument<String>("emoji") ?: "💡",
                        call.argument<String>("text") ?: "Take a moment",
                        call.argument<String>("lang") ?: "en"
                    )
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    private fun setupPermissionsChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, PERMISSIONS_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasUsageAccess" -> result.success(hasUsageAccess())
                    "openUsageAccess" -> openUsageAccessSettings().also { result.success(null) }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun setupBatteryChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, BATTERY_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "requestIgnoreBatteryOptimization") {
                    requestBatteryOptimizationIgnore()
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
        }
    }
    // End Region

    // Region: Service Management
    private inline fun <reified T> startServiceSafely(result: MethodChannel.Result) {
        try {
            val intent = Intent(this, T::class.java)
            ContextCompat.startForegroundService(this, intent)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start service", e)
            result.error("SERVICE_ERROR", e.message, null)
        }
    }

    private inline fun <reified T> stopServiceSafely(result: MethodChannel.Result) {
        try {
            val intent = Intent(this, T::class.java)
            stopService(intent)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop service", e)
            result.error("SERVICE_ERROR", e.message, null)
        }
    }
    // End Region

    // Region: WakeLock Management
    private fun acquireWakeLock(result: MethodChannel.Result) {
        try {
            if (wakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                    ?: throw IllegalStateException("PowerManager unavailable")
                wakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "neura::micLock"
                ).apply {
                    setReferenceCounted(false)
                }
            }
            wakeLock?.acquire(10 * 60 * 1000L)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "WakeLock acquisition failed", e)
            result.error("WAKE_LOCK_ERROR", e.message, null)
        }
    }

    private fun releaseWakeLock(result: MethodChannel.Result) {
        try {
            wakeLock?.release()
            wakeLock = null
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "WakeLock release failed", e)
            result.error("WAKE_LOCK_ERROR", e.message, null)
        }
    }
    // End Region

    // Region: TTS Handling
    private fun playTtsStream(url: String) {
        val bufferSize = AudioTrack.getMinBufferSize(
            22050,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )

        val player = AudioTrack(
            AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                .build(),
            AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(22050)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build(),
            bufferSize,
            AudioTrack.MODE_STREAM,
            AudioManager.AUDIO_SESSION_ID_GENERATE
        ).apply {
            if (state != AudioTrack.STATE_INITIALIZED) {
                release()
                return
            }
        }

        val request = Request.Builder().url(url).build()
        okHttpClient.newWebSocket(request, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                try {
                    if (player.playState != AudioTrack.PLAYSTATE_PLAYING) player.play()
                    player.write(bytes.toByteArray(), 0, bytes.size)
                } catch (e: Exception) {
                    Log.e(TAG, "AudioTrack write failed", e)
                    player.release()
                    webSocket.close(1000, "Audio error")
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                player.stop()
                player.release()
            }
        })
    }

    private fun speakTts(text: String) {
        synchronized(ttsInitLock) {
            if (tts == null) {
                tts = TextToSpeech(this) { status ->
                    if (status == TextToSpeech.SUCCESS) {
                        tts?.language = if (tts?.isLanguageAvailable(Locale.US) == TextToSpeech.LANG_AVAILABLE) {
                            Locale.US
                        } else {
                            Locale.ENGLISH
                        }
                        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "NEURA_TTS")
                    }
                }
            } else {
                tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "NEURA_TTS")
            }
        }
    }
    // End Region

    // Region: SOS Functionality
    private fun sendSilentSms(message: String, result: MethodChannel.Result) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val deviceId = prefs.getString("flutter.device_id", null)
        val token = prefs.getString("auth_token", null)

        if (deviceId != null && token != null) {
            openSmsAppForContacts(deviceId, token, message)
            result.success(true)
        } else {
            result.error("MISSING_CONTEXT", "Missing device ID or token", null)
        }
    }

    private fun triggerSosFlow(engine: FlutterEngine, message: String, location: String) {
        val isScreenOn = (getSystemService(Context.POWER_SERVICE) as? PowerManager)?.isInteractive ?: false

        Toast.makeText(this, "🔴 Danger detected. Sending SOS...", Toast.LENGTH_LONG).show()

        coroutineScope.launch {
            val delayTime = if (isScreenOn) SOS_DELAY_SCREEN_ON else SOS_DELAY_SCREEN_OFF
            delay(delayTime)
            openSosScreen(engine, message, location)
        }
    }

    private fun openSosScreen(engine: FlutterEngine, message: String, location: String) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "sos.screen.trigger").invokeMethod(
            "openSosScreen", mapOf(
                "message" to message,
                "location" to location,
                "autoSms" to true,
                "backgroundMic" to true,
                "proofLog" to true
            )
        )
    }

    private fun openSmsAppForContacts(deviceId: String, token: String, message: String) {
        val url = "https://byshiladityamallick-neura-smart-assistant.hf.space/safety/list-sos-contacts"
        val requestBody = RequestBody.create(
            "application/json".toMediaTypeOrNull(),
            """{ "device_id": "$deviceId" }"""
        )

        val request = Request.Builder()
            .url(url)
            .post(requestBody)
            .addHeader("Authorization", "Bearer $token")
            .build()

        okHttpClient.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.e(TAG, "SOS contacts fetch failed", e)
            }

            override fun onResponse(call: Call, response: Response) {
                response.body?.string()?.let { body ->
                    try {
                        JSONObject(body).getJSONArray("contacts").let { contacts ->
                            for (i in 0 until contacts.length()) {
                                contacts.getJSONObject(i).getString("phone").let { phone ->
                                    val intent = Intent(Intent.ACTION_SENDTO).apply {
                                        data = Uri.parse("smsto:$phone")
                                        putExtra("sms_body", message)
                                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                    }
                                    if (intent.resolveActivity(packageManager) != null) {
                                        startActivity(intent)
                                    }
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "SMS contact processing failed", e)
                    }
                }
            }
        })
    }

    private fun vibrateDevice(durationMs: Long) {
        try {
            (getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator)?.let { vibrator ->
                if (vibrator.hasVibrator()) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        vibrator.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
                    } else {
                        @Suppress("DEPRECATION")
                        vibrator.vibrate(durationMs)
                    }
                }
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "Vibration permission denied", e)
        }
    }
    // End Region

    // Region: Nudge System
    private fun showNudgeBubble(emoji: String, text: String, lang: String) {
        Intent("com.neura.NEW_NUDGE").apply {
            putExtra("emoji", emoji)
            putExtra("text", text)
            putExtra("lang", lang)
        }.also { sendBroadcast(it) }
    }
    // End Region

    // Region: Permissions
    private fun hasUsageAccess(): Boolean {
        if (Build.FINGERPRINT.contains("generic")) return true // Emulator bypass

        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
            val mode = appOps?.unsafeCheckOpNoThrow(
                "android:get_usage_stats",
                Process.myUid(),
                packageName
            ) ?: AppOpsManager.MODE_IGNORED
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            Log.e(TAG, "Usage access check failed", e)
            false
        }
    }

    private fun openUsageAccessSettings() {
        Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }.also { startActivity(it) }
    }
    // End Region

    // Region: Battery Optimization
    private fun requestBatteryOptimizationIgnore() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return

        (getSystemService(Context.POWER_SERVICE) as? PowerManager)?.let { pm ->
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }.also { startActivity(it) }
            }
        }
    }
    // End Region

    // Region: Utility Methods
    private fun createOkHttpClient(): OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        .build()
    // End Region

    override fun onPostResume() {
        super.onPostResume()
        pushChatSummariesToFlutter()
    }

    private fun pushChatSummariesToFlutter() {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getString("cached_summary_list", "[]")?.let { json ->
            FlutterEngineCache.getInstance().get("main_engine")?.let { engine ->
                MethodChannel(engine.dartExecutor.binaryMessenger, "neura/chat/summary")
                    .invokeMethod("pushChatSummaries", json)
            }
        }
    }

    override fun onDestroy() {
        coroutineScope.cancel("Activity destroyed")
        okHttpClient.dispatcher.executorService.shutdown()
        tts?.shutdown()
        wakeLock?.release()
        super.onDestroy()
    }
}
