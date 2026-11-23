package ai.viewbridge.vouch

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Small platform odds and ends with no good Flutter plugin:
 *  deviceName() -> "Google Pixel 9"
 *  biometryName() -> "fingerprint" (iOS: "Face ID" or "Touch ID")
 *  isIgnoringBatteryOptimizations() -> bool
 *  requestIgnoreBatteryOptimizations(): opens the system dialog for this app
 *  openBatterySettings(): the full battery-optimisation list, as a fallback
 */
class AppSettingsChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val NAME = "ai.viewbridge.vouch/app_settings"

        fun register(activity: Activity, engine: FlutterEngine) {
            MethodChannel(engine.dartExecutor.binaryMessenger, NAME)
                .setMethodCallHandler(AppSettingsChannel(activity))
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "deviceName" -> result.success(deviceName())
                // What this phone calls its biometric; iOS answers Face ID / Touch ID.
                "biometryName" -> result.success("fingerprint")
                "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
                "requestIgnoreBatteryOptimizations" -> {
                    activity.startActivity(
                        Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                            .setData(Uri.parse("package:${activity.packageName}"))
                    )
                    result.success(null)
                }
                "openBatterySettings" -> {
                    activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("app_settings", e.message ?: e.javaClass.simpleName, null)
        }
    }

    private fun deviceName(): String {
        val m = Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
        val model = Build.MODEL
        return if (model.startsWith(m, ignoreCase = true)) model else "$m $model"
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = activity.getSystemService(PowerManager::class.java)
        return pm.isIgnoringBatteryOptimizations(activity.packageName)
    }
}
