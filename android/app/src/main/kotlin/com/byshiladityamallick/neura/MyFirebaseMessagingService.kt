package com.byshiladityamallick.neura

import android.content.Intent
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okio.IOException

class MyFirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val data = remoteMessage.data

        // ✅ Fallback ping handler
        val screen = data["screen"]
        if (screen == "nudge") {
            OverlayDotService.checkNudgeFallback(applicationContext)
        }

        // Handle 📍 Travel Tip
        val city = data["city_name"]
        val tips = data["tips"]
        val audioUrl = data["tips_audio_url"]

        if (!city.isNullOrEmpty() && !tips.isNullOrEmpty()) {
            val intent = Intent("com.neura.TRAVEL_TIP_RECEIVED").apply {
                putExtra("city", city)
                putExtra("tips", tips)
                putExtra("audio_url", audioUrl ?: "")
            }
            sendBroadcast(intent)
        }

        // Handle 💡 Nudge
        val emoji = data["emoji"]
        val nudgeText = data["nudge_text"]
        val lang = data["lang"]

        if (!nudgeText.isNullOrEmpty()) {
            val intent = Intent("com.neura.NEW_NUDGE").apply {
                putExtra("emoji", emoji ?: "💡")
                putExtra("text", nudgeText)
                putExtra("lang", lang ?: "en")
            }
            sendBroadcast(intent)
        }

        // Handle ⏰ Hourly Nudge
        val hourlyText = data["hourly_text"]
        val hourlyEmoji = data["hourly_emoji"]
        val hourlyLang = data["hourly_lang"]

        if (!hourlyText.isNullOrEmpty()) {
            val intent = Intent("com.neura.HOURLY_NUDGE").apply {
                putExtra("text", hourlyText)
                putExtra("emoji", hourlyEmoji ?: "⏰")
                putExtra("lang", hourlyLang ?: "en")
            }
            sendBroadcast(intent)
        }
    }

    override fun onNewToken(token: String) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val deviceId = prefs.getString("flutter.device_id", null)
        val authToken = prefs.getString("auth_token", null)

        if (deviceId.isNullOrEmpty() || authToken.isNullOrEmpty()) return

        val json = """{
        "device_id": "$deviceId",
        "fcm_token": "$token"
        }"""

        val client = okhttp3.OkHttpClient()
        val requestBody = okhttp3.RequestBody.create(
            "application/json".toMediaTypeOrNull(),
            json
        )

        val request = okhttp3.Request.Builder()
            .url("https://byshiladityamallick-neura-smart-assistant.hf.space/user/update-fcm-token")
            .addHeader("Authorization", "Bearer $authToken")
            .post(requestBody)
            .build()

        client.newCall(request).enqueue(object : okhttp3.Callback {
            override fun onFailure(call: okhttp3.Call, e: IOException) {
                e.printStackTrace()
            }

            override fun onResponse(call: okhttp3.Call, response: okhttp3.Response) {
                // Log or ignore
            }
        })
    }

}
