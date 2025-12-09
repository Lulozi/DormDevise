package com.lulo.dormdevise

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.os.Build
import android.provider.Settings

/**
 * 闹钟通知调度器：使用 AlarmManager 调度自定义 RemoteViews 闹钟，保证按钮布局可控。
 */
object AlarmNotificationScheduler {
    internal const val CHANNEL_ID = "course_alarm_channel_v4"
    private const val CHANNEL_NAME = "课程闹钟"
    private const val CHANNEL_DESC = "用于发送上课前的强提醒"
    private const val PREF_NAME = "alarm_notifications_prefs"
    private const val KEY_IDS = "alarm_ids"

    /**
     * 取消所有已注册闹钟与通知。
     */
    fun cancelAll(context: Context) {
        val ids = loadIds(context)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        ids.forEach { id ->
            val pi = buildShowPendingIntent(context, id, null, null, null)
            alarmManager.cancel(pi)
        }
        saveIds(context, emptySet())
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancelAll()
    }

    /**
     * 立即展示闹钟通知。
     */
    fun showNow(
        context: Context,
        id: Int,
        course: String,
        location: String,
        minutes: Int,
    ) {
        ensureChannel(context)
        AlarmNotificationReceiver.showNotification(context, id, course, location, minutes)
    }

    /**
     * 调度指定时间的闹钟通知。
     */
    fun schedule(
        context: Context,
        id: Int,
        triggerAtMillis: Long,
        course: String,
        location: String,
        minutes: Int,
    ) {
        ensureChannel(context)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = buildShowPendingIntent(context, id, course, location, minutes)
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) AlarmManager.RTC_WAKEUP else AlarmManager.RTC
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(mode, triggerAtMillis, pi)
        } else {
            alarmManager.setExact(mode, triggerAtMillis, pi)
        }
        rememberId(context, id)
    }

    internal fun buildDismissPendingIntent(context: Context, id: Int): PendingIntent {
        val dismissIntent = Intent(context, AlarmNotificationReceiver::class.java).apply {
            action = AlarmNotificationReceiver.ACTION_DISMISS
            putExtra(AlarmNotificationReceiver.EXTRA_ID, id)
        }
        return PendingIntent.getBroadcast(
            context,
            id,
            dismissIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun buildShowPendingIntent(
        context: Context,
        id: Int,
        course: String?,
        location: String?,
        minutes: Int?,
    ): PendingIntent {
        val intent = Intent(context, AlarmNotificationReceiver::class.java).apply {
            action = AlarmNotificationReceiver.ACTION_SHOW
            putExtra(AlarmNotificationReceiver.EXTRA_ID, id)
            course?.let { putExtra(AlarmNotificationReceiver.EXTRA_COURSE, it) }
            location?.let { putExtra(AlarmNotificationReceiver.EXTRA_LOCATION, it) }
            minutes?.let { putExtra(AlarmNotificationReceiver.EXTRA_MINUTES, it) }
        }
        return PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .build()
        val channel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH).apply {
            description = CHANNEL_DESC
            enableLights(true)
            enableVibration(true)
            setSound(Settings.System.DEFAULT_ALARM_ALERT_URI, audioAttributes)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun rememberId(context: Context, id: Int) {
        val ids = loadIds(context).toMutableSet()
        ids.add(id)
        saveIds(context, ids)
    }

    internal fun removeId(context: Context, id: Int) {
        val ids = loadIds(context).toMutableSet()
        ids.remove(id)
        saveIds(context, ids)
    }

    private fun loadIds(context: Context): Set<Int> {
        val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        val stored = prefs.getStringSet(KEY_IDS, emptySet()) ?: emptySet()
        return stored.mapNotNull { it.toIntOrNull() }.toSet()
    }

    private fun saveIds(context: Context, ids: Set<Int>) {
        val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        prefs.edit().putStringSet(KEY_IDS, ids.map { it.toString() }.toSet()).apply()
    }

    // Expose a helper to retrieve scheduled alarm IDs for Dart to query
    fun getScheduledIds(context: Context): List<Int> {
        return loadIds(context).toList()
    }
}
