package com.lulo.dormdevise

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent

/**
 * 接收桌面微件添加成功的回调。
 * 当用户在系统 widget 选择器中点击"添加到主屏幕"后触发。
 */
class DoorWidgetPinReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val providerClass = DoorWidgetPinRequestHelper.resolveProviderClass(
            intent?.getStringExtra(DoorWidgetPinRequestHelper.extraProviderClassName),
        ) ?: DoorWidgetProvider::class.java

        val appWidgetManager = AppWidgetManager.getInstance(context)
        val widgetIds = resolveWidgetIds(context, intent, appWidgetManager, providerClass)
        if (widgetIds.isNotEmpty()) {
            val updateIntent = Intent(context, providerClass).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, widgetIds)
            }
            context.sendBroadcast(updateIntent)
        }

        DoorWidgetPinRequestHelper.returnToHomeScreen(context)
    }

    private fun resolveWidgetIds(
        context: Context,
        intent: Intent?,
        appWidgetManager: AppWidgetManager,
        providerClass: Class<out AppWidgetProvider>,
    ): IntArray {
        val widgetId = intent?.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (widgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
            return intArrayOf(widgetId)
        }
        return appWidgetManager.getAppWidgetIds(ComponentName(context, providerClass))
    }
}
