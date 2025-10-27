package com.lulo.dormdevise

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * 桌面微件专用入口 Activity，使用预热 Flutter 引擎加载底部浮层界面。
 */
class DoorWidgetPromptActivity : FlutterActivity() {

    companion object {
        private const val ENGINE_ID = "door_widget_prompt_engine"

        /**
         * 预热并缓存专用 Flutter 引擎，加速后续启动。
         */
        fun ensureEngine(context: Context) {
            val cache = FlutterEngineCache.getInstance()
            if (cache.contains(ENGINE_ID)) return
            val engine = FlutterEngine(context.applicationContext)
            engine.navigationChannel.setInitialRoute("door_widget_prompt")
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault(),
            )
            cache.put(ENGINE_ID, engine)
        }
    }

    private var methodChannel: MethodChannel? = null

    /**
     * 配置透明窗口并完成父类初始化。
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.setBackgroundDrawableResource(android.R.color.transparent)
        super.onCreate(savedInstanceState)
    }

    /**
     * 绑定 MethodChannel，接收 Flutter 端关闭或跳转指令。
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "door_widget/prompt")
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "close" -> {
                    moveTaskToBackground()
                    result.success(null)
                }
                "openSettings" -> {
                    launchMqttSettings()
                    finish()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Activity 销毁时解除 MethodChannel 监听，避免内存泄漏。
     */
    override fun onDestroy() {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        super.onDestroy()
    }

    /**
     * 提供预热后的缓存引擎以缩短启动时间。
     */
    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        ensureEngine(context)
        return FlutterEngineCache.getInstance().get(ENGINE_ID)
    }

    /**
     * 保留 Flutter 引擎供下次快速复用。
     */
    override fun shouldDestroyEngineWithHost(): Boolean = false

    /**
     * 使用纹理渲染确保透明背景生效。
     */
    override fun getRenderMode(): RenderMode = RenderMode.texture

    /**
     * 设置完全透明的渲染模式。
     */
    override fun getTransparencyMode(): TransparencyMode = TransparencyMode.transparent

    /**
     * 收到关闭指令时将任务移至后台，尽量保持进程常驻。
     */
    private fun moveTaskToBackground() {
        moveTaskToBack(true)
    }

    /**
     * 从微件入口直接跳转到应用内 MQTT 设置页。
     */
    private fun launchMqttSettings() {
        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra("route", "open_door_settings/mqtt")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        startActivity(intent)
    }
}
