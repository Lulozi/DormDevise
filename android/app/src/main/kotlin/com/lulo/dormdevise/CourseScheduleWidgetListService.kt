package com.lulo.dormdevise

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.util.TypedValue
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetPlugin
import kotlin.math.ceil
import java.util.Calendar

class CourseScheduleWidgetListService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return CourseScheduleWidgetRemoteViewsFactory(
            context = applicationContext,
            widgetId = intent.getIntExtra(
                AppWidgetManager.EXTRA_APPWIDGET_ID,
                AppWidgetManager.INVALID_APPWIDGET_ID,
            ),
        )
    }
}

private class CourseScheduleWidgetRemoteViewsFactory(
    private val context: Context,
    private val widgetId: Int,
) : RemoteViewsService.RemoteViewsFactory {
    private var snapshot = CourseScheduleWidgetSnapshot(
        currentWeek = 0,
        weekday = 1,
        courses = emptyList(),
        displayDateMillis = System.currentTimeMillis(),
        reminderMinutes = 0,
        headerFontSizeSp = 14f,
        contentFontSizeSp = 12f,
    )

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        val widgetData = HomeWidgetPlugin.getData(context)
        snapshot = CourseScheduleWidgetData.buildSnapshot(
            widgetData = widgetData,
            displayDate = CourseScheduleWidgetProvider.resolveDisplayDateCalendar(
                widgetData = widgetData,
                widgetId = widgetId,
            ),
        )
    }

    override fun onDestroy() {
        snapshot = snapshot.copy(courses = emptyList())
    }

    override fun getCount(): Int = snapshot.courses.size

    override fun getViewAt(position: Int): RemoteViews? {
        if (position !in snapshot.courses.indices) return null

        val item = snapshot.courses[position]
        val state = CourseScheduleWidgetData.resolveState(item, snapshot)
        val reminderDue = state == CourseScheduleItemState.UPCOMING && isReminderDue(item, snapshot)
        val views = RemoteViews(context.packageName, R.layout.widget_course_schedule_list_item)
        val contentFontSize = snapshot.contentFontSizeSp
        val secondaryFontSize = (contentFontSize - 2f).coerceAtLeast(8f)

        views.setTextViewTextSize(
            R.id.course_widget_item_name,
            TypedValue.COMPLEX_UNIT_SP,
            contentFontSize,
        )
        views.setTextViewTextSize(
            R.id.course_widget_item_info,
            TypedValue.COMPLEX_UNIT_SP,
            secondaryFontSize,
        )
        views.setTextViewTextSize(
            R.id.course_widget_item_section,
            TypedValue.COMPLEX_UNIT_SP,
            secondaryFontSize,
        )

        views.setTextViewText(R.id.course_widget_item_name, item.name)
        views.setTextViewText(R.id.course_widget_item_info, buildInfoText(item))
        views.setTextViewText(
            R.id.course_widget_item_section,
            buildSectionText(item, state, snapshot),
        )
        views.setInt(
            R.id.course_widget_item_indicator,
            "setColorFilter",
            resolveIndicatorColor(item.indicatorColor, state),
        )

        when {
            state == CourseScheduleItemState.FINISHED -> {
                views.setInt(
                    R.id.course_widget_item_root,
                    "setBackgroundResource",
                    R.drawable.widget_course_item_bg_finished,
                )
                views.setTextColor(
                    R.id.course_widget_item_name,
                    ContextCompat.getColor(context, R.color.widget_course_finished_text),
                )
                views.setTextColor(
                    R.id.course_widget_item_info,
                    ContextCompat.getColor(context, R.color.widget_course_finished_text),
                )
                views.setTextColor(
                    R.id.course_widget_item_section,
                    ContextCompat.getColor(context, R.color.widget_course_finished_text),
                )
            }

            state == CourseScheduleItemState.ONGOING -> {
                views.setInt(
                    R.id.course_widget_item_root,
                    "setBackgroundResource",
                    R.drawable.widget_course_item_bg_active,
                )
                views.setTextColor(
                    R.id.course_widget_item_name,
                    ContextCompat.getColor(context, R.color.widget_text),
                )
                views.setTextColor(
                    R.id.course_widget_item_info,
                    ContextCompat.getColor(context, R.color.widget_text_secondary),
                )
                views.setTextColor(
                    R.id.course_widget_item_section,
                    ContextCompat.getColor(context, R.color.widget_course_active_text),
                )
            }

            reminderDue -> {
                views.setInt(
                    R.id.course_widget_item_root,
                    "setBackgroundResource",
                    R.drawable.widget_course_item_bg_reminder,
                )
                views.setTextColor(
                    R.id.course_widget_item_name,
                    ContextCompat.getColor(context, R.color.widget_text),
                )
                views.setTextColor(
                    R.id.course_widget_item_info,
                    ContextCompat.getColor(context, R.color.widget_text_secondary),
                )
                views.setTextColor(
                    R.id.course_widget_item_section,
                    ContextCompat.getColor(context, R.color.widget_course_reminder_text),
                )
            }

            else -> {
                views.setInt(
                    R.id.course_widget_item_root,
                    "setBackgroundResource",
                    R.drawable.widget_course_item_bg,
                )
                views.setTextColor(
                    R.id.course_widget_item_name,
                    ContextCompat.getColor(context, R.color.widget_text),
                )
                views.setTextColor(
                    R.id.course_widget_item_info,
                    ContextCompat.getColor(context, R.color.widget_text_secondary),
                )
                views.setTextColor(
                    R.id.course_widget_item_section,
                    ContextCompat.getColor(context, R.color.widget_gray),
                )
            }
        }

        views.setOnClickFillInIntent(
            R.id.course_widget_item_root,
            Intent().apply {
                putExtra(
                    "route",
                    CourseScheduleWidgetProvider.buildWidgetRoute(
                        snapshot = snapshot,
                        startSection = item.startSection,
                        courseName = item.name,
                    ),
                )
            },
        )
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long {
        return snapshot.courses.getOrNull(position)?.stableId ?: position.toLong()
    }

    override fun hasStableIds(): Boolean = true

    private fun buildInfoText(item: CourseScheduleWidgetItem): String {
        val timeInfo = if (item.startTime.isNotBlank() && item.endTime.isNotBlank()) {
            "${item.startTime}-${item.endTime}"
        } else {
            ""
        }

        return if (item.location.isNotBlank()) {
            if (timeInfo.isNotBlank()) "$timeInfo · ${item.location}" else item.location
        } else {
            timeInfo
        }
    }

    private fun buildSectionText(
        item: CourseScheduleWidgetItem,
        state: CourseScheduleItemState,
        snapshot: CourseScheduleWidgetSnapshot,
    ): String {
        return when (state) {
            CourseScheduleItemState.ONGOING -> "${item.sectionLabel} · 进行中"
            CourseScheduleItemState.FINISHED -> "${item.sectionLabel} · 已结束"
            CourseScheduleItemState.UPCOMING -> {
                val reminderLabel = buildReminderLabel(item, snapshot)
                if (reminderLabel.isNullOrEmpty()) {
                    item.sectionLabel
                } else {
                    "${item.sectionLabel} · $reminderLabel"
                }
            }
        }
    }

    private fun isReminderDue(
        item: CourseScheduleWidgetItem,
        snapshot: CourseScheduleWidgetSnapshot,
        now: Calendar = Calendar.getInstance(),
    ): Boolean {
        if (snapshot.reminderMinutes <= 0) {
            return false
        }
        val displayDate = Calendar.getInstance().apply {
            timeInMillis = snapshot.displayDateMillis
        }
        if (!isSameDay(displayDate, now)) {
            return false
        }
        val startMillis = parseTodayTimeMillis(item.startTime, now) ?: return false
        val diffMillis = startMillis - now.timeInMillis
        val reminderWindow = snapshot.reminderMinutes * 60_000L
        return diffMillis > 0 && diffMillis <= reminderWindow
    }

    private fun buildReminderLabel(
        item: CourseScheduleWidgetItem,
        snapshot: CourseScheduleWidgetSnapshot,
        now: Calendar = Calendar.getInstance(),
    ): String? {
        if (!isReminderDue(item, snapshot, now)) {
            return null
        }
        val startMillis = parseTodayTimeMillis(item.startTime, now) ?: return null
        val diffMillis = (startMillis - now.timeInMillis).coerceAtLeast(0)
        if (diffMillis <= 60_000L) {
            return "即将"
        }
        val minutesLeft = ceil(diffMillis / 60_000.0).toInt().coerceAtLeast(1)
        return "${minutesLeft}分钟后"
    }

    private fun parseTodayTimeMillis(
        timeText: String,
        base: Calendar,
    ): Long? {
        val parts = timeText.split(':')
        if (parts.size != 2) return null
        val hour = parts[0].toIntOrNull() ?: return null
        val minute = parts[1].toIntOrNull() ?: return null

        return Calendar.getInstance().apply {
            timeInMillis = base.timeInMillis
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
    }

    private fun isSameDay(
        a: Calendar,
        b: Calendar,
    ): Boolean {
        return a.get(Calendar.YEAR) == b.get(Calendar.YEAR) &&
            a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)
    }

    private fun resolveIndicatorColor(
        color: Int,
        state: CourseScheduleItemState,
    ): Int {
        return when (state) {
            CourseScheduleItemState.FINISHED -> blendColors(
                color = color,
                overlay = ContextCompat.getColor(context, R.color.widget_gray),
                overlayRatio = 0.68f,
            )

            else -> color
        }
    }

    private fun blendColors(
        color: Int,
        overlay: Int,
        overlayRatio: Float,
    ): Int {
        val ratio = overlayRatio.coerceIn(0f, 1f)
        val baseRatio = 1f - ratio
        val red = (Color.red(color) * baseRatio + Color.red(overlay) * ratio).toInt()
        val green = (Color.green(color) * baseRatio + Color.green(overlay) * ratio).toInt()
        val blue = (Color.blue(color) * baseRatio + Color.blue(overlay) * ratio).toInt()
        return Color.argb(255, red, green, blue)
    }
}
