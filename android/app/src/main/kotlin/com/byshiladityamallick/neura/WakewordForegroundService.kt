package com.byshiladityamallick.neura

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.*
import android.os.*
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import okhttp3.*
import okio.ByteString
import org.tensorflow.lite.Interpreter
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import java.net.URLEncoder

class WakewordForegroundService : Service() {
    private var interpreter: Interpreter? = null
    private var isListening = true
    private val coroutineScope = CoroutineScope(Dispatchers.IO)
    private lateinit var wakeLock: PowerManager.WakeLock
    private var lastTriggeredAt: Long = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()

        // ✅ Acquire WakeLock for stability
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "neura::WakeLock")
        wakeLock.acquire(10 * 60 * 1000L)

        val notification = NotificationCompat.Builder(this, "wakeword_channel")
            .setContentTitle("Neura is listening")
            .setContentText("Your assistant is running in background.")
            .setSmallIcon(R.drawable.ic_dot_blue)
            .build()
        startForeground(101, notification)

        coroutineScope.launch {
            runInferenceLoop()
        }
    }

    private suspend fun runInferenceLoop() {
        val modelFile = File(filesDir, "wakeword_model.tflite")
        if (!modelFile.exists()) {
            stopSelf()
            return
        }

        interpreter = Interpreter(modelFile)

        val sampleRate = 16000
        val bufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )

        if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            stopSelf()
            return
        }

        val record = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize
        )

        val inputSize = 16000
        val audioBuffer = ShortArray(inputSize)
        val inputBuffer = ByteBuffer.allocateDirect(inputSize * 2).order(ByteOrder.nativeOrder())
        val outputBuffer = ByteBuffer.allocateDirect(4).order(ByteOrder.nativeOrder())

        record.startRecording()

        while (isListening && !Thread.currentThread().isInterrupted) {
            val read = record.read(audioBuffer, 0, inputSize)
            if (read > 0) {
                inputBuffer.clear()
                for (i in 0 until read) inputBuffer.putShort(audioBuffer[i])
                outputBuffer.clear()
                interpreter?.run(inputBuffer, outputBuffer)

                outputBuffer.rewind()
                val score = outputBuffer.float

                val now = System.currentTimeMillis()
                if (score > 0.8f && now - lastTriggeredAt > 4000) {
                    lastTriggeredAt = now
                    vibrateOnTrigger()
                    playWelcomeSoundFromBackend()
                    try {
                        startService(Intent(this, OverlayDotService::class.java))
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }

                    val intent = Intent("com.neura.WAKEWORD_TRIGGERED")
                    sendBroadcast(intent)
                    break
                }
            }
        }

        record.stop()
        record.release()
        stopSelf()
    }

    private fun vibrateOnTrigger() {
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(100, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            vibrator.vibrate(100)
        }
    }

    private fun playWelcomeSoundFromBackend() {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val voicePref = prefs.getString("flutter.voice", "male") ?: "male"
            val langPref = prefs.getString("flutter.preferred_lang", "en") ?: "en"
            val voiceId = if (voicePref == "female") "onwK4e9ZLuTAKqWW03F9" else "EXAVITQu4vr4xnSDxMaL"

            val encodedText = URLEncoder.encode("Hi, I'm listening", "UTF-8")
            val ttsUrl = "wss://byshiladityamallick-neura-smart-assistant.hf.space/ws/stream/elevenlabs?text=$encodedText&voice_id=$voiceId&lang=$langPref"
            val client = OkHttpClient()
            val request = Request.Builder().url(ttsUrl).build()

            val minBufferSize = AudioTrack.getMinBufferSize(
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
                minBufferSize,
                AudioTrack.MODE_STREAM,
                AudioManager.AUDIO_SESSION_ID_GENERATE
            )

            client.newWebSocket(request, object : WebSocketListener() {
                var isPlaying = false

                override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                    player.write(bytes.toByteArray(), 0, bytes.size)
                    if (!isPlaying) {
                        player.play()
                        isPlaying = true
                    }
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    if (isPlaying) {
                        player.stop()
                        player.release()
                    }
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    t.printStackTrace()
                    if (isPlaying) {
                        player.stop()
                        player.release()
                    }
                }
            })

        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "wakeword_channel",
                "Wakeword Background Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onDestroy() {
        isListening = false
        interpreter?.close()
        coroutineScope.cancel()
        if (::wakeLock.isInitialized && wakeLock.isHeld) wakeLock.release()
        super.onDestroy()
    }
}
