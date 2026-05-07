package com.lulo.dormdevise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/**
 * 处理桌面微件点击事件，实现简单的双击检测逻辑。
 * - 首次点击记录时间戳；若在阈值内再次点击则视为双击并触发开门流程；
 * - 双击时将写入 SharedPreferences 标志并启动 DoorWidgetRouterActivity 以预热 Flutter 引擎并执行开门。
 */
class DoorWidgetClickReceiver : BroadcastReceiver() {
    companion object {
        private const val ACTION_WIDGET_CLICK = "com.lulo.dormdevise.DOOR_WIDGET_CLICK"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val LAST_CLICK_KEY = "door_widget_last_click_ts"
        private const val LAST_TRIGGER_KEY = "door_widget_last_trigger_ts"
        // 与 shared_preferences 保持一致：Dart 侧键 door_widget_pending_auto_open 在原生层会带 flutter. 前缀。
        private const val PENDING_AUTO_OPEN = "flutter.door_widget_pending_auto_open"
        private const val DOUBLE_TAP_WINDOW_MS = 600L
        private const val DEBOUNCE_INTERVAL_MS = 4000L  // 4秒防抖，与开门页面一致
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_WIDGET_CLICK) return

        val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val last = prefs.getLong(LAST_CLICK_KEY, 0L)
        val now = System.currentTimeMillis()
        if (now - last <= DOUBLE_TAP_WINDOW_MS) {
            // 防抖检查：4秒内不允许重复触发
            val lastTrigger = prefs.getLong(LAST_TRIGGER_KEY, 0L)
            if (now - lastTrigger < DEBOUNCE_INTERVAL_MS) {
                Log.d("DoorWidget", "Debounce: ignoring double-tap within 4 seconds")
                prefs.edit().putLong(LAST_CLICK_KEY, 0L).apply()
                return
            }
            
            // 记录本次触发时间
            prefs.edit().putLong(LAST_TRIGGER_KEY, now).apply()
             
            // 双击检测成功 - 先触发振动反馈
            triggerHapticFeedback(context)
             
            // 双击：尽量直接触发开门（通过传递 directOpen 标志给路由 Activity）
            prefs.edit().putBoolean(PENDING_AUTO_OPEN, true).apply()
            val launchIntent = Intent(context, DoorWidgetRouterActivity::class.java).apply {
                putExtra("directOpen", true)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            }
            Log.d("DoorWidget", "Double-tap detected, launching router with directOpen=true")
            try {
                context.startActivity(launchIntent)
            } catch (e: Exception) {
                Log.e("DoorWidget", "Failed to start activity: ${e.message}")
            }
            // 清除时间戳以避免三击触发二次开门
            prefs.edit().putLong(LAST_CLICK_KEY, 0L).apply()
        } else {
            // 记录单次点击时间戳，等待可能的第二次点击
            prefs.edit().putLong(LAST_CLICK_KEY, now).apply()
        }
    }

    /**
     * 触发振动反馈，保持与 Flutter 面板双击交互一致。
     */
    private fun triggerHapticFeedback(context: Context) {
        try {
            val vibrator: Vibrator? = when {
                // Android 12 (API 31) 及以上使用 VibratorManager
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
                    val vibratorManager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                    vibratorManager?.defaultVibrator
                }
                // Android 10-11 使用传统方式
                else -> {
                    @Suppress("DEPRECATION")
                    context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                }
            }

            if (vibrator == null) {
                Log.w("DoorWidget", "Vibrator not available")
                return
            }

            // 检查设备是否支持振动
            @Suppress("DEPRECATION")
            if (!vibrator.hasVibrator()) {
                Log.w("DoorWidget", "Device does not have vibrator")
                return
            }

            // 执行振动 - 使用较短的振动时间（60ms）和中等强度
            when {
                // Android 10+ (API 29+) 使用 VibrationEffect.createOneShot
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> {
                    // 使用 EFFECT_CLICK 效果更适合触觉反馈，兼容性更好
                    val effect = VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK)
                    vibrator.vibrate(effect)
                    Log.d("DoorWidget", "Haptic feedback triggered using EFFECT_CLICK")
                }
                // Android 8-9 (API 26-28) 使用 createOneShot
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> {
                    val effect = VibrationEffect.createOneShot(60, VibrationEffect.DEFAULT_AMPLITUDE)
                    vibrator.vibrate(effect)
                    Log.d("DoorWidget", "Haptic feedback triggered using createOneShot")
                }
                // Android 7 及以下（虽然不在目标范围，但保留兼容性）
                else -> {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(60)
                    Log.d("DoorWidget", "Haptic feedback triggered using legacy vibrate")
                }
            }
        } catch (e: Exception) {
            Log.e("DoorWidget", "Failed to trigger haptic feedback: ${e.message}")
        }
    }
}
