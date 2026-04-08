package com.lulo.dormdevise

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetPlugin

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
        val views = RemoteViews(context.packageName, R.layout.widget_course_schedule_list_item)

        views.setTextViewText(R.id.course_widget_item_name, item.name)
        views.setTextViewText(R.id.course_widget_item_info, buildInfoText(item))
        views.setTextViewText(R.id.course_widget_item_section, buildSectionText(item, state))
        views.setInt(
            R.id.course_widget_item_indicator,
            "setColorFilter",
            resolveIndicatorColor(item.indicatorColor, state),
        )

        when (state) {
            CourseScheduleItemState.UPCOMING -> {
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

            CourseScheduleItemState.ONGOING -> {
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

            CourseScheduleItemState.FINISHED -> {
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
        }

        views.setOnClickFillInIntent(
            R.id.course_widget_item_root,
            Intent().apply {
                putExtra(
                    "route",
                    CourseScheduleWidgetProvider.buildWidgetRoute(
                        snapshot = snapshot,
                        startSection = item.startSection,
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
    ): String {
        return when (state) {
            CourseScheduleItemState.ONGOING -> "${item.sectionLabel} · 进行中"
            CourseScheduleItemState.FINISHED -> "${item.sectionLabel} · 已结束"
            CourseScheduleItemState.UPCOMING -> item.sectionLabel
        }
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
