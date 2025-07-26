package com.byshiladityamallick.neura

import android.annotation.SuppressLint
import android.app.Service
import android.content.*
import android.graphics.PixelFormat
import android.os.*
import android.speech.tts.TextToSpeech
import android.view.*
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.AlphaAnimation
import android.view.animation.Animation
import android.view.animation.ScaleAnimation
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import java.util.*
import androidx.core.net.toUri
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.Response
import okio.IOException
import org.json.JSONArray
import org.json.JSONObject

private var ttsEngine: TextToSpeech? = null
private lateinit var unlockReceiver: BroadcastReceiver

class OverlayDotService : Service() {
    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var dotIcon: ImageView? = null

    private lateinit var normalPulse: Animation
    private lateinit var fastPulse: Animation
    private lateinit var wakewordReceiver: BroadcastReceiver

    private var sosBubbleView: View? = null
    private var hiBubbleView: View? = null
    private var sosBubbleTimer: Handler? = null
    private var countdown = 5
    private var cancelTriggered = false

    @SuppressLint("UnspecifiedRegisterReceiverFlag", "ClickableViewAccessibility")
    override fun onCreate() {
        super.onCreate()

        // 🚫 Prevent execution if onboarding not completed
        val onboardingpref = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val onboardingDone = onboardingpref.getBoolean("flutter.onboarding_completed", false)
        if (!onboardingDone) {
            stopSelf()
            return
        }

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
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
        )
        layoutParams.gravity = Gravity.TOP or Gravity.START
        layoutParams.x = 50
        layoutParams.y = 300

        dotIcon = floatingView?.findViewById(R.id.dot_icon)
        setupPulseAnimations()
        dotIcon?.startAnimation(normalPulse)

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
                        view.performClick()  // ✅ Tells accessibility system this is a "click"
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


        windowManager?.addView(floatingView, layoutParams)

        floatingView?.setOnClickListener {
            val vibrator = getSystemService(VIBRATOR_SERVICE) as? Vibrator
            vibrator?.vibrate(50)
            Toast.makeText(this, "👃 Hi, I'm listening...", Toast.LENGTH_SHORT).show()
        }

        floatingView?.setOnLongClickListener {
            MuteManager.nudgesMuted = !MuteManager.nudgesMuted
            val msg = if (MuteManager.nudgesMuted) "🔇 Nudges muted" else "🔔 Nudges unmuted"
            Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
            true
        }


        wakewordReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    "com.neura.WAKEWORD_TRIGGERED" -> {
                        pulseDotFaster()
                        val langCode = intent.getStringExtra("lang") ?: "en"
                        val text = intent.getStringExtra("text") ?: "Hi, I'm listening"
                        showHiBubble(text)
                        speakHiTts(text, langCode)
                        val engine = FlutterEngineCache.getInstance().get("main_engine")
                        engine?.let {
                            val methodChannel = MethodChannel(it.dartExecutor.binaryMessenger, "com.neura/mic_control")
                            methodChannel.invokeMethod("startMic", null)
                        }
                        Handler(Looper.getMainLooper()).postDelayed({
                            dotIcon?.startAnimation(normalPulse)
                        }, 3500)
                    }

                    "com.neura.TRIGGER_SMART_SOS" -> {
                        pulseDotFaster()
                        val vibrator = getSystemService(VIBRATOR_SERVICE) as? Vibrator
                        vibrator?.vibrate(300)
                        createSosBubble("Possible danger detected", "Unknown")
                    }

                    "com.neura.NEW_NUDGE" -> {
                        val emoji = intent.getStringExtra("emoji") ?: "💡"
                        val message = intent.getStringExtra("text") ?: "Here’s something for you"
                        val langCode = intent.getStringExtra("lang") ?: "en"

                        // ✅ Save to chat summary cache
                        saveSummaryToCache("nudge", emoji, message)

                        showNudgeBubble(message, emoji)

                        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        val voiceNudgesEnabled = prefs.getBoolean("flutter.voice_nudges_enabled", true)
                        if (voiceNudgesEnabled) {
                            speakHiTts(message, langCode)
                        }
                    }

                    "com.neura.HOURLY_NUDGE" -> {
                        val emoji = intent.getStringExtra("emoji") ?: "⏰"
                        val message = intent.getStringExtra("text") ?: "Time for a mindful pause"
                        val langCode = intent.getStringExtra("lang") ?: "en"

                        // Show bubble + voice
                        showNudgeBubble(message, emoji)
                        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        val voiceNudgesEnabled = prefs.getBoolean("flutter.voice_nudges_enabled", true)
                        if (voiceNudgesEnabled) speakHiTts(message, langCode)

                        // Save to summary cache
                        saveSummaryToCache("hourly", emoji, message)
                    }

