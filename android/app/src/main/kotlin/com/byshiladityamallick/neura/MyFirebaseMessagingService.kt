package com.byshiladityamallick.neura

import android.content.Intent
import android.util.Log
import androidx.annotation.VisibleForTesting
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit


class MyFirebaseMessagingService : FirebaseMessagingService() {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val okHttpClient by lazy { createOkHttpClient() }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val data = remoteMessage.data

        when {
            data["screen"] == "nudge" -> triggerNudgeFallback()
            data["city_name"]?.isNotEmpty() == true && data["tips"]?.isNotEmpty() == true ->
                handleTravelTip(data)
            data["nudge_text"]?.isNotEmpty() == true ->
                handleNudge(data)
            data["hourly_text"]?.isNotEmpty() == true ->
                handleHourlyNudge(data)
        }
    }

    private fun triggerNudgeFallback() {
    val intent = Intent(applicationContext, OverlayDotService::class.java).apply {
        putExtra("check_nudge_fallback", true)
    }
    ContextCompat.startForegroundService(applicationContext, intent)
    }


    private fun handleTravelTip(data: Map<String, String>) {
        sendBroadcast(Intent("com.neura.TRAVEL_TIP_RECEIVED").apply {
            putExtra("city", data["city_name"])
            putExtra("tips", data["tips"])
            putExtra("audio_url", data["tips_audio_url"])
        })
    }

    private fun handleNudge(data: Map<String, String>) {
        sendBroadcast(Intent("com.neura.NEW_NUDGE").apply {
            putExtra("emoji", data["emoji"] ?: "💡")
            putExtra("text", data["nudge_text"])
            putExtra("lang", data["lang"] ?: "en")
        })
    }

    private fun handleHourlyNudge(data: Map<String, String>) {
        sendBroadcast(Intent("com.neura.HOURLY_NUDGE").apply {
            putExtra("text", data["hourly_text"])
            putExtra("emoji", data["hourly_emoji"] ?: "⏰")
            putExtra("lang", data["hourly_lang"] ?: "en")
        })
    }

    override fun onNewToken(token: String) {
        serviceScope.launch {
            updateFcmTokenOnServer(token)
        }
    }

    private suspend fun updateFcmTokenOnServer(token: String) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val deviceId = prefs.getString("flutter.device_id", null) ?: return
        val authToken = prefs.getString("auth_token", null) ?: return

        val json = createTokenUpdateJson(deviceId, token)
        val request = createTokenUpdateRequest(json, authToken)

        runCatching {
            okHttpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    Log.w(TAG, "❌ Token update failed: ${response.code}")
                } else {
                    Log.i(TAG, "✅ FCM token updated successfully")
                }
            }
        }.onFailure {
            Log.e(TAG, "🚫 Error updating FCM token", it)
        }
    }

    @VisibleForTesting
    internal fun createTokenUpdateJson(deviceId: String, token: String): String {
        return JSONObject().apply {
            put("device_id", deviceId)
            put("fcm_token", token)
        }.toString()
    }

    @VisibleForTesting
    internal fun createTokenUpdateRequest(json: String, authToken: String): Request {
        return Request.Builder()
            .url("$BASE_URL/user/update-fcm-token")
            .addHeader("Authorization", "Bearer $authToken")
            .post(json.toRequestBody("application/json".toMediaTypeOrNull()))
            .build()
    }

    private fun createOkHttpClient(): OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        .build()

    companion object {
        private const val TAG = "FCMService"
        private const val BASE_URL = "https://byshiladityamallick-neura-smart-assistant.hf.space"
    }
}
