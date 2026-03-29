package com.lulo.dormdevise

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper

/**
 * 品牌启动页：先完整展示带文字 Logo，再无动画切入 Flutter 页面。
 *
 * 举措：使用主线程 Handler 调度并在 onDestroy 中清理回调，
 * 确保在不同 Android 版本上行为一致且无泄露。
 */
class SplashActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())

    private val switchRunnable = Runnable {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = intent?.action
            data = intent?.data
            intent?.extras?.let(::putExtras)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(launchIntent)
        finish()
        overridePendingTransition(0, 0)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_splash)

        // 最小展示时长（毫秒），设置为 1200ms
        val minSplashMs = 1200L
        val startTime = System.currentTimeMillis()

        // 等待首帧布局可见后再计算并调度跳转，避免出现白屏
        window.decorView.post {
            val elapsed = System.currentTimeMillis() - startTime
            val delay = if (elapsed >= minSplashMs) 0L else minSplashMs - elapsed
            handler.postDelayed(switchRunnable, delay)
        }
    }

    override fun onDestroy() {
        handler.removeCallbacks(switchRunnable)
        super.onDestroy()
    }
}
