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
import org.json.JSONArray
import org.json.JSONObject

/**
 * 课程提醒调度器：使用 AlarmManager 调度通知，保证后台和进程回收后仍可由系统触发。
 */
object AlarmNotificationScheduler {
    internal const val ALARM_CHANNEL_ID = "course_alarm_channel_v6"
    internal const val NOTIFICATION_CHANNEL_ID = "course_notification_channel_v8"
    internal const val NOTIFICATION_SILENT_CHANNEL_ID = "course_notification_channel_v8_silent"
    private const val ALARM_CHANNEL_NAME = "课程闹钟"
    private const val ALARM_CHANNEL_DESC = "用于发送上课前的强提醒，遵循系统闹钟铃声与提醒设置"
    private const val NOTIFICATION_CHANNEL_NAME = "课程消息提醒"
    private const val NOTIFICATION_CHANNEL_DESC = "用于发送课程弹窗提醒"
    private const val NOTIFICATION_SILENT_CHANNEL_NAME = "课程消息提醒（无振动）"
    private const val NOTIFICATION_SILENT_CHANNEL_DESC = "用于发送无振动的课程弹窗提醒"
    private const val PREF_NAME = "alarm_notifications_prefs"
    private const val KEY_REMINDERS = "scheduled_reminders"
    private const val RECENT_OVERDUE_WINDOW_MILLIS = 2 * 60 * 1000L

    private data class ScheduledReminder(
        val id: Int,
        val triggerAtMillis: Long,
        val title: String,
        val body: String,
        val isAlarm: Boolean,
        val enableVibration: Boolean,
    ) {
        fun toJson(): JSONObject = JSONObject()
            .put("id", id)
            .put("triggerAtMillis", triggerAtMillis)
            .put("title", title)
            .put("body", body)
            .put("isAlarm", isAlarm)
            .put("enableVibration", enableVibration)

        companion object {
            fun fromJson(json: JSONObject): ScheduledReminder? {
                val id = json.optInt("id", Int.MIN_VALUE)
                val triggerAtMillis = json.optLong("triggerAtMillis", Long.MIN_VALUE)
                if (id == Int.MIN_VALUE || triggerAtMillis == Long.MIN_VALUE) {
                    return null
                }
                return ScheduledReminder(
                    id = id,
                    triggerAtMillis = triggerAtMillis,
                    title = json.optString("title", "课程提醒"),
                    body = json.optString("body", ""),
                    isAlarm = json.optBoolean("isAlarm", false),
                    enableVibration = json.optBoolean("enableVibration", true),
                )
            }
        }
    }

