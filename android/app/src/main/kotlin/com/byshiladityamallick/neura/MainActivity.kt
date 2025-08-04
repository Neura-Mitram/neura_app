package com.byshiladityamallick.neura

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.media.*
import android.speech.tts.TextToSpeech
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import android.widget.Toast
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okio.ByteString
import java.util.*
import org.json.JSONObject
import java.io.IOException
import android.app.AppOpsManager
import android.content.pm.ApplicationInfo


class MainActivity : FlutterActivity() {
    private val WAKEWORD_CHANNEL = "neura/wakeword"
    private val TTS_CHANNEL = "neura/tts"
    private var methodChannel: MethodChannel? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var tts: TextToSpeech? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ✅ Cache engine
        FlutterEngineCache.getInstance().put("main_engine", flutterEngine)

        // ✅ Wakeword + overlay control
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WAKEWORD_CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startWakewordService" -> {
                    val intent = Intent(this, WakewordForegroundService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent)
                    else startService(intent)
                    result.success(true)
                }
                "startOverlayDotService" -> {
                    val intent = Intent(this, OverlayDotService::class.java)
                    startService(intent)
                    result.success(true)
                }
                "stopOverlayDotService" -> {
                    val intent = Intent(this, OverlayDotService::class.java)
                    stopService(intent)
                    result.success(true)
                }
                "acquireWakeLock" -> {
                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                    if (wakeLock == null) {
                        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "neura::micLock")
                        wakeLock?.setReferenceCounted(false)
                    }
                    wakeLock?.acquire(10 * 60 * 1000L)
                    result.success(true)
                }
                "releaseWakeLock" -> {
                    wakeLock?.release()
                    wakeLock = null
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // ✅ Native TTS & ElevenLabs fallback
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TTS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playTtsInBackground" -> {
                        val url = call.argument<String>("url")
                        if (url != null) {
                            playTtsStream(url)
                            result.success(true)
                        } else {
                            result.error("NO_URL", "No URL provided", null)
                        }
                    }

                    "speakNativeTts" -> {
                        val text = call.argument<String>("text") ?: "Sorry, I lost connection"
                        speakTts(text)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }

        // ✅ Native Silent SMS Sender
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sos.sms.native")
            .setMethodCallHandler { call, result ->
                if (call.method == "sendSilentSms") {
                    val message = call.argument<String>("message") ?: "🚨 Emergency! I need help."
                    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    val deviceId = prefs.getString("flutter.device_id", null)
                    val token = prefs.getString("auth_token", null)

                    if (deviceId != null && token != null) {
                        openSmsAppForContacts(deviceId, token, message)
                        result.success(true)
                    } else {
                        result.error("MISSING_CONTEXT", "Missing device ID or token", null)
                    }
                } else {
                    result.notImplemented()
                }
            }


        // ✅ Smart SOS Escalation Logic
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sos.sosLogic")
            .setMethodCallHandler { call, result ->
                if (call.method == "triggerSosFlow") {
                    val message = call.argument<String>("message") ?: "Neura detected emergency keyword."
                    val location = call.argument<String>("location") ?: ""

                    val powerManager = getSystemService(POWER_SERVICE) as PowerManager
                    val isScreenOn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT_WATCH) {
                        powerManager.isInteractive
                    } else {
                        powerManager.isScreenOn
                    }

                    if (isScreenOn) {
                        // ✅ Show toast + wait 5s — let user cancel via dot
                        Toast.makeText(this, "🔴 Danger detected. Sending SOS in 5s…", Toast.LENGTH_LONG).show()

                        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        val deviceId = prefs.getString("flutter.device_id", null)
                        val token = prefs.getString("auth_token", null)
                        if (deviceId != null && token != null) {
                            openSmsAppForContacts(deviceId, token, message)
                        }

                        Handler(Looper.getMainLooper()).postDelayed({
                            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sos.screen.trigger")
                                .invokeMethod("openSosScreen", mapOf(
                                    "message" to message,
                                    "location" to location,
                                    "autoSms" to true,
                                    "backgroundMic" to true,
                                    "proofLog" to true
                                ))
                        }, 5000)
                    } else {
                        // 📴 Screen OFF — whisper + vibration
                        val vibrator = getSystemService(VIBRATOR_SERVICE) as Vibrator
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            vibrator.vibrate(VibrationEffect.createOneShot(300, VibrationEffect.DEFAULT_AMPLITUDE))
                        } else {
                            vibrator.vibrate(300)
                        }

                        speakTts("I heard something worrying. If you need help, stay still.")

                        Handler(Looper.getMainLooper()).postDelayed({
                            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sos.screen.trigger")
                                .invokeMethod("openSosScreen", mapOf(
                                    "message" to message,
                                    "location" to location,
                                    "autoSms" to true,
                                    "backgroundMic" to true,
                                    "proofLog" to true
                                ))
                        }, 8000)
                    }

                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }

        // ✅ Smart Nudge Logic
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "neura/native/nudge")
            .setMethodCallHandler { call, result ->
                if (call.method == "showNudgeBubble") {
                    val emoji = call.argument<String>("emoji") ?: "💡"
                    val text = call.argument<String>("text") ?: "Take a moment"
                    val lang = call.argument<String>("lang") ?: "en"

                    val intent = Intent("com.neura.NEW_NUDGE").apply {
                        putExtra("emoji", emoji)
                        putExtra("text", text)
                        putExtra("lang", lang)
                    }
                    sendBroadcast(intent)
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }

        // ✅ Smart Permissions For events help
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.neura/permissions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasUsageAccess" -> result.success(hasUsageAccess())
                    "openUsageAccess" -> {
                        openUsageAccessSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }


        // ✅ Battery Optimization Request (moved here safely)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.neura/battery")
            .setMethodCallHandler { call, result ->
                if (call.method == "requestIgnoreBatteryOptimization") {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val packageName = applicationContext.packageName
                        val pm = getSystemService(POWER_SERVICE) as PowerManager
                        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                            intent.data = Uri.parse("package:$packageName")
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                    }
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }



        
    }

    private fun playTtsStream(url: String) {
        val client = OkHttpClient()
        val request = Request.Builder().url(url).build()

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
        )

        if (player.state != AudioTrack.STATE_INITIALIZED) return

        client.newWebSocket(request, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                if (player.playState != AudioTrack.PLAYSTATE_PLAYING) {
                    player.play()
                }
                player.write(bytes.toByteArray(), 0, bytes.size)
            }
        })
    }

    private fun speakTts(text: String) {
        if (tts == null) {
            tts = TextToSpeech(this) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    val result = tts?.setLanguage(Locale.US)
                    if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                        tts?.language = Locale.ENGLISH
                    }
                    tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "NEURA_TTS")
                }
            }
        } else {
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "NEURA_TTS")
        }
    }

    private fun openSmsAppForContacts(deviceId: String, token: String, message: String = "🚨 Emergency! I need help.") {
        val url = "https://byshiladityamallick-neura-smart-assistant.hf.space/safety/list-sos-contacts"
        val client = OkHttpClient()

        val requestBody = RequestBody.create(
            "application/json".toMediaTypeOrNull(),
            """{ "device_id": "$deviceId" }"""
        )

        val request = Request.Builder()
            .url(url)
            .post(requestBody)
            .addHeader("Authorization", "Bearer $token")
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                e.printStackTrace()
            }

            override fun onResponse(call: Call, response: Response) {
                response.body?.string()?.let { responseBody ->
                    try {
                        val json = JSONObject(responseBody)
                        val contacts = json.getJSONArray("contacts")

                        for (i in 0 until contacts.length()) {
                            val contact = contacts.getJSONObject(i)
                            val phone = contact.getString("phone")

                            val uri = Uri.parse("smsto:$phone")
                            val intent = Intent(Intent.ACTION_SENDTO, uri).apply {
                                putExtra("sms_body", message)
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }

                            if (intent.resolveActivity(packageManager) != null) {
                                startActivity(intent)
                            }
                        }
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            }
        })
    }

    private fun pushChatSummariesToFlutter() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val summaryJson = prefs.getString("cached_summary_list", "[]") ?: "[]"

        val engine = FlutterEngineCache.getInstance().get("main_engine")
        engine?.let {
            val channel = MethodChannel(it.dartExecutor.binaryMessenger, "neura/chat/summary")
            channel.invokeMethod("pushChatSummaries", summaryJson)

            // Optional: clear the list after sending
            prefs.edit().remove("cached_summary_list").apply()
        }
    }

    private fun hasUsageAccess(): Boolean {
        // 🧪 Emulator bypass (optional)
        if (Build.FINGERPRINT.contains("generic")) return true

        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager

            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                // Android 11+ recommended way
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )
            } else {
                // Legacy but still safe fallback
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )
            }

            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun openUsageAccessSettings() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    override fun onPostResume() {
        super.onPostResume()
        // ✅ Send cached summaries to Flutter on app open
        pushChatSummariesToFlutter() // UI is ready now
    }
    

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
}
