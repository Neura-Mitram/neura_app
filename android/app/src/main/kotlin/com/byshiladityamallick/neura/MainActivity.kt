package com.byshiladityamallick.neura

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.media.*
import android.speech.tts.TextToSpeech
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import okhttp3.*
import okio.ByteString
import java.util.*

class MainActivity : FlutterActivity() {
    private val WAKEWORD_CHANNEL = "neura/wakeword"
    private val TTS_CHANNEL = "neura/tts"
    private var methodChannel: MethodChannel? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var tts: TextToSpeech? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ✅ Cache engine for overlay + background access
        FlutterEngineCache.getInstance().put("main_engine", flutterEngine)

        // ✅ Wakeword + overlay service control
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WAKEWORD_CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startWakewordService" -> {
                    val intent = Intent(this, WakewordForegroundService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
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
                    wakeLock?.acquire(10 * 60 * 1000L /*10 minutes*/)
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

        // ✅ TTS stream + native fallback
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

        // ✅ Ask for battery optimization exemption
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val packageName = applicationContext.packageName
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                intent.data = Uri.parse("package:$packageName")
                startActivity(intent)
            }
        }
    }

    // ✅ ElevenLabs streaming playback
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

        if (player.state != AudioTrack.STATE_INITIALIZED) {
            return
        }

        client.newWebSocket(request, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                if (player.playState != AudioTrack.PLAYSTATE_PLAYING) {
                    player.play()
                }
                val audioData = bytes.toByteArray()
                player.write(audioData, 0, audioData.size)
            }
        })
    }

    // ✅ Native Android TTS fallback
    private fun speakTts(text: String) {
        if (tts == null) {
            tts = TextToSpeech(this) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    val result = tts?.setLanguage(Locale.US)
                    if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                        tts?.language = Locale.ENGLISH // fallback
                    }
                    tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "NEURA_TTS")
                }
            }
        } else {
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "NEURA_TTS")
        }
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
}
