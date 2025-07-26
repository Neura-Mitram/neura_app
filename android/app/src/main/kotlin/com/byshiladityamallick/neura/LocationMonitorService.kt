package com.byshiladityamallick.neura

import android.Manifest
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.widget.Toast
import androidx.core.content.ContextCompat
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import org.json.JSONObject
import java.io.IOException

class LocationMonitorService : Service(), LocationListener {

    private lateinit var locationManager: LocationManager

    private val LOCATION_INTERVAL_MS = 15 * 60 * 1000L // 15 minutes
    private val LOCATION_DISTANCE_KM = 100.0 // kilometers
    private val TRAVEL_THROTTLE_INTERVAL_MS = 6 * 60 * 60 * 1000L // 6 hours


    override fun onCreate() {
        super.onCreate()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        startLocationUpdates()
    }

    private fun startLocationUpdates() {
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            Toast.makeText(this, "Location permission not granted", Toast.LENGTH_SHORT).show()
            stopSelf()
            return
        }

        try {
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                LOCATION_INTERVAL_MS,
                0f, // or set a min distance if you want, e.g. 500f meters
                this,
                Looper.getMainLooper()
            )
        } catch (ex: Exception) {
            ex.printStackTrace()
        }
    }

    override fun onLocationChanged(location: Location) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val lastLat = prefs.getFloat("last_lat", 0f).toDouble()
        val lastLon = prefs.getFloat("last_lon", 0f).toDouble()
        val deviceId = prefs.getString("flutter.device_id", null)
        val token = prefs.getString("auth_token", null)
        val lastTravelCheck = prefs.getLong("last_travel_check_ts", 0L)

        if (deviceId.isNullOrEmpty() || token.isNullOrEmpty()) {
            stopSelf()
            return
        }

        val now = System.currentTimeMillis()
        if (now - lastTravelCheck < TRAVEL_THROTTLE_INTERVAL_MS) {
            stopSelf()
            return
        }

        val movedDistance = haversine(lastLat, lastLon, location.latitude, location.longitude)

        if (movedDistance > LOCATION_DISTANCE_KM) {
            sendTravelCheckRequest(location.latitude, location.longitude, deviceId, token)
        } else {
            stopSelf()
        }
    }

    private fun sendTravelCheckRequest(lat: Double, lon: Double, deviceId: String, token: String) {
        val client = OkHttpClient()
        val json = JSONObject()
        json.put("lat", lat)
        json.put("lon", lon)
        json.put("device_id", deviceId)

        val body = RequestBody.create("application/json".toMediaTypeOrNull(), json.toString())
        val request = Request.Builder()
            .url("https://byshiladityamallick-neura-smart-assistant.hf.space/event/check-travel")
            .post(body)
            .addHeader("Authorization", "Bearer $token")
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                e.printStackTrace()
            }

            override fun onResponse(call: Call, response: Response) {
                if (response.isSuccessful) {
                    val responseBody = response.body?.string() ?: ""
                    val json = JSONObject(responseBody)
                    // ✅ Update saved location
                    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    prefs.edit().apply {
                        putFloat("last_lat", lat.toFloat())
                        putFloat("last_lon", lon.toFloat())
                        apply()
                    }

                    // 🔄 Trigger travel bubble + audio
                    if (json.optBoolean("is_travel_mode")) {
                        val city = json.optString("city_name")
                        val tips = json.optString("tips")
                        val audioUrl = json.optString("tips_audio_url")

                        val intent = Intent("com.neura.TRAVEL_TIP_RECEIVED").apply {
                            putExtra("city", city)
                            putExtra("tips", tips)
                            putExtra("audio_url", audioUrl)
                        }
                        sendBroadcast(intent)
                    }
                }

                stopSelf()
            }
        })
    }

    private fun haversine(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val R = 6371 // km
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                Math.sin(dLon / 2) * Math.sin(dLon / 2)
        val c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return R * c
    }

    override fun onDestroy() {
        super.onDestroy()
        locationManager.removeUpdates(this)
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
