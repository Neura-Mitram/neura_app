package com.byshiladityamallick.neura

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.media.*
import android.os.*
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*
import kotlinx.coroutines.isActive
import okhttp3.*
import okio.ByteString
import org.tensorflow.lite.Interpreter
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.TimeUnit

class WakewordForegroundService : Service() {

    private companion object {
        const val TAG = "WakewordService"
        const val NOTIFICATION_ID = 101
        const val CHANNEL_ID = "wakeword_channel"
        const val COOLDOWN_MS = 4000L
        const val WAKE_LOCK_TIMEOUT = 10 * 60 * 1000L // 10 minutes
        const val SAMPLE_RATE = 16000
        const val MODEL_FILE = "wakeword_model.tflite"
        const val WAKE_PHRASE = "Hi, I'm listening"
        const val INFERENCE_DELAY_MS = 100L
    }

    private var interpreter: Interpreter? = null
    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private lateinit var wakeLock: PowerManager.WakeLock
    private lateinit var prefs: SharedPreferences
    private var lastTriggeredAt: Long = 0
    private val okHttpClient by lazy { createOkHttpClient() }

    override fun onCreate() {
        super.onCreate()
        prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        if (!prefs.getBoolean("flutter.onboarding_completed", false)) {
            stopSelf()
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                // Use safe reflection-free API if available
                startForeground(
                    NOTIFICATION_ID,
                    createNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                )
            } catch (_: Exception) {
                startForeground(NOTIFICATION_ID, createNotification())
            }
        } else {
            startForeground(NOTIFICATION_ID, createNotification())
        }

        wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager).newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "neura::WakewordLock"
        ).apply { acquire(WAKE_LOCK_TIMEOUT) }

        createNotificationChannel()
        requestAudioFocus()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        serviceScope.launch {
            runInferenceLoop()
        }
        return START_STICKY
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Neura is listening")
            .setContentText("Your assistant is running in background")
            .setSmallIcon(R.drawable.ic_dot_blue)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Wakeword Detection",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Background service for wakeword detection"
                setShowBadge(false)
            }

            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun requestAudioFocus() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val result = audioManager.requestAudioFocus(
            { /* ignore changes */ },
            AudioManager.STREAM_VOICE_CALL,
            AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE
        )

        if (result != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            Log.w(TAG, "Audio focus not granted - wakeword detection may be impaired")
        }
    }

    private fun abandonAudioFocus() {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.abandonAudioFocus(null)
    }

    private suspend fun runInferenceLoop() {
        try {
            val modelFile = File(filesDir, MODEL_FILE)
            if (!modelFile.exists()) {
                Log.e(TAG, "Model file not found")
                stopSelf()
                return
            }

            interpreter = Interpreter(modelFile)

            val bufferSize = AudioRecord.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )

            if (ContextCompat.checkSelfPermission(
                    this,
                    android.Manifest.permission.RECORD_AUDIO
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                stopSelf()
                return
            }

            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            ).apply { startRecording() }

            val inputSize = 16000
            val audioBuffer = ShortArray(inputSize)
            val inputBuffer = ByteBuffer.allocateDirect(inputSize * 2)
                .order(ByteOrder.nativeOrder())
            val outputBuffer = ByteBuffer.allocateDirect(4)
                .order(ByteOrder.nativeOrder())

            while (serviceScope.isActive) {
                val read = audioRecord?.read(audioBuffer, 0, inputSize) ?: 0
                if (read <= 0) continue

                inputBuffer.clear()
                for (i in 0 until read) inputBuffer.putShort(audioBuffer[i])
                outputBuffer.clear()

                interpreter?.run(inputBuffer, outputBuffer)
                outputBuffer.rewind()
                val score = outputBuffer.float

                val now = System.currentTimeMillis()
                if (score > 0.8f && now - lastTriggeredAt > COOLDOWN_MS) {
                    lastTriggeredAt = now
                    handleWakewordTrigger()
                    break
                }

                delay(INFERENCE_DELAY_MS)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Inference error", e)
        } finally {
            cleanupResources()
            stopSelf()
        }
    }

    private fun handleWakewordTrigger() {
        try {
            (getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator)?.let { vibrator ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(VibrationEffect.createOneShot(100, VibrationEffect.DEFAULT_AMPLITUDE))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(100)
                }
            }

            ContextCompat.startForegroundService(
                this,
                Intent(this, OverlayDotService::class.java)
            )

            sendBroadcast(Intent("com.neura.WAKEWORD_TRIGGERED"))

            serviceScope.launch {
                playWelcomeSound()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Trigger handling failed", e)
        }
    }

    private suspend fun playWelcomeSound() {
        try {
            val voicePref = prefs.getString("flutter.voice", "male") ?: "male"
            val langPref = prefs.getString("flutter.preferred_lang", "en") ?: "en"
            val voiceId = if (voicePref == "female") "onwK4e9ZLuTAKqWW03F9" else "EXAVITQu4vr4xnSDxMaL"

            val encodedText = WAKE_PHRASE.replace(" ", "%20")
            val ttsUrl = "wss://byshiladityamallick-neura-smart-assistant.hf.space/" +
                    "ws/stream/elevenlabs?text=$encodedText&voice_id=$voiceId&lang=$langPref"

            val minBufferSize = AudioTrack.getMinBufferSize(
                22050,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )

            audioTrack = AudioTrack(
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
            ).apply { play() }

            val request = Request.Builder().url(ttsUrl).build()
            val webSocket = okHttpClient.newWebSocket(request, object : WebSocketListener() {
                override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                    audioTrack?.write(bytes.toByteArray(), 0, bytes.size)
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    releaseAudioTrack()
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    Log.e(TAG, "TTS websocket error", t)
                    releaseAudioTrack()
                }
            })

            withContext(Dispatchers.IO) {
                delay(15000)
                webSocket.close(1000, "Timeout")
            }
        } catch (e: Exception) {
            Log.e(TAG, "TTS playback error", e)
            releaseAudioTrack()
        }
    }

    private fun releaseAudioTrack() {
        try {
            audioTrack?.apply {
                if (state != AudioTrack.STATE_UNINITIALIZED) {
                    stop()
                    release()
                }
            }
            audioTrack = null
        } catch (e: Exception) {
            Log.e(TAG, "AudioTrack release error", e)
        }
    }

    private fun cleanupResources() {
        try {
            abandonAudioFocus()

            audioRecord?.apply {
                if (recordingState == AudioRecord.RECORDSTATE_RECORDING) stop()
                release()
            }
            audioRecord = null

            releaseAudioTrack()
            interpreter?.close()
            interpreter = null
        } catch (e: Exception) {
            Log.e(TAG, "Resource cleanup error", e)
        }
    }

    private fun createOkHttpClient(): OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        .build()

    override fun onDestroy() {
        serviceScope.cancel("Service destroyed")
        if (::wakeLock.isInitialized && wakeLock.isHeld) wakeLock.release()
        cleanupResources()
        super.onDestroy()
    }
}
