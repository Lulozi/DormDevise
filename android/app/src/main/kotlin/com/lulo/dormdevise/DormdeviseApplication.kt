package com.lulo.dormdevise

import android.app.Application

/**
 * 自定义 Application，用于在进程启动时预热桌面微件专用 Flutter 引擎，减少冷启动时间。
 */
class DormdeviseApplication : Application() {

    /**
     * 进程创建时即预热微件引擎，尽量维持在后台缓存。
     */
    override fun onCreate() {
        super.onCreate()
        DoorWidgetPromptActivity.ensureEngine(this)
    }
}
