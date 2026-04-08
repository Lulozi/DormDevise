package com.lulo.dormdevise

import android.app.Activity
import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import android.os.Bundle
import android.util.Log

/**
 * 桌面微件点击后的路由分发 Activity，根据配置情况决定后续流程。
 */
class DoorWidgetRouterActivity : Activity() {
    companion object {
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val PENDING_AUTO_OPEN = "door_widget_pending_auto_open"
        private const val PROMPT_ENGINE_ID = "door_widget_prompt_engine"
    }

    /**
    * 根据当前配置判断启动浮层还是跳转设置页面。
    */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // 完全透明，避免任何界面闪烁
        window.decorView.setBackgroundColor(android.graphics.Color.TRANSPARENT)
        window.setBackgroundDrawableResource(android.R.color.transparent)
        
        val launchData = intent?.data
        if (DoorWidgetPromptActivity.isActive()) {
            finish()
            return
        }
        
        val directOpen = intent?.getBooleanExtra("directOpen", false) ?: false
        Log.d("DoorWidget", "RouterActivity directOpen=$directOpen")
        
        if (directOpen) {
            // 仅在热引擎场景直接调用 performAutoOpen；冷启动场景交给 pending 标志兜底。
            try {
                val warmEngine: FlutterEngine? = FlutterEngineCache.getInstance().get(PROMPT_ENGINE_ID)
                if (warmEngine != null) {
                    val channel = MethodChannel(warmEngine.dartExecutor.binaryMessenger, "door_widget/prompt")
                    channel.invokeMethod("performAutoOpen", null, object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            clearPendingAutoOpenFlag()
                            Log.d("DoorWidget", "directOpen: performAutoOpen consumed by warm engine")
                        }

                        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                            Log.w("DoorWidget", "directOpen invoke error: $errorCode, $errorMessage")
                        }

                        override fun notImplemented() {
                            Log.w("DoorWidget", "directOpen invoke notImplemented")
                        }
                    })
                    Log.d("DoorWidget", "directOpen: invoked on warm engine")
                } else {
                    Log.d("DoorWidget", "directOpen: cold engine fallback via pending flag")
                    DoorWidgetPromptActivity.ensureEngine(applicationContext)
                }
            } catch (t: Throwable) {
                Log.w("DoorWidget", "directOpen invoke failed: ${t.message}")
            }
            finish()
            return
        }
        
        // 非直接开门模式，显示浮层界面
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

        Log.d("DoorWidget", "RouterActivity forwarding to PromptActivity showOnLock=$showOnLock turnOn=$turnOn")
        val promptIntent = Intent(this, DoorWidgetPromptActivity::class.java).apply {
            data = launchData
            putExtra("showOnLock", showOnLock)
            putExtra("turnScreenOn", turnOn)
            putExtra("directOpen", false)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        }
        startActivity(promptIntent)
        finish()
    }

    private fun clearPendingAutoOpenFlag() {
        try {
            getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(PENDING_AUTO_OPEN, false)
                .apply()
        } catch (_: Exception) {
            // ignore
        }
    }
}