    /**
     * 取消所有已注册闹钟与通知。
     */
    fun cancelAll(context: Context) {
        val reminders = loadReminders(context)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        reminders.forEach { reminder ->
            alarmManager.cancel(buildShowPendingIntent(context, reminder.id, null, null, null, null))
            manager.cancel(reminder.id)
        }
        saveReminders(context, emptyList())
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
        removeId(context, id)
        ensureChannel(context, isAlarm, enableVibration)
        AlarmNotificationReceiver.showNotification(
            context = context,
            id = id,
            title = title,
            body = body,
            isAlarm = isAlarm,
            enableVibration = enableVibration,
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
        val reminder = ScheduledReminder(
            id = id,
            triggerAtMillis = triggerAtMillis,
            title = title,
            body = body,
            isAlarm = isAlarm,
            enableVibration = enableVibration,
        )
        if (triggerAtMillis <= System.currentTimeMillis()) {
            showNow(context, id, title, body, isAlarm, enableVibration)
            return
        }
        scheduleReminder(context, reminder)
        rememberReminder(context, reminder)
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
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    internal fun restoreAll(context: Context) {
        val now = System.currentTimeMillis()
        val activeReminders = mutableListOf<ScheduledReminder>()
        loadReminders(context)
            .sortedBy { it.triggerAtMillis }
            .forEach { reminder ->
                when {
                    reminder.triggerAtMillis <= now - RECENT_OVERDUE_WINDOW_MILLIS -> Unit
                    reminder.triggerAtMillis <= now -> {
                        showNow(
                            context = context,
                            id = reminder.id,
                            title = reminder.title,
                            body = reminder.body,
                            isAlarm = reminder.isAlarm,
                            enableVibration = reminder.enableVibration,
                        )
                    }
                    else -> {
                        scheduleReminder(context, reminder)
                        activeReminders.add(reminder)
                    }
                }
            }
        saveReminders(context, activeReminders)
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
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
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
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun scheduleReminder(
        context: Context,
        reminder: ScheduledReminder,
    ) {
        ensureChannel(context, reminder.isAlarm, reminder.enableVibration)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = buildShowPendingIntent(
            context = context,
            id = reminder.id,
            title = reminder.title,
            body = reminder.body,
            isAlarm = reminder.isAlarm,
            enableVibration = reminder.enableVibration,
        )
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            AlarmManager.RTC_WAKEUP
        } else {
            AlarmManager.RTC
        }

        if (reminder.isAlarm && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val showIntent = buildLaunchPendingIntent(context, reminder.id) ?: pendingIntent
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(reminder.triggerAtMillis, showIntent),
                pendingIntent,
            )
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                !alarmManager.canScheduleExactAlarms()
            ) {
                scheduleBestEffort(alarmManager, mode, reminder.triggerAtMillis, pendingIntent)
                return
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(mode, reminder.triggerAtMillis, pendingIntent)
            } else {
                alarmManager.setExact(mode, reminder.triggerAtMillis, pendingIntent)
            }
        } catch (_: SecurityException) {
            scheduleBestEffort(alarmManager, mode, reminder.triggerAtMillis, pendingIntent)
        }
    }

    private fun scheduleBestEffort(
        alarmManager: AlarmManager,
        mode: Int,
        triggerAtMillis: Long,
        pendingIntent: PendingIntent,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(mode, triggerAtMillis, pendingIntent)
        } else {
            alarmManager.set(mode, triggerAtMillis, pendingIntent)
        }
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
                    NotificationManager.IMPORTANCE_HIGH,
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

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .build()
        val channel = NotificationChannel(
            channelId,
            if (enableVibration) NOTIFICATION_CHANNEL_NAME else NOTIFICATION_SILENT_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = if (enableVibration) {
                NOTIFICATION_CHANNEL_DESC
            } else {
                NOTIFICATION_SILENT_CHANNEL_DESC
            }
            enableLights(true)
            enableVibration(enableVibration)
            setSound(Settings.System.DEFAULT_NOTIFICATION_URI, audioAttributes)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun rememberReminder(context: Context, reminder: ScheduledReminder) {
        val reminders = loadReminders(context)
            .filterNot { it.id == reminder.id }
            .toMutableList()
        reminders.add(reminder)
        saveReminders(context, reminders)
    }

    internal fun removeId(context: Context, id: Int) {
        val reminders = loadReminders(context)
            .filterNot { it.id == id }
        saveReminders(context, reminders)
    }

    private fun loadReminders(context: Context): List<ScheduledReminder> {
        val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        val stored = prefs.getString(KEY_REMINDERS, null) ?: return emptyList()
        return try {
            val jsonArray = JSONArray(stored)
            buildList {
                for (index in 0 until jsonArray.length()) {
                    val jsonObject = jsonArray.optJSONObject(index) ?: continue
                    ScheduledReminder.fromJson(jsonObject)?.let(::add)
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun saveReminders(context: Context, reminders: List<ScheduledReminder>) {
        val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        val jsonArray = JSONArray()
        reminders
            .sortedBy { it.triggerAtMillis }
            .forEach { jsonArray.put(it.toJson()) }
        prefs.edit().putString(KEY_REMINDERS, jsonArray.toString()).apply()
    }

    fun getScheduledIds(context: Context): List<Int> {
        val now = System.currentTimeMillis()
        val reminders = loadReminders(context)
        val activeReminders = reminders.filter {
            it.triggerAtMillis > now - RECENT_OVERDUE_WINDOW_MILLIS
        }
        if (activeReminders.size != reminders.size) {
            saveReminders(context, activeReminders)
        }
        return activeReminders.map { it.id }
    }
}
