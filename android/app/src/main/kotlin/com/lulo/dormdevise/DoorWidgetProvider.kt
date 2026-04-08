package com.lulo.dormdevise

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
import android.app.PendingIntent
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 负责渲染 Android 桌面微件的提供者，通过 HomeWidget 框架读取共享数据并更新 RemoteViews。
 */
class DoorWidgetProvider : HomeWidgetProvider() {

  companion object {
    private const val PREFS_NAME = "door_widget_pin_state"
    private const val KEY_PENDING_PIN = "pending_pin_request"
    
    // 闪烁控制
    private var blinkHandler: Handler? = null
    private var blinkRunnable: Runnable? = null
    private var isBlinkVisible = true

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
     * 获取动态主题背景色（Material You 风格）
     */
    private fun getDynamicBackgroundColor(context: Context): Int {
      return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        // Android 12+ 使用动态颜色
        val isDarkMode = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        if (isDarkMode) {
          context.getColor(android.R.color.system_accent1_800)
        } else {
          context.getColor(android.R.color.system_accent1_100)
        }
      } else {
        // 低版本使用浅绿色作为备用
        Color.parseColor("#E8F5E9")
      }
    }
  }

  /**
   * 系统请求更新时，根据共享数据刷新每个微件实例的界面。
   */
  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
    widgetData: SharedPreferences,
  ) {
    // 清除 pending pin 标记（不主动返回桌面，让系统处理）
    checkAndClearPendingPin(context)

    // 后台预热 Flutter 引擎
    try {
      DoorWidgetPromptActivity.ensureEngine(context.applicationContext)
    } catch (_: Exception) {}

    appWidgetIds.forEach { widgetId ->
      try {
        val compactLayout = shouldUseCompactLayout(appWidgetManager, widgetId)
        val views = RemoteViews(
          context.packageName,
          if (compactLayout) R.layout.widget_door_compact else R.layout.widget_door,
        )

        val busy = widgetData.getBoolean("door_widget_busy", false)

        // 读取状态数据
        val doorStatus = widgetData.getInt("door_widget_door_lock_status", 0) // 0=pending, 1=success, 2=failed
        val deviceStatus = widgetData.getInt("door_widget_device_status", 1) // 0=online, 1=offline, 2=abnormal
        val wifiStatus = widgetData.getInt("door_widget_wifi_status", 1) // 0=connected, 1=disconnected, 2=unconfigured
        val mqttConnStatus = widgetData.getInt("door_widget_mqtt_connection_status", 1) // 0=connected, 1=disconnected, 2=failed
        val mqttSubStatus = widgetData.getInt("door_widget_mqtt_subscription_status", 1) // 0=subscribed, 1=unsubscribed

        // 更新设备状态
        val (deviceText, deviceBg, deviceColor) = when (deviceStatus) {
          0 -> Triple("设备在线", R.drawable.widget_chip_green, R.color.widget_success)
          2 -> Triple("设备异常", R.drawable.widget_chip_yellow, R.color.widget_warning)
          else -> Triple("设备离线", R.drawable.widget_chip_gray, R.color.widget_gray)
        }
        views.setTextViewText(R.id.door_widget_device_status, deviceText)
        views.setInt(R.id.door_widget_device_status, "setBackgroundResource", deviceBg)
        views.setTextColor(R.id.door_widget_device_status, ContextCompat.getColor(context, deviceColor))

        if (!compactLayout) {
          // 更新门锁状态
          val (doorText, doorBg, doorColor) = when {
            busy -> Triple("正在开门...", R.drawable.widget_chip_gray, R.color.widget_gray)
            doorStatus == 1 -> Triple("开门成功", R.drawable.widget_chip_green, R.color.widget_success)
            doorStatus == 2 -> Triple("开门失败", R.drawable.widget_chip_red, R.color.widget_error)
            else -> Triple("待开门", R.drawable.widget_chip_gray, R.color.widget_gray)
          }
          views.setTextViewText(R.id.door_widget_door_status, doorText)
          views.setInt(R.id.door_widget_door_status, "setBackgroundResource", doorBg)
          views.setTextColor(R.id.door_widget_door_status, ContextCompat.getColor(context, doorColor))

          // 更新WiFi状态
          val (wifiText, wifiBg, wifiColor) = when (wifiStatus) {
            0 -> Triple("WiFi：已连接", R.drawable.widget_chip_green, R.color.widget_success)
            2 -> Triple("WiFi：非配置", R.drawable.widget_chip_yellow, R.color.widget_warning)
            else -> Triple("WiFi：未连接", R.drawable.widget_chip_gray, R.color.widget_gray)
          }
          views.setTextViewText(R.id.door_widget_wifi_status, wifiText)
          views.setInt(R.id.door_widget_wifi_status, "setBackgroundResource", wifiBg)
          views.setTextColor(R.id.door_widget_wifi_status, ContextCompat.getColor(context, wifiColor))

          // 更新 MQTT 状态显示优先级：连接失败 > 未订阅 > 已连接 > 未连接
          val isMqttConnected = mqttConnStatus == 0
          val isMqttFailed = mqttConnStatus == 2
          val isMqttSubscribed = mqttSubStatus == 0
          val (mqttText, mqttBg, mqttColor) = when {
            isMqttFailed -> Triple("MQTT：连接失败", R.drawable.widget_chip_red, R.color.widget_error)
            !isMqttSubscribed -> Triple("MQTT：未订阅", R.drawable.widget_chip_yellow, R.color.widget_warning)
            isMqttConnected -> Triple("MQTT：已连接", R.drawable.widget_chip_green, R.color.widget_success)
            else -> Triple("MQTT：未连接", R.drawable.widget_chip_gray, R.color.widget_gray)
          }
          views.setTextViewText(R.id.door_widget_mqtt_status, mqttText)
          views.setInt(R.id.door_widget_mqtt_status, "setBackgroundResource", mqttBg)
          views.setTextColor(R.id.door_widget_mqtt_status, ContextCompat.getColor(context, mqttColor))
        }

        // 更新门锁图标
        val iconRes = if (doorStatus == 1) {
          R.drawable.ic_lock_open
        } else {
          R.drawable.ic_lock_outline
        }
        views.setImageViewResource(R.id.door_widget_icon, iconRes)
        
        // 图标颜色
        val iconTint = when (doorStatus) {
          1 -> ContextCompat.getColor(context, R.color.widget_success)
          2 -> ContextCompat.getColor(context, R.color.widget_error)
          else -> ContextCompat.getColor(context, R.color.widget_text)
        }
        views.setInt(R.id.door_widget_icon, "setColorFilter", iconTint)

        // 点击事件
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

        appWidgetManager.updateAppWidget(widgetId, views)
        
        // 停止闪烁（静默处理异常）
        try {
          stopBlinking()
        } catch (_: Exception) {}
      } catch (e: Exception) {
        android.util.Log.e("DoorWidgetProvider", "Widget update failed: ${e.message}", e)
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
  
  /**
   * 启动闪烁效果
   */
  private fun startBlinking(
    context: Context,
    appWidgetManager: AppWidgetManager,
    widgetId: Int,
    widgetData: SharedPreferences
  ) {
    // 如果已经在闪烁，不重复启动
    if (blinkHandler != null) return
    
    blinkHandler = Handler(Looper.getMainLooper())
    blinkRunnable = object : Runnable {
      override fun run() {
        isBlinkVisible = !isBlinkVisible
        updateBlinkState(context, appWidgetManager, widgetId, widgetData, isBlinkVisible)
        blinkHandler?.postDelayed(this, 500) // 500ms 闪烁间隔
      }
    }
    blinkHandler?.post(blinkRunnable!!)
  }
  
  /**
   * 停止闪烁效果
   */
  private fun stopBlinking() {
    blinkRunnable?.let { blinkHandler?.removeCallbacks(it) }
    blinkHandler = null
    blinkRunnable = null
    isBlinkVisible = true
  }

  private fun shouldUseCompactLayout(
    appWidgetManager: AppWidgetManager,
    widgetId: Int,
  ): Boolean {
    val options = appWidgetManager.getAppWidgetOptions(widgetId)
    val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
    val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
    return minWidth in 1..84 && minHeight in 1..84
  }
  
  /**
   * 更新闪烁状态
   */
  private fun updateBlinkState(
    context: Context,
    appWidgetManager: AppWidgetManager,
    widgetId: Int,
    widgetData: SharedPreferences,
    visible: Boolean
  ) {
    val views = RemoteViews(context.packageName, R.layout.widget_door)
    
    val doorStatus = widgetData.getInt("door_widget_door_lock_status", 0)
    val wifiStatus = widgetData.getInt("door_widget_wifi_status", 1)
    
    // 根据可见性设置透明度
    val alpha = if (visible) 1.0f else 0.3f
    
    // 开门失败时闪烁门锁状态
    if (doorStatus == 2) {
      views.setFloat(R.id.door_widget_door_status, "setAlpha", alpha)
    }
    
    // WiFi问题时闪烁WiFi状态
    if (wifiStatus == 1 || wifiStatus == 2) {
      views.setFloat(R.id.door_widget_wifi_status, "setAlpha", alpha)
    }
    
    appWidgetManager.partiallyUpdateAppWidget(widgetId, views)
  }
}
