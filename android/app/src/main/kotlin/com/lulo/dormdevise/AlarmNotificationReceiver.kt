package com.lulo.dormdevise

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import androidx.core.app.NotificationCompat

/**
 * 负责展示与关闭课程提醒通知。
 */
class AlarmNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_SHOW -> handleShow(context, intent)
            ACTION_DISMISS -> handleDismiss(context, intent)
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

    companion object {
        const val ACTION_SHOW = "com.lulo.dormdevise.ALARM_SHOW"
        const val ACTION_DISMISS = "com.lulo.dormdevise.ALARM_DISMISS"
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
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val contentPendingIntent: PendingIntent? = launchIntent?.let {
                PendingIntent.getActivity(
                    context,
                    id,
                    it,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            }

            val channelId = when {
                isAlarm -> AlarmNotificationScheduler.ALARM_CHANNEL_ID
                enableVibration -> AlarmNotificationScheduler.NOTIFICATION_CHANNEL_ID
                else -> AlarmNotificationScheduler.NOTIFICATION_SILENT_CHANNEL_ID
            }

            val builder = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(context.applicationInfo.icon)
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
                .setColor(ContextCompat.getColor(context, R.color.widget_primary))
                .addAction(
                    0,
                    "关闭",
                    AlarmNotificationScheduler.buildDismissPendingIntent(context, id)
                )

            contentPendingIntent?.let { builder.setContentIntent(it) }
            if (isAlarm && contentPendingIntent != null) {
                builder.setFullScreenIntent(contentPendingIntent, true)
            }

            val notification = builder.build()
            if (isAlarm) {
                notification.flags = notification.flags or Notification.FLAG_INSISTENT
            }

            manager.notify(id, notification)
        }
    }
}
