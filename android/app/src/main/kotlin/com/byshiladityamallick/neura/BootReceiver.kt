package com.byshiladityamallick.neura

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
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
            "android.intent.action.QUICKBOOT_POWERON"  // For OEM-specific boot events
        )
        
        if (!validActions.contains(intent.action)) {
            Log.w(TAG, "Unsupported action received: ${intent.action}")
            return
        }

        Log.i(TAG, "Device boot completed - starting services")
        
        try {
            // 1. Get shared preferences safely
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            
            // 2. Validate onboarding status
            if (!prefs.getBoolean(KEY_ONBOARDING, false)) {
                Log.w(TAG, "Onboarding not completed - skipping auto-start")
                return
            }

            // 3. Start services based on configuration
            when (prefs.getString(KEY_MODE, "manual")) {
                "ambient" -> {
                    startServiceCompat(context, WakewordForegroundService::class.java)
                    startServiceCompat(context, LocationMonitorService::class.java)
                }
            }

            // 4. Start overlay service with fallback
            startServiceCompat(context, OverlayDotService::class.java) {
                putExtra("check_nudge_fallback", true)
            }

            // 5. Start app detector if enabled
            if (prefs.getBoolean(KEY_SMART_TRACKING, false)) {
                startServiceCompat(context, ForegroundAppDetector::class.java)
            }
            
            Log.i(TAG, "Boot services launched successfully")
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
                
                // Use modern ContextCompat for service starting
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