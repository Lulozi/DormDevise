package com.lulo.dormdevise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.Toast
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
        private const val PENDING_AUTO_OPEN = "door_widget_pending_auto_open"
        private const val DOUBLE_TAP_WINDOW_MS = 600L
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_WIDGET_CLICK) return

        val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val last = prefs.getLong(LAST_CLICK_KEY, 0L)
        val now = System.currentTimeMillis()
        if (now - last <= DOUBLE_TAP_WINDOW_MS) {
            // 双击：尽量直接触发开门（通过传递 directOpen 标志给路由 Activity，Router->Prompt 会在预热引擎后触发 Dart 执行开门）
            // 同时保留 pending 标志作为兜底（若 native->Dart 协商失败，Flutter 端仍会读取并处理）
            prefs.edit().putBoolean(PENDING_AUTO_OPEN, true).apply()
            val launchIntent = Intent(context, DoorWidgetRouterActivity::class.java).apply {
                putExtra("directOpen", true)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            }
            Log.d("DoorWidget", "Double-tap detected, launching router with directOpen=true")
            try {
                context.startActivity(launchIntent)
            } catch (e: Exception) {
                Toast.makeText(context, "正在尝试开门...", Toast.LENGTH_SHORT).show()
            }
            // 清除时间戳以避免三击触发二次开门
            prefs.edit().putLong(LAST_CLICK_KEY, 0L).apply()
        } else {
            // 记录单次点击时间戳，等待可能的第二次点击
            prefs.edit().putLong(LAST_CLICK_KEY, now).apply()
        }
    }
}
