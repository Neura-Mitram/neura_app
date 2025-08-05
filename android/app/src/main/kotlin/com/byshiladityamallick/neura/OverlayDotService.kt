package com.byshiladityamallick.neura

import android.annotation.SuppressLint
import android.app.*
import android.content.*
import android.graphics.PixelFormat
import android.os.*
import android.speech.tts.TextToSpeech
import android.view.*
import android.view.animation.*
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.core.content.ContextCompat
import androidx.core.content.getSystemService
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import okhttp3.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.*

class OverlayDotService : Service() {
    // Constants
    private companion object {
        const val TAG = "OverlayDotService"
        const val SOS_COUNTDOWN_SEC = 5
        const val MAX_SUMMARY_ITEMS = 20
        const val NUDGE_FALLBACK_DELAY_MS = 1500L
    }

    // Views and UI
    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var dotIcon: ImageView? = null
    private lateinit var normalPulse: Animation
    private lateinit var fastPulse: Animation

    // State management
    private var sosBubbleView: View? = null
    private var hiBubbleView: View? = null
    private var sosBubbleTimer: Handler? = null
    private var countdown = SOS_COUNTDOWN_SEC
    private var cancelTriggered = false

    // Broadcast receivers
    private lateinit var wakewordReceiver: BroadcastReceiver
    private lateinit var unlockReceiver: BroadcastReceiver

    // Services
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val okHttpClient by lazy { createOkHttpClient() }

    @SuppressLint("UnspecifiedRegisterReceiverFlag", "ClickableViewAccessibility")
    override fun onCreate() {
        super.onCreate()

        // 🚫 Prevent execution if onboarding not completed
        if (!isOnboardingComplete()) {
            stopSelf()
            return
        }

        // Initialize UI components
        initWindowManager()
        setupPulseAnimations()
        dotIcon?.startAnimation(normalPulse)

        // Register broadcast receivers
        registerReceivers()

        // Start supporting services
        startSupportingServices()

        // Start app tracking if enabled
        if (isSmartTrackingEnabled()) {
            startForegroundServiceCompat(ForegroundAppDetector::class.java)
        }
    }

    private fun isOnboardingComplete(): Boolean {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return prefs.getBoolean("flutter.onboarding_completed", false)
    }

    private fun initWindowManager() {
        windowManager = getSystemService()
        val inflater = LayoutInflater.from(this)
        floatingView = inflater.inflate(R.layout.overlay_dot, null)

        val layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 50
            y = 300
        }

