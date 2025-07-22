package com.byshiladityamallick.neura

import android.annotation.SuppressLint
import android.app.Service
import android.content.*
import android.graphics.PixelFormat
import android.os.*
import android.view.*
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.Animation
import android.view.animation.ScaleAnimation
import android.widget.ImageView
import android.widget.Toast
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter



class OverlayDotService : Service() {
    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var dotIcon: ImageView? = null

    private lateinit var normalPulse: Animation
    private lateinit var fastPulse: Animation
    private lateinit var wakewordReceiver: BroadcastReceiver


    @SuppressLint("UnspecifiedRegisterReceiverFlag")
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

        // ✅ Drag functionality
        floatingView?.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f

            @SuppressLint("ClickableViewAccessibility")
            override fun onTouch(view: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = layoutParams.x
                        initialY = layoutParams.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
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

        // ✅ Add to window
        windowManager?.addView(floatingView, layoutParams)

        // ✅ Tap = toast + tone + haptic
        floatingView?.setOnClickListener {
            val vibrator = getSystemService(VIBRATOR_SERVICE) as? Vibrator
            vibrator?.vibrate(50)

            val toneGen = android.media.ToneGenerator(android.media.AudioManager.STREAM_NOTIFICATION, 100)
            toneGen.startTone(android.media.ToneGenerator.TONE_PROP_ACK, 150)

            Toast.makeText(this, "👂 Hi, I'm listening...", Toast.LENGTH_SHORT).show()
        }

        // ✅ Broadcast receiver for wakeword
        wakewordReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == "com.neura.WAKEWORD_TRIGGERED") {
                    pulseDotFaster()
                    showHiPopup()

                    val engine = FlutterEngineCache.getInstance().get("main_engine")
                    if (engine != null) {
                        val methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.neura/mic_control")
                        methodChannel.invokeMethod("startMic", null)
                    }

                    Handler(Looper.getMainLooper()).postDelayed({
                        dotIcon?.startAnimation(normalPulse)
                    }, 3500)
                }
            }
        }

        val filter = IntentFilter("com.neura.WAKEWORD_TRIGGERED")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                wakewordReceiver,
                filter,
                null,
                null,
                Context.RECEIVER_VISIBLE_TO_INSTANT_APPS
            )
        } else {
            // 👇 Old version does NOT support extra args
            @Suppress("DEPRECATION")
            registerReceiver(wakewordReceiver, filter)
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

    private fun pulseDotFaster() {
        dotIcon?.clearAnimation()
        dotIcon?.startAnimation(fastPulse)
    }

    private fun showHiPopup() {
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(this, "👂 Hi, I'm listening...", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        dotIcon?.clearAnimation()
        if (floatingView?.windowToken != null) {
            windowManager?.removeView(floatingView)
        }
        unregisterReceiver(wakewordReceiver)
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