                    "com.neura.TRAVEL_TIP_RECEIVED" -> {
                        val city = intent.getStringExtra("city") ?: "Unknown"
                        val tips = intent.getStringExtra("tips") ?: return
                        val audioUrl = intent.getStringExtra("audio_url") ?: ""

                        // ✅ Save to summary cache
                        saveSummaryToCache("travel", "📍 $city", tips)
                        showNudgeBubble(tips, "📍 $city")

                        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        val voiceNudgesEnabled = prefs.getBoolean("flutter.voice_nudges_enabled", true)


                        if (voiceNudgesEnabled) {
                            if (audioUrl.isNotEmpty()) {
                                try {
                                    speakHiTts(audioUrl, "en", isUrl = true)
                                } catch (e: Exception) {
                                    // Fallback to native TTS
                                    speakHiTts(tips, "en")
                                }
                            } else {
                                // No URL – fallback immediately
                                speakHiTts(tips, "en")
                            }
                        }

                    }

                    "com.neura.FOREGROUND_REPLY" -> {
                        val message = intent.getStringExtra("text") ?: return
                        val emoji = intent.getStringExtra("emoji") ?: "📱"
                        val langCode = intent.getStringExtra("lang") ?: "en"

                        // Save to cache
                        saveSummaryToCache("foreground", emoji, message)

                        // Show bubble + voice
                        showNudgeBubble(message, emoji)

                        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        val voiceNudgesEnabled = prefs.getBoolean("flutter.voice_nudges_enabled", true)
                        if (voiceNudgesEnabled) speakHiTts(message, langCode)
                    }

                }
            }
        }

        val filter = IntentFilter().apply {
            addAction("com.neura.WAKEWORD_TRIGGERED")
            addAction("com.neura.TRIGGER_SMART_SOS")
            addAction("com.neura.NEW_NUDGE")
            addAction("com.neura.TRAVEL_TIP_RECEIVED")
            addAction("com.neura.FOREGROUND_REPLY")
        }

        registerReceiver(wakewordReceiver, filter)

        val unlockReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_USER_PRESENT) {
                    checkAndTriggerNudgeFallback() // ✅ pulls missed nudges
                }
            }
        }
        registerReceiver(unlockReceiver, IntentFilter(Intent.ACTION_USER_PRESENT))

        // 🚀 Auto-trigger location check for travel tips
        startService(Intent(this, LocationMonitorService::class.java))


        // ✅ Smart app tracking: start detector if enabled
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val trackingEnabled = prefs.getBoolean("flutter.smart_tracking_enabled", false)
        if (trackingEnabled) {
            try {
                val fgIntent = Intent(this, ForegroundAppDetector::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(fgIntent)
                } else {
                    startService(fgIntent)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }


    }

    private fun setupPulseAnimations() {
        normalPulse = ScaleAnimation(1f, 1.3f, 1f, 1.3f,
            Animation.RELATIVE_TO_SELF, 0.5f,
            Animation.RELATIVE_TO_SELF, 0.5f).apply {
            duration = 800
            repeatMode = Animation.REVERSE
            repeatCount = Animation.INFINITE
            interpolator = AccelerateDecelerateInterpolator()
        }

        fastPulse = ScaleAnimation(1f, 1.5f, 1f, 1.5f,
            Animation.RELATIVE_TO_SELF, 0.5f,
            Animation.RELATIVE_TO_SELF, 0.5f).apply {
            duration = 300
            repeatMode = Animation.REVERSE
            repeatCount = Animation.INFINITE
            interpolator = AccelerateDecelerateInterpolator()
        }
    }

    private fun pulseDotFaster() {
        dotIcon?.clearAnimation()
        dotIcon?.startAnimation(fastPulse)
    }

    private fun isKeyboardVisible(): Boolean {
        val inputMethodManager = getSystemService(Context.INPUT_METHOD_SERVICE) as? android.view.inputmethod.InputMethodManager
        return inputMethodManager?.isAcceptingText == true
    }

    private fun showHiBubble(text: String) {
        val inflater = LayoutInflater.from(this)
        hiBubbleView = inflater.inflate(R.layout.overlay_hi_bubble, null)

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
        )
        layoutParams.gravity = Gravity.TOP or Gravity.START
        layoutParams.x = 90
        layoutParams.y = if (isKeyboardVisible()) 150 else 450

        val fadeIn = AlphaAnimation(0f, 1f).apply {
            duration = 300
            fillAfter = true
        }
        val fadeOut = AlphaAnimation(1f, 0f).apply {
            duration = 300
            startOffset = 2200
            fillAfter = true
        }

        hiBubbleView?.startAnimation(fadeIn)
        windowManager?.addView(hiBubbleView, layoutParams)

        Handler(Looper.getMainLooper()).postDelayed({
            try {
                hiBubbleView?.startAnimation(fadeOut)
                windowManager?.removeView(hiBubbleView)
            } catch (_: Exception) {}
        }, 2500)
    }

    private fun speakHiTts(text: String, langCode: String, isUrl: Boolean = false) {
        if (isUrl) {
            val intent = Intent(Intent.ACTION_VIEW, text.toUri())
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(intent)
            return
        }
        if (ttsEngine == null) {
            ttsEngine = TextToSpeech(applicationContext) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    val locale = Locale.forLanguageTag(langCode)
                    ttsEngine?.language = locale
                    ttsEngine?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "NEURA_HI")
                }
            }
        } else {
            val locale = Locale.forLanguageTag(langCode)
            ttsEngine?.language = locale
            ttsEngine?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "NEURA_HI")
        }
    }

    private fun createSosBubble(message: String, location: String) {
        if (sosBubbleView != null) return

        val inflater = LayoutInflater.from(this)
        sosBubbleView = inflater.inflate(R.layout.overlay_sos_bubble, null)

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
        )
        layoutParams.gravity = Gravity.TOP or Gravity.START
        layoutParams.x = 80
        layoutParams.y = if (isKeyboardVisible()) 180 else 500

        val fadeIn = AlphaAnimation(0f, 1f).apply {
            duration = 300
            fillAfter = true
        }
        sosBubbleView?.startAnimation(fadeIn)

        val msgView = sosBubbleView!!.findViewById<TextView>(R.id.sos_message)
        val cancelBtn = sosBubbleView!!.findViewById<Button>(R.id.cancel_button)

        msgView.text = "⚠️ $message"
        cancelBtn.text = "Cancel ($countdown)"

        cancelBtn.setOnClickListener {
            cancelTriggered = true
            sosBubbleTimer?.removeCallbacksAndMessages(null)
            windowManager?.removeView(sosBubbleView)
            sosBubbleView = null
            Toast.makeText(this, "✅ SOS cancelled", Toast.LENGTH_SHORT).show()
        }

        windowManager?.addView(sosBubbleView, layoutParams)

        sosBubbleTimer = Handler(Looper.getMainLooper())
        sosBubbleTimer?.post(object : Runnable {
            override fun run() {
                if (countdown > 0) {
                    cancelBtn.text = "Cancel ($countdown)"
                    countdown--
                    sosBubbleTimer?.postDelayed(this, 1000)
                } else {
                    if (!cancelTriggered) {
                        val engine = FlutterEngineCache.getInstance().get("main_engine")
                        if (engine != null) {
                            val msg = "🚨 Possible danger detected. Please help me. Location: $location"
                            fetchAndLaunchSmsForSos(msg)
                        }
                    }
                    try {
                        windowManager?.removeView(sosBubbleView)
                    } catch (_: Exception) {}
                    sosBubbleView = null
                    countdown = 5
                }
            }
        })
    }

    private fun showNudgeBubble(text: String, emoji: String) {
        val inflater = LayoutInflater.from(this)
        val view = inflater.inflate(R.layout.overlay_hi_bubble, null) // reuse layout

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
        )
        layoutParams.gravity = Gravity.TOP or Gravity.START
        layoutParams.x = 100
        layoutParams.y = if (isKeyboardVisible()) 140 else 460

        val fadeIn = AlphaAnimation(0f, 1f).apply {
            duration = 300
            fillAfter = true
        }
        val fadeOut = AlphaAnimation(1f, 0f).apply {
            duration = 300
            startOffset = 2800
            fillAfter = true
        }

        val textView = view.findViewById<TextView>(R.id.hi_message)
        textView.text = "$emoji $text"

        windowManager?.addView(view, layoutParams)
        view.startAnimation(fadeIn)

        Handler(Looper.getMainLooper()).postDelayed({
            try {
                view.startAnimation(fadeOut)
                windowManager?.removeView(view)
            } catch (_: Exception) {}
        }, 3000)
    }

    private fun fetchAndLaunchSmsForSos(message: String) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val deviceId = prefs.getString("flutter.device_id", null)
        val token = prefs.getString("auth_token", null)

        if (deviceId.isNullOrEmpty() || token.isNullOrEmpty()) {
            Toast.makeText(this, "⚠️ Missing device ID or token", Toast.LENGTH_SHORT).show()
            return
        }

        val client = OkHttpClient()
        val requestBody = RequestBody.create(
            "application/json".toMediaTypeOrNull(),
            """{ "device_id": "$deviceId" }"""
        )

        val request = Request.Builder()
            .url("https://byshiladityamallick-neura-smart-assistant.hf.space/safety/list-sos-contacts")
            .post(requestBody)
            .addHeader("Authorization", "Bearer $token")
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                e.printStackTrace()
            }

            override fun onResponse(call: Call, response: Response) {
                response.body?.string()?.let { responseBody ->
                    try {
                        val json = JSONObject(responseBody)
                        val contacts = json.getJSONArray("contacts")

                        for (i in 0 until contacts.length()) {
                            val contact = contacts.getJSONObject(i)
                            val phone = contact.getString("phone")
                            launchPrefilledSms(phone, message)
                        }
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            }
        })
    }

    private fun launchPrefilledSms(phone: String, message: String) {
        val uri = "smsto:$phone".toUri()
        val intent = Intent(Intent.ACTION_SENDTO, uri).apply {
            putExtra("sms_body", message)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }

        if (intent.resolveActivity(packageManager) != null) {
            startActivity(intent)
        } else {
            Toast.makeText(this, "No SMS app found", Toast.LENGTH_SHORT).show()
        }
    }

    private fun checkAndTriggerNudgeFallback() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val token = prefs.getString("auth_token", null)
        val deviceId = prefs.getString("flutter.device_id", null)

        if (token.isNullOrEmpty() || deviceId.isNullOrEmpty()) return


        val client = OkHttpClient()
        val request = Request.Builder()
            .url("https://byshiladityamallick-neura-smart-assistant.hf.space/event/check-nudge?device_id=$deviceId")
            .get()
            .addHeader("Authorization", "Bearer $token")
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                e.printStackTrace()
            }

            override fun onResponse(call: Call, response: Response) {
                if (!response.isSuccessful) return
                val body = response.body?.string() ?: return

                try {
                    val json = JSONObject(body)
                    val text = json.optString("text")
                    val emoji = json.optString("emoji", "💡")
                    val lang = json.optString("lang", "en")

                    if (text.isNotEmpty()) {
                        val intent = Intent("com.neura.NEW_NUDGE").apply {
                            putExtra("text", text)
                            putExtra("emoji", emoji)
                            putExtra("lang", lang)
                        }
                        sendBroadcast(intent)
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        })
    }



    private fun saveSummaryToCache(type: String, emoji: String, text: String) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val existingJson = prefs.getString("cached_summary_list", "[]") ?: "[]"

        val summaryArray = try {
            JSONArray(existingJson)
        } catch (e: Exception) {
            JSONArray() // fallback if corrupted
        }

        // Create new summary item
        val newItem = JSONObject().apply {
            put("type", type)
            put("emoji", emoji)
            put("text", text)
            put("timestamp", System.currentTimeMillis())
        }

        summaryArray.put(newItem) // add at the end

        // ✅ Keep only the last 20 items
        val limitedArray = JSONArray()
        val start = if (summaryArray.length() > 20) summaryArray.length() - 20 else 0
        for (i in start until summaryArray.length()) {
            limitedArray.put(summaryArray.get(i))
        }

        // Save it back
        prefs.edit().putString("cached_summary_list", limitedArray.toString()).apply()
    }

    companion object {
        fun checkNudgeFallback(context: Context) {
            val intent = Intent(context, OverlayDotService::class.java)
            intent.putExtra("check_nudge_fallback", true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val shouldCheckNudge = intent?.getBooleanExtra("check_nudge_fallback", false) ?: false
        if (shouldCheckNudge) {
            checkAndTriggerNudgeFallback()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        dotIcon?.clearAnimation()
        if (floatingView?.windowToken != null) {
            windowManager?.removeView(floatingView)
        }
        sosBubbleView?.let { windowManager?.removeView(it) }
        hiBubbleView?.let { windowManager?.removeView(it) }
        unregisterReceiver(wakewordReceiver)
        unregisterReceiver(unlockReceiver)

    }

    override fun onBind(intent: Intent?): IBinder? = null
}

object MuteManager {
    var nudgesMuted: Boolean = false
}
