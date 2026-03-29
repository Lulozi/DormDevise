package com.lulo.dormdevise

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * 负责展示、打开与关闭课程提醒通知。
 */
class AlarmNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_SHOW -> handleShow(context, intent)
            ACTION_DISMISS -> handleDismiss(context, intent)
            ACTION_OPEN -> handleOpen(context, intent)
        }
    }

    private fun handleShow(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_ID, 0)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "课程提醒"
        val body = intent.getStringExtra(EXTRA_BODY) ?: ""
        val isAlarm = intent.getBooleanExtra(EXTRA_IS_ALARM, false)
        val enableVibration = intent.getBooleanExtra(EXTRA_ENABLE_VIBRATION, true)
        showNotification(context, id, title, body, isAlarm, enableVibration)
        AlarmNotificationScheduler.removeId(context, id)
    }

    private fun handleDismiss(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_ID, 0)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(id)
        AlarmNotificationScheduler.removeId(context, id)
    }

    private fun handleOpen(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_ID, 0)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(id)
        AlarmNotificationScheduler.removeId(context, id)

        val launchIntent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
            }
        if (launchIntent != null) {
            context.startActivity(launchIntent)
        }
    }

    companion object {
        private const val FLUTTER_SHARED_PREFERENCES_NAME = "FlutterSharedPreferences"
        private const val THEME_PRIMARY_COLOR_KEY = "flutter.theme_primary_color"
        private const val THEME_CUSTOM_PREVIEW_ENABLED_KEY = "flutter.theme_custom_preview_enabled"
        private const val WHITE_MODE_NOTIFICATION_COLOR = -10395295 // Colors.grey.shade700

        const val ACTION_SHOW = "com.lulo.dormdevise.ALARM_SHOW"
        const val ACTION_DISMISS = "com.lulo.dormdevise.ALARM_DISMISS"
        const val ACTION_OPEN = "com.lulo.dormdevise.ALARM_OPEN"
        const val EXTRA_ID = "extra_alarm_id"
        const val EXTRA_TITLE = "extra_alarm_title"
        const val EXTRA_BODY = "extra_alarm_body"
        const val EXTRA_IS_ALARM = "extra_alarm_is_alarm"
        const val EXTRA_ENABLE_VIBRATION = "extra_alarm_enable_vibration"

        /**
         * 直接展示系统课程提醒通知。
         */
        fun showNotification(
            context: Context,
            id: Int,
            title: String,
            body: String,
            isAlarm: Boolean,
            enableVibration: Boolean,
        ) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val contentPendingIntent = buildOpenPendingIntent(context, id)

            val channelId = when {
                isAlarm -> AlarmNotificationScheduler.ALARM_CHANNEL_ID
                enableVibration -> AlarmNotificationScheduler.NOTIFICATION_CHANNEL_ID
                else -> AlarmNotificationScheduler.NOTIFICATION_SILENT_CHANNEL_ID
            }

            val builder = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(R.drawable.icon_dormdevise_notification)
                .setContentTitle(title)
                .setContentText(body.replace('\n', ' '))
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setCategory(
                    if (isAlarm) {
                        NotificationCompat.CATEGORY_ALARM
                    } else {
                        NotificationCompat.CATEGORY_REMINDER
                    }
                )
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOngoing(isAlarm)
                .setAutoCancel(!isAlarm)
                .setOnlyAlertOnce(false)
                .setColor(resolveNotificationColor(context))
                .setColorized(false)
                .setDeleteIntent(AlarmNotificationScheduler.buildDismissPendingIntent(context, id))

            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                val legacySound = if (isAlarm) {
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                } else {
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                }
                builder.setSound(legacySound)
                if (isAlarm) {
                    builder.setVibrate(longArrayOf(0L, 500L, 260L, 720L))
                } else if (enableVibration) {
                    builder.setVibrate(longArrayOf(0L, 160L, 90L, 220L, 120L, 220L))
                }
            }

            builder.setContentIntent(contentPendingIntent)
            if (isAlarm) {
                builder.addAction(
                    0,
                    "关闭",
                    AlarmNotificationScheduler.buildDismissPendingIntent(context, id),
                )
            }
            if (isAlarm && canUseFullScreenIntent(manager)) {
                builder.setFullScreenIntent(contentPendingIntent, true)
            }

            val notification = builder.build().also {
                if (isAlarm) {
                    it.flags = it.flags or Notification.FLAG_INSISTENT
                }
            }
            manager.notify(id, notification)
        }

        private fun buildOpenPendingIntent(context: Context, id: Int): PendingIntent {
            val openIntent = Intent(context, AlarmNotificationReceiver::class.java).apply {
                action = ACTION_OPEN
                putExtra(EXTRA_ID, id)
            }
            return PendingIntent.getBroadcast(
                context,
                id + 100000,
                openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun canUseFullScreenIntent(manager: NotificationManager): Boolean {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                manager.canUseFullScreenIntent()
            } else {
                true
            }
        }

        private fun resolveNotificationColor(context: Context): Int {
            val preferences = context.getSharedPreferences(
                FLUTTER_SHARED_PREFERENCES_NAME,
                Context.MODE_PRIVATE,
            )
            val customPreviewEnabled = preferences.getBoolean(
                THEME_CUSTOM_PREVIEW_ENABLED_KEY,
                false,
            )
            val storedColor = preferences.getLong(
                THEME_PRIMARY_COLOR_KEY,
                0xFFFFFFFFL,
            ).toInt()

            if (!customPreviewEnabled && storedColor == 0xFFFFFFFF.toInt()) {
                return WHITE_MODE_NOTIFICATION_COLOR
            }
            return storedColor
        }
    }
}
