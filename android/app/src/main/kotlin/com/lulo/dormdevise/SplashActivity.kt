package com.lulo.dormdevise

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * 品牌启动页：先完整展示带文字 Logo，再无动画切入 Flutter 页面。
 */
class SplashActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_splash)

        window.decorView.post {
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
    }
}
