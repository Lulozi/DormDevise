package com.lulo.dormdevise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 系统重启、应用更新后恢复课程提醒，避免 AlarmManager 注册项丢失。
 */
class AlarmRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        AlarmNotificationScheduler.restoreAll(context.applicationContext)
        CourseScheduleWidgetProvider.refreshAllWidgets(context.applicationContext)
    }
}
