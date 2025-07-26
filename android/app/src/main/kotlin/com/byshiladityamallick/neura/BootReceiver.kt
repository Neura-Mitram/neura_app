package com.byshiladityamallick.neura

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {

            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val onboardingDone = prefs.getBoolean("flutter.onboarding_completed", false)
            if (!onboardingDone) return // 🚫 don't auto-start anything

            val mode = prefs.getString("flutter.active_mode", "manual")

            if (mode == "ambient") {
                // 🔁 Start WakewordForegroundService
                val serviceIntent = Intent(context, WakewordForegroundService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }

                // 🧭 Start LocationMonitorService for travel detection
                val travelIntent = Intent(context, LocationMonitorService::class.java)
                context.startService(travelIntent)
            }

            // 🫧 Always start OverlayDotService + trigger fallback check
            val overlayIntent = Intent(context, OverlayDotService::class.java)
            overlayIntent.putExtra("check_nudge_fallback", true) // ✅ this line is important
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(overlayIntent)
            } else {
                context.startService(overlayIntent)
            }


            // ✅ NEW: Start Foreground App Detector if user enabled it
            val trackingEnabled = prefs.getBoolean("flutter.smart_tracking_enabled", false)
            if (trackingEnabled) {
                val fgIntent = Intent(context, ForegroundAppDetector::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(fgIntent)
                } else {
                    context.startService(fgIntent)
                }
            }
        }
    }
}
