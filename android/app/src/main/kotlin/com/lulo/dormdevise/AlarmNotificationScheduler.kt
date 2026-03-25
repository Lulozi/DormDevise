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
 * 课程提醒调度器：使用 AlarmManager 调度通知，保证后台和进程回收后仍可由系统触发。
 */
object AlarmNotificationScheduler {
    internal const val ALARM_CHANNEL_ID = "course_alarm_channel_v5"
    internal const val NOTIFICATION_CHANNEL_ID = "course_notification_channel_v8"
    internal const val NOTIFICATION_SILENT_CHANNEL_ID = "course_notification_channel_v8_silent"
    private const val ALARM_CHANNEL_NAME = "课程闹钟"
    private const val ALARM_CHANNEL_DESC = "用于发送上课前的强提醒"
    private const val NOTIFICATION_CHANNEL_NAME = "课程消息提醒"
    private const val NOTIFICATION_CHANNEL_DESC = "用于发送课程弹窗提醒"
    private const val NOTIFICATION_SILENT_CHANNEL_NAME = "课程消息提醒（无振动）"
    private const val NOTIFICATION_SILENT_CHANNEL_DESC = "用于发送无振动的课程弹窗提醒"
    private const val PREF_NAME = "alarm_notifications_prefs"
    private const val KEY_IDS = "alarm_ids"

    /**
     * 取消所有已注册闹钟与通知。
     */
    fun cancelAll(context: Context) {
        val ids = loadIds(context)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        ids.forEach { id ->
            val pi = buildShowPendingIntent(context, id, null, null, null, null)
            alarmManager.cancel(pi)
        }
        saveIds(context, emptySet())
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancelAll()
    }

    /**
     * 立即展示课程提醒通知。
     */
    fun showNow(
        context: Context,
        id: Int,
        title: String,
        body: String,
        isAlarm: Boolean,
        enableVibration: Boolean,
    ) {
        ensureChannel(context, isAlarm, enableVibration)
        AlarmNotificationReceiver.showNotification(
            context = context,
            id = id,
            title = title,
            body = body,
            isAlarm = isAlarm,
            enableVibration = enableVibration
        )
    }

    /**
     * 调度指定时间的课程提醒通知。
     */
    fun schedule(
        context: Context,
        id: Int,
        triggerAtMillis: Long,
        title: String,
        body: String,
        isAlarm: Boolean,
        enableVibration: Boolean,
    ) {
        ensureChannel(context, isAlarm, enableVibration)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = buildShowPendingIntent(
            context = context,
            id = id,
            title = title,
            body = body,
            isAlarm = isAlarm,
            enableVibration = enableVibration
        )
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) AlarmManager.RTC_WAKEUP else AlarmManager.RTC
        if (isAlarm && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val showIntent = buildLaunchPendingIntent(context, id) ?: pi
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(triggerAtMillis, showIntent),
                pi
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
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

    private fun buildLaunchPendingIntent(
        context: Context,
        id: Int,
    ): PendingIntent? {
        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?: return null
        return PendingIntent.getActivity(
            context,
            id,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun buildShowPendingIntent(
        context: Context,
        id: Int,
        title: String?,
        body: String?,
        isAlarm: Boolean?,
        enableVibration: Boolean?,
    ): PendingIntent {
        val intent = Intent(context, AlarmNotificationReceiver::class.java).apply {
            action = AlarmNotificationReceiver.ACTION_SHOW
            putExtra(AlarmNotificationReceiver.EXTRA_ID, id)
            title?.let { putExtra(AlarmNotificationReceiver.EXTRA_TITLE, it) }
            body?.let { putExtra(AlarmNotificationReceiver.EXTRA_BODY, it) }
            isAlarm?.let { putExtra(AlarmNotificationReceiver.EXTRA_IS_ALARM, it) }
            enableVibration?.let {
                putExtra(AlarmNotificationReceiver.EXTRA_ENABLE_VIBRATION, it)
            }
        }
        return PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun ensureChannel(context: Context, isAlarm: Boolean, enableVibration: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (isAlarm) {
            val existing = manager.getNotificationChannel(ALARM_CHANNEL_ID)
            if (existing == null) {
                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .build()
                val channel = NotificationChannel(
                    ALARM_CHANNEL_ID,
                    ALARM_CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = ALARM_CHANNEL_DESC
                    enableLights(true)
                    enableVibration(true)
                    setSound(Settings.System.DEFAULT_ALARM_ALERT_URI, audioAttributes)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                }
                manager.createNotificationChannel(channel)
            }
            return
        }

        val channelId = if (enableVibration) {
            NOTIFICATION_CHANNEL_ID
        } else {
            NOTIFICATION_SILENT_CHANNEL_ID
        }
        if (manager.getNotificationChannel(channelId) != null) {
            return
        }

        val channel = NotificationChannel(
            channelId,
            if (enableVibration) NOTIFICATION_CHANNEL_NAME else NOTIFICATION_SILENT_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = if (enableVibration) {
                NOTIFICATION_CHANNEL_DESC
            } else {
                NOTIFICATION_SILENT_CHANNEL_DESC
            }
            enableLights(true)
            enableVibration(enableVibration)
            if (enableVibration) {
                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .build()
                setSound(Settings.System.DEFAULT_NOTIFICATION_URI, audioAttributes)
            } else {
                setSound(null, null)
            }
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
