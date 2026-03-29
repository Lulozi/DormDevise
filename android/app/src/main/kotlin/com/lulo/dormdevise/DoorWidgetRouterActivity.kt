package com.lulo.dormdevise

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import android.os.Bundle
import android.os.Build
import android.view.WindowManager
import org.json.JSONObject
import android.util.Log

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
        if (DoorWidgetPromptActivity.isActive()) {
            finish()
            return
        }
        DoorWidgetPromptActivity.ensureEngine(applicationContext)
        // 优先从 URI 查询参数读取控制开关，其次回退到 FlutterSharedPreferences 中的配置项
        val showOnLockFromUri = launchData?.getQueryParameter("showOnLock")
        val turnOnFromUri = launchData?.getQueryParameter("turnScreenOn")

        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val showOnLock = when {
            !showOnLockFromUri.isNullOrEmpty() -> (showOnLockFromUri == "1" || showOnLockFromUri.equals("true", true))
            else -> prefs.getBoolean("door_widget_setting_allow_show_on_lock", false)
        }
        val turnOn = when {
            !turnOnFromUri.isNullOrEmpty() -> (turnOnFromUri == "1" || turnOnFromUri.equals("true", true))
            else -> prefs.getBoolean("door_widget_setting_allow_turn_screen_on", false)
        }

        val directOpen = intent?.getBooleanExtra("directOpen", false) ?: false
        Log.d("DoorWidget", "RouterActivity forwarding to PromptActivity directOpen=$directOpen showOnLock=$showOnLock turnOn=$turnOn")
        if (directOpen) {
            // 直接在后台引擎上调用 performAutoOpen，避免展示 UI
            try {
                DoorWidgetPromptActivity.ensureEngine(applicationContext)
                val engine: FlutterEngine? = FlutterEngineCache.getInstance().get("door_widget_prompt_engine")
                if (engine != null) {
                    val ch = MethodChannel(engine.dartExecutor.binaryMessenger, "door_widget/prompt")
                    ch.invokeMethod("performAutoOpen", null)
                }
            } catch (t: Throwable) {
                Log.w("DoorWidget", "directOpen invoke failed: ${t.message}")
            }
            finish()
            return
        } else {
            val promptIntent = Intent(this, DoorWidgetPromptActivity::class.java).apply {
                data = launchData
                putExtra("showOnLock", showOnLock)
                putExtra("turnScreenOn", turnOn)
                putExtra("directOpen", directOpen)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            }
            startActivity(promptIntent)
        }
        finish()
    }
}
