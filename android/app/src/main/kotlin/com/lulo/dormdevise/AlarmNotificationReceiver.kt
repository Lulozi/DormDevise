package com.lulo.dormdevise

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Color
import androidx.core.content.ContextCompat
import android.os.Build
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat

/**
 * 负责展示与关闭闹钟通知，使用自定义 RemoteViews 将关闭按钮放在右侧。
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
        val course = intent.getStringExtra(EXTRA_COURSE) ?: "课程"
        val location = intent.getStringExtra(EXTRA_LOCATION) ?: "未知教室"
        val minutes = intent.getIntExtra(EXTRA_MINUTES, 0)
        showNotification(context, id, course, location, minutes)
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
        const val EXTRA_COURSE = "extra_alarm_course"
        const val EXTRA_LOCATION = "extra_alarm_location"
        const val EXTRA_MINUTES = "extra_alarm_minutes"

        /**
         * 直接展示自定义闹钟通知。
         */
        fun showNotification(
            context: Context,
            id: Int,
            course: String,
            location: String,
            minutes: Int,
        ) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val contentView = RemoteViews(context.packageName, R.layout.notification_alarm).apply {
                val titleText = if (minutes <= 0) "马上开始上课" else "${minutes}分钟后上课"
                setTextViewText(R.id.alarm_title, titleText)
                setTextViewText(R.id.alarm_course_name, course)
                setTextViewText(R.id.alarm_course_extra, " - 教室：$location")
                setTextViewText(R.id.alarm_body, "")
                setOnClickPendingIntent(R.id.alarm_close, AlarmNotificationScheduler.buildDismissPendingIntent(context, id))
            }

            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val contentPendingIntent: PendingIntent? = launchIntent?.let {
                PendingIntent.getActivity(
                    context,
                    id,
                    it,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            }

            val builder = NotificationCompat.Builder(context, AlarmNotificationScheduler.CHANNEL_ID)
                .setSmallIcon(context.applicationInfo.icon)
                .setContentTitle(if (minutes <= 0) "马上开始上课" else "${minutes}分钟后上课")
                .setContentText("$course - 教室：$location")
                .setStyle(NotificationCompat.DecoratedCustomViewStyle())
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOngoing(false)
                .setAutoCancel(true)
                .setFullScreenIntent(contentPendingIntent, true)
                .setColor(ContextCompat.getColor(context, R.color.widget_primary))

            contentPendingIntent?.let { builder.setContentIntent(it) }

            val notification = builder.build()
            notification.contentView = contentView
            notification.bigContentView = contentView
            notification.flags = notification.flags or Notification.FLAG_INSISTENT

            manager.notify(id, notification)
        }
    }
}
