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
        if (DoorWidgetPromptActivity.isActive()) {
            finish()
            return
        }
        DoorWidgetPromptActivity.ensureEngine(applicationContext)
        val promptIntent = Intent(this, DoorWidgetPromptActivity::class.java).apply {
            data = launchData
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        }
        startActivity(promptIntent)
        finish()
    }
}
