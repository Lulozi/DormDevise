package com.lulo.dormdevise

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 负责渲染 Android 桌面微件的提供者，通过 HomeWidget 框架读取共享数据并更新 RemoteViews。
 */
class DoorWidgetProvider : HomeWidgetProvider() {

  /**
   * 系统请求更新时，根据共享数据刷新每个微件实例的界面。
   */
  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
    widgetData: SharedPreferences,
  ) {
    appWidgetIds.forEach { widgetId ->
      val views = RemoteViews(context.packageName, R.layout.widget_door)

      val busy = widgetData.getBoolean("door_widget_busy", false)
      val showLastResult = widgetData.getBoolean("door_widget_setting_show_result", true)
      val message = widgetData.getString(
        "door_widget_message",
        context.getString(R.string.door_widget_default_message)
      )
      val rawSuccess = widgetData.getAll()["door_widget_last_success"]
      val success = when (rawSuccess) {
        is Boolean -> rawSuccess
        else -> null
      }
      val effectiveMessage = if (showLastResult) message else context.getString(R.string.door_widget_default_message)
      views.setTextViewText(
        R.id.door_widget_status,
        effectiveMessage ?: context.getString(R.string.door_widget_default_message)
      )

      val statusColor = when {
        busy -> ContextCompat.getColor(context, R.color.widget_text)
        success == true -> ContextCompat.getColor(context, R.color.widget_success)
        success == false -> ContextCompat.getColor(context, R.color.widget_error)
        else -> ContextCompat.getColor(context, R.color.widget_text)
      }
      views.setTextColor(R.id.door_widget_status, statusColor)

      // 使用广播接收器实现点击逻辑（支持双击识别），由 DoorWidgetClickReceiver 处理双击并触发开门。
      val clickIntent = Intent(context, DoorWidgetClickReceiver::class.java).apply {
        action = "com.lulo.dormdevise.DOOR_WIDGET_CLICK"
      }
      val pending = PendingIntent.getBroadcast(
        context,
        widgetId,
        clickIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
      )
      views.setOnClickPendingIntent(R.id.door_widget_root, pending)
      views.setOnClickPendingIntent(R.id.door_widget_icon, pending)

      val iconTint = ContextCompat.getColor(context, R.color.widget_text)
      views.setInt(R.id.door_widget_icon, "setColorFilter", iconTint)
      views.setTextViewText(
        R.id.door_widget_label,
        context.getString(R.string.door_widget_action_label)
      )
      views.setTextColor(R.id.door_widget_label, iconTint)

      val hintColor = ContextCompat.getColor(context, R.color.widget_text_secondary)
      if (!busy && success == null) {
        views.setTextColor(R.id.door_widget_status, hintColor)
      }

      // 占位：HTTP/MQTT 状态显示由 Flutter 侧合并到主消息 `door_widget_message`，以保证兼容性。

      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }
}
