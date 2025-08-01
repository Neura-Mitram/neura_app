package com.byshiladityamallick.neura

import android.app.*
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.*
import android.util.Log
import androidx.core.app.NotificationCompat
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException

class ForegroundAppDetector : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private var lastApp: String? = null

    private val CHANNEL_ID = "foreground_app_detector_channel"
    private val NOTIFICATION_ID = 101

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        handler.post(checkForegroundApp)
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        handler.removeCallbacks(checkForegroundApp)
    }

    private val checkForegroundApp = object : Runnable {
        override fun run() {
            val packageName = getForegroundApp()

            if (packageName != null && packageName != lastApp) {
                lastApp = packageName
                sendEventToBackend(packageName)
            }
            handler.postDelayed(this, 10000) // every 10 sec
        }
    }

    private fun getForegroundApp(): String? {
        val usageStatsManager =
            getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY, now - 10000, now
        )

        val recent = stats.maxByOrNull { it.lastTimeUsed }

        val hasAccess = recent != null
        Log.d("Neura", "📦 hasUsageAccess returned: $hasAccess")

        return recent?.packageName
    }

    private fun sendEventToBackend(packageName: String) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val trackingEnabled = prefs.getBoolean("flutter.smart_tracking_enabled", false)
        if (!trackingEnabled) {
            Log.d("Neura", "🧪 Smart tracking is disabled. Skipping foreground app event.")
            return
        }

        val excludedPrefixes = listOf(
            "com.android.launcher", "com.google.android.googlequicksearchbox",
            "com.miui.home", "com.samsung.android"
        )
        if (excludedPrefixes.any { packageName.startsWith(it) }) {
            Log.d("Neura", "⛔️ Ignored system app: $packageName")
            return
        }

        val token = prefs.getString("auth_token", null) ?: return
        val deviceId = prefs.getString("flutter.device_id", null) ?: return
        val appName = getAppName(packageName)

        Log.d("Neura", "✅ Detected app: $appName ($packageName)")

        val json = JSONObject().apply {
            put("device_id", deviceId)
            put("event_type", "foreground_app")
            put("metadata", JSONObject().apply {
                put("app_name", appName)
                put("package_name", packageName)
            })
        }

        val body = json.toString().toRequestBody("application/json".toMediaTypeOrNull())
        val request = Request.Builder()
            .url("https://byshiladityamallick-neura-smart-assistant.hf.space/event/push-mobile")
            .addHeader("Authorization", "Bearer $token")
            .post(body)
            .build()

        OkHttpClient().newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.e("Neura", "❌ Failed to send event", e)
            }

            override fun onResponse(call: Call, response: Response) {
                if (!response.isSuccessful) return
                val res = response.body?.string() ?: return
                try {
                    val jsonRes = JSONObject(res)
                    val text = jsonRes.optJSONObject("event_trigger")?.optString("prompt") ?: return
                    val lang = prefs.getString("flutter.preferred_lang", "en") ?: "en"

                    val intent = Intent("com.neura.FOREGROUND_REPLY").apply {
                        putExtra("text", text)
                        putExtra("emoji", "\uD83D\uDCF1") // 📱
                        putExtra("lang", lang)
                    }
                    sendBroadcast(intent)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        })
    }

    private fun getAppName(packageName: String): String {
        return try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (e: Exception) {
            packageName
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Neura App Usage Tracker",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Neura is tracking app activity")
            .setContentText("This helps provide proactive support.")
            .setSmallIcon(R.drawable.ic_dot_blue) // replace with real icon
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
