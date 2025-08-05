package com.byshiladityamallick.neura

import android.app.*
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.*
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

class ForegroundAppDetector : Service() {

    companion object {
        private const val TAG = "AppDetector"
        private const val CHANNEL_ID = "app_detector_channel"
        private const val NOTIFICATION_ID = 102
        private const val DETECTION_INTERVAL = 30000L // 30s

        private val SYSTEM_APP_PREFIXES = listOf(
            "com.android.launcher", "com.google.android.googlequicksearchbox",
            "com.miui.home", "com.samsung.android",
            "com.huawei.android.launcher", "com.oppo.launcher"
        )
    }

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val handler = Handler(Looper.getMainLooper())
    private var lastDetectedApp: String? = null
    private val okHttpClient by lazy { createOkHttpClient() }

    private val detectionRunnable = object : Runnable {
        override fun run() {
            detectForegroundApp()
            handler.postDelayed(this, DETECTION_INTERVAL)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        handler.post(detectionRunnable)
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        handler.removeCallbacks(detectionRunnable)
        serviceScope.cancel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun detectForegroundApp() {
        if (!isTrackingEnabled()) return

        serviceScope.launch {
            val packageName = getForegroundAppPackage() ?: return@launch
            if (packageName != lastDetectedApp && !isSystemApp(packageName)) {
                lastDetectedApp = packageName
                val appName = getAppName(packageName)
                Log.d(TAG, "Detected app: $appName ($packageName)")
                sendAppEventToBackend(packageName, appName)
            }
        }
    }

    private fun isTrackingEnabled(): Boolean {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return prefs.getBoolean("flutter.smart_tracking_enabled", false)
    }

    private fun getForegroundAppPackage(): String? {
        return try {
            val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val now = System.currentTimeMillis()
            val stats = manager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                now - 10000,
                now
            )
            stats.maxByOrNull { it.lastTimeUsed }?.packageName
        } catch (e: SecurityException) {
            Log.e(TAG, "Usage access permission not granted", e)
            null
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get foreground app", e)
            null
        }
    }

    private fun isSystemApp(packageName: String): Boolean {
        return SYSTEM_APP_PREFIXES.any { packageName.startsWith(it) }
    }

    private fun getAppName(packageName: String): String {
        return try {
            val info = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(info).toString()
        } catch (e: Exception) {
            packageName
        }
    }

    private suspend fun sendAppEventToBackend(packageName: String, appName: String) {
        val (token, deviceId) = getAuthCredentials() ?: return

        val metadata = JSONObject().apply {
            put("app_name", appName)
            put("package_name", packageName)
        }

        val eventData = JSONObject().apply {
            put("device_id", deviceId)
            put("event_type", "foreground_app")
            put("metadata", metadata)
        }

        val request = Request.Builder()
            .url("https://byshiladityamallick-neura-smart-assistant.hf.space/event/push-mobile")
            .addHeader("Authorization", "Bearer $token")
            .post(eventData.toString().toRequestBody("application/json".toMediaTypeOrNull()))
            .build()

        try {
            val response = okHttpClient.newCall(request).execute()
            if (!response.isSuccessful) return

            val body = response.body?.string() ?: return
            val prompt = JSONObject(body)
                .optJSONObject("event_trigger")
                ?.optString("prompt")

            if (!prompt.isNullOrEmpty()) triggerForegroundReply(prompt)
        } catch (e: Exception) {
            Log.e(TAG, "Error sending or processing app event", e)
        }
    }

    private fun getAuthCredentials(): Pair<String, String>? {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val token = prefs.getString("auth_token", null)
        val deviceId = prefs.getString("flutter.device_id", null)
        return if (token != null && deviceId != null) Pair(token, deviceId) else null
    }

    private fun triggerForegroundReply(text: String) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val lang = prefs.getString("flutter.preferred_lang", "en") ?: "en"

        val intent = Intent("com.neura.FOREGROUND_REPLY").apply {
            putExtra("text", text)
            putExtra("emoji", "\uD83D\uDCF1") // 📱
            putExtra("lang", lang)
        }

        sendBroadcast(intent)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "App Usage Tracker",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Tracks foreground apps for smart assistance"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Neura is observing app usage")
            .setContentText("Providing contextual assistance")
            .setSmallIcon(R.drawable.ic_dot_blue)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .build()
    }

    private fun createOkHttpClient(): OkHttpClient {
        return OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .writeTimeout(15, TimeUnit.SECONDS)
            .build()
    }
}
