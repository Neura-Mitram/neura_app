package com.byshiladityamallick.neura

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.*
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.content.getSystemService
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import kotlin.math.*

class LocationMonitorService : Service(), LocationListener {
    // Constants
    private companion object {
        const val TAG = "LocationMonitor"
        const val CHANNEL_ID = "location_monitor_channel"
        const val NOTIFICATION_ID = 103
        const val LOCATION_INTERVAL_MS = 15 * 60 * 1000L // 15 minutes
        const val LOCATION_DISTANCE_KM = 100.0 // kilometers
        const val TRAVEL_THROTTLE_HOURS = 6
        const val TRAVEL_THROTTLE_MS = TRAVEL_THROTTLE_HOURS * 60 * 60 * 1000L // 6 hours
        const val MAX_LOCATION_AGE_MS = 5 * 60 * 1000L // 5 minutes
    }

    // Services
    private lateinit var locationManager: LocationManager
    private lateinit var prefs: SharedPreferences
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val okHttpClient by lazy { createOkHttpClient() }
    private var lastLocation: Location? = null

    override fun onCreate() {
        super.onCreate()
        prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        locationManager = getSystemService()!!
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (hasLocationPermission()) {
            requestLocationUpdates()
        } else {
            stopSelf()
        }
        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Location Monitoring",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Periodic location checks for travel assistance"
                setShowBadge(false)
            }
            getSystemService<NotificationManager>()?.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Neura Location Service")
            .setContentText("Checking for significant location changes")
            .setSmallIcon(R.drawable.ic_dot_blue)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .build()
    }

    private fun hasLocationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestLocationUpdates() {
        try {
            // First try to get last known location
            getLastKnownLocation()?.let { location ->
                if (isLocationFresh(location)) {
                    onLocationChanged(location)
                    return
                }
            }

            // Request new location updates
            locationManager.requestSingleUpdate(
                LocationManager.GPS_PROVIDER,
                this,
                Looper.getMainLooper()
            )

            // Set timeout for location acquisition
            serviceScope.launch {
                delay(30000) // 30 seconds timeout
                if (lastLocation == null) stopSelf()
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "Location permission not granted", e)
            stopSelf()
        } catch (e: Exception) {
            Log.e(TAG, "Location request failed", e)
            stopSelf()
        }
    }

    private fun getLastKnownLocation(): Location? {
        return try {
            locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
        } catch (e: SecurityException) {
            null
        }
    }

    private fun isLocationFresh(location: Location): Boolean {
        return System.currentTimeMillis() - location.time < MAX_LOCATION_AGE_MS
    }

    override fun onLocationChanged(location: Location) {
        lastLocation = location
        serviceScope.launch {
            processLocationChange(location)
            stopSelf()
        }
    }

    private suspend fun processLocationChange(location: Location) {
        val (lastLat, lastLon) = getLastCoordinates()
        val (deviceId, token) = getAuthCredentials() ?: return
        val lastTravelCheck = prefs.getLong("last_travel_check_ts", 0L)

        // Throttle travel checks
        if (System.currentTimeMillis() - lastTravelCheck < TRAVEL_THROTTLE_MS) return

        // Check if significant movement occurred
        if (haversine(lastLat, lastLon, location.latitude, location.longitude) > LOCATION_DISTANCE_KM) {
            sendTravelCheckRequest(location.latitude, location.longitude, deviceId, token)
        }
    }

    private fun getLastCoordinates(): Pair<Double, Double> {
        return Pair(
            prefs.getFloat("last_lat", 0f).toDouble(),
            prefs.getFloat("last_lon", 0f).toDouble()
        )
    }

    private fun getAuthCredentials(): Pair<String, String>? {
        val deviceId = prefs.getString("flutter.device_id", null) ?: return null
        val token = prefs.getString("auth_token", null) ?: return null
        return Pair(deviceId, token)
    }

    private suspend fun sendTravelCheckRequest(lat: Double, lon: Double, deviceId: String, token: String) {
        val request = createTravelCheckRequest(lat, lon, deviceId, token)

        try {
            okHttpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return

                // Update saved location
                updateLastLocation(lat, lon)

                response.body?.string()?.let { body ->
                    JSONObject(body).takeIf { it.optBoolean("is_travel_mode") }?.let { json ->
                        triggerTravelTipEvent(json)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Travel check request failed", e)
        }
    }

    private fun createTravelCheckRequest(lat: Double, lon: Double, deviceId: String, token: String): Request {
        val json = JSONObject().apply {
            put("lat", lat)
            put("lon", lon)
            put("device_id", deviceId)
        }

        return Request.Builder()
            .url("https://byshiladityamallick-neura-smart-assistant.hf.space/event/check-travel")
            .post(json.toString().toRequestBody("application/json".toMediaTypeOrNull()))
            .addHeader("Authorization", "Bearer $token")
            .build()
    }

    private fun updateLastLocation(lat: Double, lon: Double) {
        prefs.edit().apply {
            putFloat("last_lat", lat.toFloat())
            putFloat("last_lon", lon.toFloat())
            putLong("last_travel_check_ts", System.currentTimeMillis())
            apply()
        }
    }

    private fun triggerTravelTipEvent(json: JSONObject) {
        val city = json.optString("city_name")
        val tips = json.optString("tips")
        val audioUrl = json.optString("tips_audio_url")

        Intent("com.neura.TRAVEL_TIP_RECEIVED").apply {
            putExtra("city", city)
            putExtra("tips", tips)
            putExtra("audio_url", audioUrl)
        }.also { sendBroadcast(it) }
    }

    private fun haversine(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val R = 6371 // Earth radius in km
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = sin(dLat / 2).pow(2) +
                cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) *
                sin(dLon / 2).pow(2)
        val c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    override fun onDestroy() {
        super.onDestroy()
        cleanupResources()
    }

    private fun cleanupResources() {
        try {
            locationManager.removeUpdates(this)
            serviceScope.cancel()
        } catch (e: SecurityException) {
            // Ignore if permission was revoked
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onProviderEnabled(provider: String) {}
    override fun onProviderDisabled(provider: String) {}
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    override fun onFlushComplete(requestCode: Int) {}

    private fun createOkHttpClient(): OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        .build()
}
