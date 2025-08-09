package com.byshiladityamallick.neura

import android.app.*
import android.bluetooth.BluetoothManager
import android.content.*
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.*
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONObject
import java.io.IOException
import java.text.SimpleDateFormat
import java.util.*

class ForegroundSensorService : Service(), SensorEventListener {

    private val TAG = "ForegroundSensorService"
    private val BACKEND_URL = "https://byshiladityamallick-neura-smart-assistant.hf.space/event/push-mobile"

    // Sensors
    private lateinit var sensorManager: SensorManager
    private var lightValue: Float? = null
    private var proximityValue: Float? = null
    private var accelLast: FloatArray? = null
    private var accelMovementDetected = false

    // System states
    private var batteryLevelPct: Int = -1
    private var isCharging: Boolean = false
    private var screenState: String = "unknown"

    // Networking / scheduling
    private val client = OkHttpClient.Builder().callTimeout(15, java.util.concurrent.TimeUnit.SECONDS).build()
    private val handler = Handler(Looper.getMainLooper())
    private val SEND_INTERVAL_MS = 90_000L // 90 seconds
    private val dateIsoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    // Sampling thresholds
    private val ACCEL_THRESHOLD = 2.2f // tweak as needed

    private val sendRunnable = object : Runnable {
        override fun run() {
            // Build + send aggregated payload
            sendAggregatedSensorContext()
            handler.postDelayed(this, SEND_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "onCreate")

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager

        // Register sensors at normal delay and keep latest values
        sensorManager.getDefaultSensor(Sensor.TYPE_LIGHT)?.also {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
        }
        sensorManager.getDefaultSensor(Sensor.TYPE_PROXIMITY)?.also {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
        }
        sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.also {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
        }

        // Register battery receiver for updates
        registerReceiver(batteryReceiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))

        // Register screen on/off receiver
        val screenFilter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        registerReceiver(screenReceiver, screenFilter)

        startForegroundNotification()

        // Immediately post first send, then every interval
        handler.post(sendRunnable)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Keep service alive
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.i(TAG, "onDestroy")
        try {
            handler.removeCallbacks(sendRunnable)
            sensorManager.unregisterListener(this)
            unregisterReceiver(batteryReceiver)
            unregisterReceiver(screenReceiver)
        } catch (t: Throwable) {
            Log.w(TAG, "cleanup error", t)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // --- SensorEventListener ---
    override fun onSensorChanged(event: SensorEvent?) {
        event ?: return

        when (event.sensor.type) {
            Sensor.TYPE_LIGHT -> {
                lightValue = event.values.getOrNull(0)
            }
            Sensor.TYPE_PROXIMITY -> {
                proximityValue = event.values.getOrNull(0)
            }
            Sensor.TYPE_ACCELEROMETER -> {
                // store last and detect movement
                val x = event.values.getOrNull(0) ?: 0f
                val y = event.values.getOrNull(1) ?: 0f
                val z = event.values.getOrNull(2) ?: 0f
                accelLast = floatArrayOf(x, y, z)
                val magnitude = kotlin.math.sqrt(x * x + y * y + z * z)
                accelMovementDetected = accelMovementDetected || (kotlin.math.abs(magnitude - SensorManager.GRAVITY_EARTH) > ACCEL_THRESHOLD)
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // no-op
    }

    // --- Receivers ---
    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            try {
                intent ?: return
                val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                batteryLevelPct = if (level >= 0 && scale > 0) ((level * 100) / scale) else -1

                val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
                Log.d(TAG, "Battery updated: $batteryLevelPct% charging=$isCharging")
            } catch (e: Exception) {
                Log.w(TAG, "batteryReceiver error", e)
            }
        }
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_ON -> {
                    screenState = "on"
                    Log.d(TAG, "Screen ON")
                }
                Intent.ACTION_SCREEN_OFF -> {
                    screenState = "off"
                    Log.d(TAG, "Screen OFF")
                }
            }
        }
    }

    // --- Aggregation & Networking ---
    private fun sendAggregatedSensorContext() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val deviceId = prefs.getString("flutter.device_id", null)
        val token = prefs.getString("auth_token", null)

        if (deviceId.isNullOrEmpty() || token.isNullOrEmpty()) {
            Log.w(TAG, "Missing deviceId or token; skip send")
            return
        }