        dotIcon = floatingView?.findViewById(R.id.dot_icon)
        setupViewDragListener(layoutParams)
        setupViewClickListeners()
        windowManager?.addView(floatingView, layoutParams)
    }

    private fun setupViewDragListener(layoutParams: WindowManager.LayoutParams) {
        floatingView?.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f

            override fun onTouch(view: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = layoutParams.x
                        initialY = layoutParams.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        view.performClick()  // Accessibility support
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        layoutParams.x = initialX + (event.rawX - initialTouchX).toInt()
                        layoutParams.y = initialY + (event.rawY - initialTouchY).toInt()
                        windowManager?.updateViewLayout(floatingView, layoutParams)
                        return true
                    }
                }
                return false
            }
        })
    }

    private fun setupViewClickListeners() {
        floatingView?.setOnClickListener {
            vibrate(50)
            Toast.makeText(this, "👃 Hi, I'm listening...", Toast.LENGTH_SHORT).show()
        }

        floatingView?.setOnLongClickListener {
            MuteManager.nudgesMuted = !MuteManager.nudgesMuted
            val msg = if (MuteManager.nudgesMuted) "🔇 Nudges muted" else "🔔 Nudges unmuted"
            Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
            true
        }
    }

    private fun setupPulseAnimations() {
        normalPulse = ScaleAnimation(
            1f, 1.3f, 1f, 1.3f,
            Animation.RELATIVE_TO_SELF, 0.5f,
            Animation.RELATIVE_TO_SELF, 0.5f
        ).apply {
            duration = 800
            repeatMode = Animation.REVERSE
            repeatCount = Animation.INFINITE
            interpolator = AccelerateDecelerateInterpolator()
        }

        fastPulse = ScaleAnimation(
            1f, 1.5f, 1f, 1.5f,
            Animation.RELATIVE_TO_SELF, 0.5f,
            Animation.RELATIVE_TO_SELF, 0.5f
        ).apply {
            duration = 300
            repeatMode = Animation.REVERSE
            repeatCount = Animation.INFINITE
            interpolator = AccelerateDecelerateInterpolator()
        }
    }

    private fun registerReceivers() {
        // Wakeword event receiver
        wakewordReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    "com.neura.WAKEWORD_TRIGGERED" -> handleWakewordTrigger(intent)
                    "com.neura.TRIGGER_SMART_SOS" -> handleSosTrigger()
                    "com.neura.NEW_NUDGE" -> handleNudge(intent, "nudge")
                    "com.neura.HOURLY_NUDGE" -> handleNudge(intent, "hourly")
                    "com.neura.TRAVEL_TIP_RECEIVED" -> handleTravelTip(intent)
                    "com.neura.FOREGROUND_REPLY" -> handleNudge(intent, "foreground")
                }
            }
        }

        // Unlock receiver
        unlockReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_USER_PRESENT) {
                    serviceScope.launch { checkAndTriggerNudgeFallback() }
                }
            }
        }

        // Register both receivers
        val filter = IntentFilter().apply {
            addAction("com.neura.WAKEWORD_TRIGGERED")
            addAction("com.neura.TRIGGER_SMART_SOS")
            addAction("com.neura.NEW_NUDGE")
            addAction("com.neura.HOURLY_NUDGE")
            addAction("com.neura.TRAVEL_TIP_RECEIVED")
            addAction("com.neura.FOREGROUND_REPLY")
        }

        registerReceiver(wakewordReceiver, filter)
        registerReceiver(unlockReceiver, IntentFilter(Intent.ACTION_USER_PRESENT))
    }

    private fun startSupportingServices() {
        // Start location monitoring for travel tips
        startForegroundServiceCompat(LocationMonitorService::class.java)
    }

    private fun isSmartTrackingEnabled(): Boolean {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return prefs.getBoolean("flutter.smart_tracking_enabled", false)
    }

    // Region: Event Handlers
    private fun handleWakewordTrigger(intent: Intent) {
        pulseDotFaster()
        val langCode = intent.getStringExtra("lang") ?: "en"
        val text = intent.getStringExtra("text") ?: "Hi, I'm listening"
        showHiBubble(text)
        speakHiTts(text, langCode)
        triggerMicStart()

        Handler(Looper.getMainLooper()).postDelayed({
            dotIcon?.startAnimation(normalPulse)
        }, 3500)
    }

    private fun handleSosTrigger() {
        pulseDotFaster()
        vibrate(300)
        createSosBubble("Possible danger detected", "Unknown")
    }

    private fun handleNudge(intent: Intent, type: String) {
        val emoji = intent.getStringExtra("emoji") ?: "💡"
        val message = intent.getStringExtra("text") ?: "Here’s something for you"
        val langCode = intent.getStringExtra("lang") ?: "en"

        saveSummaryToCache(type, emoji, message)
        showNudgeBubble(message, emoji)

        if (shouldPlayVoiceNudge()) {
            speakHiTts(message, langCode)
        }
    }

    private fun handleTravelTip(intent: Intent) {
        val city = intent.getStringExtra("city") ?: "Unknown"
        val tips = intent.getStringExtra("tips") ?: return
        val audioUrl = intent.getStringExtra("audio_url") ?: ""

        saveSummaryToCache("travel", "📍 $city", tips)
        showNudgeBubble(tips, "📍 $city")

        if (shouldPlayVoiceNudge()) {
            if (audioUrl.isNotEmpty()) {
                try {
                    speakHiTts(audioUrl, "en", isUrl = true)
                } catch (e: Exception) {
                    speakHiTts(tips, "en")
                }
            } else {
                speakHiTts(tips, "en")
            }
        }
    }

    private fun shouldPlayVoiceNudge(): Boolean {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return prefs.getBoolean("flutter.voice_nudges_enabled", true) && !MuteManager.nudgesMuted
    }
    // End Region

    private fun pulseDotFaster() {
        dotIcon?.clearAnimation()
        dotIcon?.startAnimation(fastPulse)
    }

    private fun triggerMicStart() {
        val engine = FlutterEngineCache.getInstance().get("main_engine")
        engine?.let {
            MethodChannel(it.dartExecutor.binaryMessenger, "com.neura/mic_control").invokeMethod("startMic", null)
        }
    }

    private fun showHiBubble(text: String) {
        val inflater = LayoutInflater.from(this)
        hiBubbleView = inflater.inflate(R.layout.overlay_hi_bubble, null)

        val layoutParams = createOverlayLayoutParams().apply {
            x = 90
            y = if (isKeyboardVisible()) 150 else 450
        }

        animateViewAppearance(hiBubbleView, layoutParams, 2500)
    }

    private fun createSosBubble(message: String, location: String) {
        if (sosBubbleView != null) return

        val inflater = LayoutInflater.from(this)
        sosBubbleView = inflater.inflate(R.layout.overlay_sos_bubble, null)

        val layoutParams = createOverlayLayoutParams().apply {
            x = 80
            y = if (isKeyboardVisible()) 180 else 500
        }

        animateViewAppearance(sosBubbleView, layoutParams, 0)

        val msgView = sosBubbleView?.findViewById<TextView>(R.id.sos_message)
        val cancelBtn = sosBubbleView?.findViewById<Button>(R.id.cancel_button)

        msgView?.text = "⚠️ $message"
        cancelBtn?.text = "Cancel ($countdown)"

        cancelBtn?.setOnClickListener {
            cancelTriggered = true
            sosBubbleTimer?.removeCallbacksAndMessages(null)
            removeViewSafely(sosBubbleView)
            sosBubbleView = null
            Toast.makeText(this, "✅ SOS cancelled", Toast.LENGTH_SHORT).show()
        }

        startSosCountdown(location)
    }

    private fun startSosCountdown(location: String) {
        sosBubbleTimer = Handler(Looper.getMainLooper())
        sosBubbleTimer?.post(object : Runnable {
            override fun run() {
                if (countdown > 0) {
                    sosBubbleView?.findViewById<Button>(R.id.cancel_button)?.text = "Cancel ($countdown)"
                    countdown--
                    sosBubbleTimer?.postDelayed(this, 1000)
                } else {
                    if (!cancelTriggered) {
                        fetchAndLaunchSmsForSos("🚨 Possible danger detected. Please help me. Location: $location")
                    }
                    removeViewSafely(sosBubbleView)
                    sosBubbleView = null
                    countdown = SOS_COUNTDOWN_SEC
                }
            }
        })
    }

    private fun showNudgeBubble(text: String, emoji: String) {
        val inflater = LayoutInflater.from(this)
        val view = inflater.inflate(R.layout.overlay_hi_bubble, null)

        val layoutParams = createOverlayLayoutParams().apply {
            x = 100
            y = if (isKeyboardVisible()) 140 else 460
        }

        val textView = view.findViewById<TextView>(R.id.hi_message)
        textView.text = "$emoji $text"

        animateViewAppearance(view, layoutParams, 3000)
    }

    private fun createOverlayLayoutParams(): WindowManager.LayoutParams {
        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }
    }

    private fun animateViewAppearance(view: View?, layoutParams: WindowManager.LayoutParams, duration: Long) {
        if (view == null) return

        val fadeIn = AlphaAnimation(0f, 1f).apply {
            this.duration = 300
            fillAfter = true
        }

        view.startAnimation(fadeIn)
        windowManager?.addView(view, layoutParams)

        if (duration > 0) {
            Handler(Looper.getMainLooper()).postDelayed({
                val fadeOut = AlphaAnimation(1f, 0f).apply {
                    this.duration = 300
                    fillAfter = true
                }
                view.startAnimation(fadeOut)
                Handler(Looper.getMainLooper()).postDelayed({
                    removeViewSafely(view)
                }, 300)
            }, duration)
        }
    }

    private fun isKeyboardVisible(): Boolean {
        return getSystemService<InputMethodManager>()?.isAcceptingText == true
    }

    private fun speakHiTts(text: String, langCode: String, isUrl: Boolean = false) {
        if (isUrl) {
            startActivity(Intent(Intent.ACTION_VIEW, text.toUri()).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            })
            return
        }

        if (TtsManager.ttsEngine == null) {
            TtsManager.initialize(applicationContext) { engine ->
                engine.language = Locale.forLanguageTag(langCode)
                engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "NEURA_HI")
            }
        } else {
            TtsManager.ttsEngine?.language = Locale.forLanguageTag(langCode)
            TtsManager.ttsEngine?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "NEURA_HI")
        }
    }

    private suspend fun checkAndTriggerNudgeFallback() {
        val (token, deviceId) = getAuthCredentials() ?: return

        val request = Request.Builder()
            .url("https://byshiladityamallick-neura-smart-assistant.hf.space/event/check-nudge?device_id=$deviceId")
            .get()
            .addHeader("Authorization", "Bearer $token")
            .build()

        try {
            okHttpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@use
                val body = response.body?.string() ?: return@use

                JSONObject(body).let { json ->
                    val text = json.optString("text")
                    val emoji = json.optString("emoji", "💡")
                    val lang = json.optString("lang", "en")

                    if (text.isNotEmpty()) {
                        sendBroadcast(Intent("com.neura.NEW_NUDGE").apply {
                            putExtra("text", text)
                            putExtra("emoji", emoji)
                            putExtra("lang", lang)
                        })
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Nudge fallback error", e)
        }
    }

    private fun getAuthCredentials(): Pair<String, String>? {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val token = prefs.getString("auth_token", null) ?: return null
        val deviceId = prefs.getString("flutter.device_id", null) ?: return null
        return Pair(token, deviceId)
    }

    private fun fetchAndLaunchSmsForSos(message: String) {
        val (token, deviceId) = getAuthCredentials() ?: run {
            Toast.makeText(this, "⚠️ Missing credentials", Toast.LENGTH_SHORT).show()
            return
        }

        val requestBody = RequestBody.create(
            "application/json".toMediaTypeOrNull(),
            """{ "device_id": "$deviceId" }"""
        )

        val request = Request.Builder()
            .url("https://byshiladityamallick-neura-smart-assistant.hf.space/safety/list-sos-contacts")
            .post(requestBody)
            .addHeader("Authorization", "Bearer $token")
            .build()

        okHttpClient.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.e(TAG, "SOS contacts fetch failed", e)
            }

            override fun onResponse(call: Call, response: Response) {
                response.body?.string()?.let { body ->
                    try {
                        JSONObject(body).getJSONArray("contacts").let { contacts ->
                            for (i in 0 until contacts.length()) {
                                contacts.getJSONObject(i).getString("phone").let { phone ->
                                    launchPrefilledSms(phone, message)
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "SMS contact processing failed", e)
                    }
                }
            }
        })
    }

    private fun launchPrefilledSms(phone: String, message: String) {
        val intent = Intent(Intent.ACTION_SENDTO).apply {
            data = "smsto:$phone".toUri()
            putExtra("sms_body", message)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        
        if (intent.resolveActivity(packageManager) != null) {
            startActivity(intent)
        } else {
            Toast.makeText(this, "No SMS app found", Toast.LENGTH_SHORT).show()
        }
    }

    private fun saveSummaryToCache(type: String, emoji: String, text: String) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val existingJson = prefs.getString("cached_summary_list", "[]") ?: "[]"

        val summaryArray = try {
            JSONArray(existingJson)
        } catch (e: Exception) {
            JSONArray()
        }

        JSONObject().apply {
            put("type", type)
            put("emoji", emoji)
            put("text", text)
            put("timestamp", System.currentTimeMillis())
        }.let { newItem ->
            summaryArray.put(newItem)
        }

        // Trim to max items
        val limitedArray = JSONArray()
        val start = (summaryArray.length() - MAX_SUMMARY_ITEMS).coerceAtLeast(0)
        for (i in start until summaryArray.length()) {
            limitedArray.put(summaryArray.get(i))
        }

        prefs.edit().putString("cached_summary_list", limitedArray.toString()).apply()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.getBooleanExtra("check_nudge_fallback", false) == true) {
            serviceScope.launch { checkAndTriggerNudgeFallback() }
        }
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        scheduleServiceRestart()
    }

    private fun scheduleServiceRestart() {
        val restartIntent = Intent(this, OverlayDotService::class.java).apply {
            putExtra("check_nudge_fallback", true)
        }

        val pendingIntent = PendingIntent.getService(
            this,
            1,
            restartIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        getSystemService<AlarmManager>()?.set(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            SystemClock.elapsedRealtime() + NUDGE_FALLBACK_DELAY_MS,
            pendingIntent
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        cleanupResources()
    }

    private fun cleanupResources() {
        dotIcon?.clearAnimation()
        removeViewSafely(floatingView)
        removeViewSafely(sosBubbleView)
        removeViewSafely(hiBubbleView)
        
        unregisterReceiver(wakewordReceiver)
        unregisterReceiver(unlockReceiver)
        
        sosBubbleTimer?.removeCallbacksAndMessages(null)
        serviceScope.cancel()
    }

    private fun removeViewSafely(view: View?) {
        try {
            if (view != null && view.windowToken != null) {
                windowManager?.removeView(view)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error removing view", e)
        }
    }

    private fun vibrate(durationMs: Long) {
        getSystemService<Vibrator>()?.let { vibrator ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(durationMs)
            }
        }
    }

    private inline fun <reified T> startForegroundServiceCompat() {
        val intent = Intent(this, T::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun createOkHttpClient(): OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        .build()
}

object MuteManager {
    var nudgesMuted: Boolean = false
}

object TtsManager {
    var ttsEngine: TextToSpeech? = null
    
    fun initialize(context: Context, onReady: (TextToSpeech) -> Unit) {
        ttsEngine = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                ttsEngine?.let(onReady)
            }
        }
    }
    
    fun shutdown() {
        ttsEngine?.stop()
        ttsEngine?.shutdown()
        ttsEngine = null
    }
}