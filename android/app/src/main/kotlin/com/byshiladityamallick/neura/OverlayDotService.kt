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
private var ttsEngine: TextToSpeech? = null

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
            val toneGen = android.media.ToneGenerator(android.media.AudioManager.STREAM_NOTIFICATION, 100)
            toneGen.startTone(android.media.ToneGenerator.TONE_PROP_ACK, 150)
            Toast.makeText(this, "👃 Hi, I'm listening...", Toast.LENGTH_SHORT).show()
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
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction("com.neura.WAKEWORD_TRIGGERED")
            addAction("com.neura.TRIGGER_SMART_SOS")
        }

        registerReceiver(wakewordReceiver, filter)
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

    private fun speakHiTts(text: String, langCode: String) {
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
                            val methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, "sos.screen.trigger")
                            methodChannel.invokeMethod("openSosScreen", mapOf(
                                "message" to message,
                                "location" to location,
                                "autoSms" to true,
                                "backgroundMic" to true,
                                "proofLog" to true
                            ))
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

    override fun onDestroy() {
        super.onDestroy()
        dotIcon?.clearAnimation()
        if (floatingView?.windowToken != null) {
            windowManager?.removeView(floatingView)
        }
        sosBubbleView?.let { windowManager?.removeView(it) }
        hiBubbleView?.let { windowManager?.removeView(it) }
        unregisterReceiver(wakewordReceiver)
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