        // Build metadata map
        val metadata = JSONObject().apply {
            try {
                put("battery", if (batteryLevelPct >= 0) batteryLevelPct else JSONObject.NULL)
                put("charging", isCharging)
                // light: attempt normalized 0..1 if value small, otherwise send lux
                val light = lightValue
                if (light == null) put("light", JSONObject.NULL) else put("light", light)

                // proximity: using sensor value; convert to 'near'/'far' when possible
                val prox = proximityValue
                if (prox == null) {
                    put("proximity", JSONObject.NULL)
                } else {
                    val maxRange = sensorManager.getDefaultSensor(Sensor.TYPE_PROXIMITY)?.maximumRange ?: 1f
                    val proxStr = if (prox < maxRange) "near" else "far"
                    put("proximity", proxStr)
                    put("proximity_raw", prox)
                }

                // motion
                val motionState = when {
                    accelMovementDetected -> "moving"
                    else -> "stationary"
                }
                put("motion", motionState)

                // optionally include accel raw values
                accelLast?.let {
                    val ax = it.getOrNull(0) ?: 0f
                    val ay = it.getOrNull(1) ?: 0f
                    val az = it.getOrNull(2) ?: 0f
                    put("accel", JSONObject().apply {
                        put("x", ax); put("y", ay); put("z", az)
                    })
                }

                // bluetooth connected (best-effort)
                put("bluetooth_connected", isBluetoothConnectedSafely())

                // wifi connected
                put("wifi_connected", isWifiConnected())

                // time (ISO)
                put("time", dateIsoFormat.format(Date()))

                // device info
                put("device_os", "android")
                put("device_id_hint", Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID))
            } catch (e: Exception) {
                Log.w(TAG, "metadata build failed", e)
            }
        }

        // Build final payload as backend expects
        val payload = JSONObject().apply {
            put("device_id", deviceId)
            put("event_type", "sensor_context")
            put("metadata", metadata)
        }

        // Reset transient motion flag after packaging
        accelMovementDetected = false

        // Send via OkHttp on background thread
        CoroutineScope(Dispatchers.IO).launch {
            postToBackend(payload, token)
        }
    }

    private fun postToBackend(payload: JSONObject, token: String) {
        try {
            val body: RequestBody = payload.toString().toRequestBody("application/json; charset=utf-8".toMediaTypeOrNull())
            val req = Request.Builder()
                .url(BACKEND_URL)
                .addHeader("Authorization", "Bearer $token")
                .post(body)
                .build()

            client.newCall(req).execute().use { resp ->
                handleBackendResponse(resp)
            }
        } catch (e: IOException) {
            Log.e(TAG, "Network send failed", e)
        } catch (e: Exception) {
            Log.e(TAG, "Unexpected error sending payload", e)
        }
    }

    private fun handleBackendResponse(response: Response) {
        try {
            val code = response.code
            val text = response.body?.string()
            Log.d(TAG, "Backend response code=$code text=$text")

            if (!text.isNullOrEmpty()) {
                try {
                    val json = JSONObject(text)
                    // If backend returns an 'event_trigger' or prompt, send broadcast to MainActivity
                    val prompt = json.optJSONObject("event_trigger")?.optString("prompt")
                        ?: json.optString("prompt", null)
                    if (!prompt.isNullOrEmpty()) {
                        sendForegroundReplyBroadcast(prompt)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed parse backend response", e)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "handleBackendResponse error", e)
        }
    }

    // Broadcast to your existing MainActivity receiver
    private fun sendForegroundReplyBroadcast(text: String) {
        try {
            val intent = Intent("com.neura.FOREGROUND_REPLY").apply {
                putExtra("text", text)
                putExtra("emoji", "\uD83D\uDCF1")
                putExtra("lang", getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    .getString("flutter.preferred_lang", "en"))
            }
            sendBroadcast(intent)
            Log.d(TAG, "Broadcasted prompt to app")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to broadcast prompt", e)
        }
    }

    // --- Helpers for connectivity & bluetooth ---
    private fun isWifiConnected(): Boolean {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val net = cm.activeNetwork ?: return false
            val caps = cm.getNetworkCapabilities(net) ?: return false
            return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
        } catch (e: Exception) {
            Log.w(TAG, "isWifiConnected check failed", e)
            return false
        }
    }

    private fun isBluetoothConnectedSafely(): Boolean {
        try {
            // require BLUETOOTH_CONNECT on Android 12+
            val hasPermission = ContextCompat.checkSelfPermission(this, android.Manifest.permission.BLUETOOTH_CONNECT) ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED
            val bm = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager ?: return false
            if (!hasPermission) {
                // fallback: check whether adapter is enabled (less accurate)
                val adapter = java.lang.reflect.Array.get(javaClass, 0) // dummy to avoid lint - replaced below
                val bluetoothAdapter = android.bluetooth.BluetoothAdapter.getDefaultAdapter()
                return bluetoothAdapter?.isEnabled == true
            } else {
                // if permitted, check connected devices across profiles (GATT/GATT_SERVER/HEADSET etc.)
                val connected = bm.getConnectedDevices(android.bluetooth.BluetoothProfile.GATT).isNotEmpty()
                // also check HEADSET profile
                val headset = bm.getConnectedDevices(android.bluetooth.BluetoothProfile.HEADSET).isNotEmpty()
                return connected || headset
            }
        } catch (e: Exception) {
            Log.w(TAG, "Bluetooth check failed", e)
            return false
        }
    }
}
