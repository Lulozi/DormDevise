package com.lulo.dormdevise

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.app.PendingIntent
import android.content.Intent
import android.os.Bundle
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 简洁版门锁桌面组件 (1x1)，只显示门锁图标和设备在线/离线状态。
 */
class DoorSimpleWidgetProvider : HomeWidgetProvider() {

    companion object {
        private const val PREFS_NAME = "door_simple_widget_pin_state"
        private const val KEY_PENDING_PIN = "pending_pin_request"

        /**
         * 标记正在进行 pin widget 请求，下次 widget 更新时返回桌面。
         */
        fun markPendingPinRequest(context: Context) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_PENDING_PIN, true)
                .apply()
        }

        /**
         * 检查并清除 pending pin 标记。
         */
        private fun checkAndClearPendingPin(context: Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val pending = prefs.getBoolean(KEY_PENDING_PIN, false)
            if (pending) {
                prefs.edit().putBoolean(KEY_PENDING_PIN, false).apply()
            }
            return pending
        }

        /**
         * 返回主屏幕。
         */
        private fun returnToHomeScreen(context: Context) {
            try {
                val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
                    )
                }
                context.startActivity(homeIntent)
            } catch (_: Exception) {
                // 静默处理
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        // 预热 Flutter 引擎
        try {
            DoorWidgetPromptActivity.ensureEngine(context.applicationContext)
        } catch (_: Exception) {}

        // 清除 pending pin 标记（不主动返回桌面，让系统处理）
        checkAndClearPendingPin(context)

        appWidgetIds.forEach { widgetId ->
            try {
                val views = RemoteViews(context.packageName, R.layout.widget_door_simple)

                // 读取状态数据
                val doorStatus = widgetData.getInt("door_widget_door_lock_status", 0) // 0=pending, 1=success, 2=failed
                // 更新门锁图标（解锁/锁定状态）
                val iconRes = if (doorStatus == 1) {
                    R.drawable.ic_lock_open
                } else {
                    R.drawable.ic_lock_outline
                }
                views.setImageViewResource(R.id.door_widget_simple_icon, iconRes)
                
                // 图标颜色
                val iconTint = when (doorStatus) {
                    1 -> ContextCompat.getColor(context, R.color.widget_success)
                    2 -> ContextCompat.getColor(context, R.color.widget_error)
                    else -> ContextCompat.getColor(context, R.color.widget_text)
                }
                views.setInt(R.id.door_widget_simple_icon, "setColorFilter", iconTint)

                // 点击事件
                val clickIntent = Intent(context, DoorWidgetClickReceiver::class.java).apply {
                    action = "com.lulo.dormdevise.DOOR_WIDGET_CLICK"
                }
                val pending = PendingIntent.getBroadcast(
                    context,
                    widgetId + 10000,
                    clickIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.door_widget_simple_root, pending)
                views.setOnClickPendingIntent(R.id.door_widget_simple_icon, pending)

                appWidgetManager.updateAppWidget(widgetId, views)
            } catch (e: Exception) {
                android.util.Log.e("DoorSimpleWidgetProvider", "Widget update failed: ${e.message}", e)
            }
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        onUpdate(
            context = context,
            appWidgetManager = appWidgetManager,
            appWidgetIds = intArrayOf(appWidgetId),
            widgetData = HomeWidgetPlugin.getData(context),
        )
    }
}
