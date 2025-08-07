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
import androidx.work.*
import java.util.concurrent.TimeUnit

class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action.isNullOrBlank()) return

        val validActions = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON"
        )

        if (intent.action !in validActions) {
            Log.w(TAG, "Unsupported boot action: ${intent.action}")
            return
        }

        val userManager = context.getSystemService(Context.USER_SERVICE) as? UserManager
        if (userManager?.isUserUnlocked != true) {
            Log.i(TAG, "User is locked, deferring boot operations")
            return
        }

        Log.i(TAG, "Boot event received, scheduling BootWorker")

        val request = OneTimeWorkRequestBuilder<BootWorker>()
            .setInitialDelay(5, TimeUnit.SECONDS)
            .build()

        WorkManager.getInstance(context).enqueue(request)
    }

    companion object {
        private const val TAG = "BootReceiver"
    }
}


class BootWorker(appContext: Context, workerParams: WorkerParameters) :
    Worker(appContext, workerParams) {

    private val prefs = appContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    override fun doWork(): Result {
        val mode = prefs.getString("flutter.active_mode", "manual")
        val smartTracking = prefs.getBoolean("flutter.smart_tracking_enabled", false)

        return try {
            if (!prefs.getBoolean("flutter.onboarding_completed", false)) {
                Log.i(TAG, "Onboarding not complete – skipping service start")
                return Result.success()
            }

            if (mode == "ambient") {
                startServiceCompat(WakewordForegroundService::class.java)
                startServiceCompat(LocationMonitorService::class.java)
            }

            startServiceCompat(OverlayDotService::class.java) {
                putExtra("check_nudge_fallback", true)
            }

            if (smartTracking) {
                startServiceCompat(ForegroundAppDetector::class.java)
            }

            Log.i(TAG, "Boot services started successfully")
            Result.success()

        } catch (e: Exception) {
            Log.e(TAG, "BootWorker failure", e)
            Result.failure()
        }
    }

    private fun startServiceCompat(
        serviceClass: Class<*>,
        intentConfig: (Intent.() -> Unit)? = null
    ) {
        try {
            val intent = Intent(applicationContext, serviceClass).apply {
                intentConfig?.invoke(this)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.startForegroundService(applicationContext, intent)
            } else {
                applicationContext.startService(intent)
            }

            Log.d(TAG, "Started service: ${serviceClass.simpleName}")

        } catch (e: Exception) {
            Log.e(TAG, "Failed to start service: ${serviceClass.simpleName}", e)
        }
    }

    companion object {
        private const val TAG = "BootWorker"
    }
}
