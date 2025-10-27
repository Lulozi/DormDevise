package com.lulo.dormdevise

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle

/**
 * 桌面微件点击后的路由分发 Activity，根据配置情况决定后续流程。
 */
class DoorWidgetRouterActivity : Activity() {

  /**
   * 根据当前配置判断启动浮层还是跳转设置页面。
   */
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val launchData = intent?.data
    if (isMqttConfigured()) {
      DoorWidgetPromptActivity.ensureEngine(applicationContext)
      val promptIntent = Intent(this, DoorWidgetPromptActivity::class.java).apply {
        data = launchData
      }
      startActivity(promptIntent)
    } else {
      val settingsIntent = Intent(this, MainActivity::class.java).apply {
        putExtra("route", "open_door_settings/mqtt")
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        data = launchData
      }
      startActivity(settingsIntent)
    }
    finish()
  }

  /**
   * 判断用户是否配置了必要的 MQTT 主机与主题。
   */
  /**
   * 读取 SharedPreferences 判断 MQTT 必要参数是否存在。
   */
  private fun isMqttConfigured(): Boolean {
    val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
    val host = prefs.getString("flutter.mqtt_host", "")?.trim().orEmpty()
    val topic = prefs.getString("flutter.mqtt_topic", "")?.trim().orEmpty()
    return host.isNotEmpty() && topic.isNotEmpty()
  }
}
