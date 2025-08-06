package com.byshiladityamallick.neura

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.UserManager
import android.util.Log
import androidx.core.content.ContextCompat

class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_ONBOARDING = "flutter.onboarding_completed"
        private const val KEY_MODE = "flutter.active_mode"
        private const val KEY_SMART_TRACKING = "flutter.smart_tracking_enabled"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == null) return

        val validActions = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED, // Handle direct boot
            "android.intent.action.QUICKBOOT_POWERON" // OEM-specific
        )

        if (!validActions.contains(intent.action)) {
            Log.w(TAG, "Unsupported action received: ${intent.action}")
            return
        }

        // ✅ Prevent Foreground Service start until device is unlocked
        val userManager = context.getSystemService(Context.USER_SERVICE) as UserManager
        if (!userManager.isUserUnlocked) {
            Log.i(TAG, "Device is locked - delaying service start until unlock")
            return
        }

        Log.i(TAG, "Device boot completed & unlocked - starting services")

        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            if (!prefs.getBoolean(KEY_ONBOARDING, false)) {
                Log.w(TAG, "Onboarding not completed - skipping auto-start")
                return
            }

            val startServices = {
                when (prefs.getString(KEY_MODE, "manual")) {
                    "ambient" -> {
                        startServiceCompat(context, WakewordForegroundService::class.java)
                        startServiceCompat(context, LocationMonitorService::class.java)
                    }
                }

                startServiceCompat(context, OverlayDotService::class.java) {
                    putExtra("check_nudge_fallback", true)
                }

                if (prefs.getBoolean(KEY_SMART_TRACKING, false)) {
                    startServiceCompat(context, ForegroundAppDetector::class.java)
                }
            }

            // Delay only on Android 14+ to avoid ForegroundServiceStartNotAllowedException
            if (Build.VERSION.SDK_INT >= 34) {
                Handler(Looper.getMainLooper()).postDelayed(startServices, 5000)
            } else {
                startServices()
            }

            Log.i(TAG, "BootReceiver setup complete")
        } catch (e: Exception) {
            Log.e(TAG, "Critical error during boot sequence", e)
        }
    }

    private fun startServiceCompat(
        context: Context,
        serviceClass: Class<*>,
        intentConfig: (Intent.() -> Unit)? = null
    ) {
        try {
            Intent(context, serviceClass).apply {
                intentConfig?.invoke(this)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ContextCompat.startForegroundService(context, this)
                } else {
                    context.startService(this)
                }
                Log.d(TAG, "Service started: ${serviceClass.simpleName}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start ${serviceClass.simpleName}: ${e.message}")
        }
    }
}

