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
import kotlin.math.abs
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
    private companion object {
        // 与 Dart/Kotlin 配置同步：95 代表“自动提醒（仅下一节）”。
        const val AUTO_REMINDER_MINUTES = 95
        // 1 分钟误差，兼容分钟边界和设备时钟抖动。
        const val BREAK_MATCH_TOLERANCE_MILLIS = 60_000L
        const val COMPACT_WIDGET_MAX_WIDTH_DP = 220f
    }

    private enum class CourseProgressType {
        TO_CLASS,
        TO_DISMISS,
    }

    private data class CourseProgressStatus(
        val type: CourseProgressType,
        val remainMillis: Long,
    )

    private var snapshot = CourseScheduleWidgetSnapshot(
        currentWeek = 0,
        weekday = 1,
        courses = emptyList(),
        sectionTimesByIndex = emptyMap(),
        breakDurationMillisByEndSection = emptyMap(),
        displayDateMillis = System.currentTimeMillis(),
        reminderMinutes = 0,
        headerFontSizeSp = 14f,
        contentFontSizeSp = 12f,
    )
    private var widgetWidthDp = 0f

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        val widgetData = HomeWidgetPlugin.getData(context)
        widgetWidthDp = widgetData.getFloat(
            CourseScheduleWidgetProvider.widgetWidthKey(widgetId),
            0f,
        )
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
        val internalBreak =
            state == CourseScheduleItemState.ONGOING && isInInternalBreak(item, snapshot)
        val breakActive = internalBreak
        val reminderDue =
            state == CourseScheduleItemState.UPCOMING &&
                isReminderDue(item, snapshot)
        val compactLayout = widgetWidthDp in 0f..COMPACT_WIDGET_MAX_WIDTH_DP
        val views = RemoteViews(
            context.packageName,
            if (compactLayout) {
                R.layout.widget_course_schedule_list_item_narrow
            } else {
                R.layout.widget_course_schedule_list_item
            },
        )
        val contentFontSize = if (compactLayout) {
            (snapshot.contentFontSizeSp - 0.5f).coerceAtLeast(10f)
        } else {
            snapshot.contentFontSizeSp
        }
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
        if (!compactLayout) {
            views.setTextViewTextSize(
                R.id.course_widget_item_section,
                TypedValue.COMPLEX_UNIT_SP,
                secondaryFontSize,
            )
        }

        views.setTextViewText(R.id.course_widget_item_name, item.name)
        val sectionText = buildSectionText(
            item = item,
            state = state,
            snapshot = snapshot,
            internalBreak = internalBreak,
        )
        views.setTextViewText(
            R.id.course_widget_item_info,
            if (compactLayout) {
                buildCompactInfoText(
                    item = item,
                    sectionText = sectionText,
                )
            } else {
                buildInfoText(item = item, state = state, snapshot = snapshot)
            },
        )
        if (!compactLayout) {
            views.setTextViewText(
                R.id.course_widget_item_section,
                sectionText,
            )
        }
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
                if (!compactLayout) {
                    views.setTextColor(
                        R.id.course_widget_item_section,
                        ContextCompat.getColor(context, R.color.widget_course_finished_text),
                    )
                }
            }

            breakActive || state == CourseScheduleItemState.ONGOING -> {
                // 课间休息与上课中统一使用绿色高亮样式。
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
                if (!compactLayout) {
                    views.setTextColor(
                        R.id.course_widget_item_section,
                        ContextCompat.getColor(context, R.color.widget_course_active_text),
                    )
                }
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
                if (!compactLayout) {
                    views.setTextColor(
                        R.id.course_widget_item_section,
                        ContextCompat.getColor(context, R.color.widget_course_reminder_text),
                    )
                }
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
                if (!compactLayout) {
                    views.setTextColor(
                        R.id.course_widget_item_section,
                        ContextCompat.getColor(context, R.color.widget_gray),
                    )
                }
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

    override fun getViewTypeCount(): Int = 2

    override fun getItemId(position: Int): Long {
        return snapshot.courses.getOrNull(position)?.stableId ?: position.toLong()
    }

    override fun hasStableIds(): Boolean = true

    private fun buildInfoText(
        item: CourseScheduleWidgetItem,
        state: CourseScheduleItemState,
        snapshot: CourseScheduleWidgetSnapshot,
    ): String {
        // 课程进入“上课中”后，信息行改为“后上课/后下课”倒计时，便于抬手即看。
        if (state == CourseScheduleItemState.ONGOING) {
            val countdownText = buildOngoingProgressText(item, snapshot)
            if (!countdownText.isNullOrBlank()) {
                return if (item.location.isNotBlank()) {
                    "$countdownText · ${item.location}"
                } else {
                    countdownText
                }
            }
        }

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

    private fun buildCompactInfoText(
        item: CourseScheduleWidgetItem,
        sectionText: String,
    ): String {
        val detail = when {
            item.location.isNotBlank() -> item.location
            item.startTime.isNotBlank() && item.endTime.isNotBlank() -> {
                "${item.startTime}-${item.endTime}"
            }
            else -> ""
        }
        return if (detail.isNotBlank()) {
            "$sectionText · $detail"
        } else {
            sectionText
        }
    }

    private fun buildSectionText(
        item: CourseScheduleWidgetItem,
        state: CourseScheduleItemState,
        snapshot: CourseScheduleWidgetSnapshot,
        internalBreak: Boolean,
    ): String {
        return when (state) {
            CourseScheduleItemState.ONGOING -> {
                if (internalBreak) {
                    "课间休息 · ${item.sectionLabel}"
                } else {
                    "上课中 · ${item.sectionLabel}"
                }
            }
            CourseScheduleItemState.FINISHED -> "已结束 · ${item.sectionLabel}"
            CourseScheduleItemState.UPCOMING -> {
                val reminderLabel = buildReminderLabel(item, snapshot)
                if (reminderLabel.isNullOrEmpty()) {
                    item.sectionLabel
                } else {
                    "$reminderLabel · ${item.sectionLabel}"
                }
            }
        }
    }

    private fun buildOngoingProgressText(
        item: CourseScheduleWidgetItem,
        snapshot: CourseScheduleWidgetSnapshot,
        now: Calendar = Calendar.getInstance(),
    ): String? {
        // 连堂课程在节内休息时，显示“后上课”；上课中显示“后下课”。
        val progress = resolveOngoingProgressStatus(item, snapshot, now) ?: return null
        val remainMillis = progress.remainMillis.coerceAtLeast(0L)
        if (remainMillis <= 60_000L) {
            return when (progress.type) {
                CourseProgressType.TO_CLASS -> "即将上课"
                CourseProgressType.TO_DISMISS -> "即将下课"
            }
        }

        val minutesLeft = ceil(remainMillis / 60_000.0).toInt().coerceAtLeast(1)
        return when (progress.type) {
            CourseProgressType.TO_CLASS -> "${minutesLeft}分后上课"
            CourseProgressType.TO_DISMISS -> "${minutesLeft}分后下课"
        }
    }

    private fun resolveOngoingProgressStatus(
        item: CourseScheduleWidgetItem,
        snapshot: CourseScheduleWidgetSnapshot,
        now: Calendar = Calendar.getInstance(),
    ): CourseProgressStatus? {
        val displayDate = Calendar.getInstance().apply {
            timeInMillis = snapshot.displayDateMillis
        }
        if (!isSameDay(displayDate, now)) {
            return null
        }

        val nowMillis = now.timeInMillis
        var fallbackEndMillis = parseTodayTimeMillis(item.endTime, now)

        for (sectionIndex in item.startSection..item.endSection) {
            val currentSection = snapshot.sectionTimesByIndex[sectionIndex] ?: continue
            val currentStartMillis = parseTodayTimeMillis(currentSection.start, now) ?: continue
            val currentEndMillis = parseTodayTimeMillis(currentSection.end, now) ?: continue
            fallbackEndMillis = currentEndMillis

            if (nowMillis < currentStartMillis) {
                return CourseProgressStatus(
                    type = CourseProgressType.TO_CLASS,
                    remainMillis = currentStartMillis - nowMillis,
                )
            }

            if (nowMillis < currentEndMillis) {
                return CourseProgressStatus(
                    type = CourseProgressType.TO_DISMISS,
                    remainMillis = currentEndMillis - nowMillis,
                )
            }

            if (sectionIndex < item.endSection) {
                val nextSection = snapshot.sectionTimesByIndex[sectionIndex + 1] ?: continue
                val nextStartMillis = parseTodayTimeMillis(nextSection.start, now) ?: continue
                if (nowMillis < nextStartMillis) {
                    return CourseProgressStatus(
                        type = CourseProgressType.TO_CLASS,
                        remainMillis = nextStartMillis - nowMillis,
                    )
                }
            }
        }

        if (fallbackEndMillis != null && nowMillis < fallbackEndMillis) {
            return CourseProgressStatus(
                type = CourseProgressType.TO_DISMISS,
                remainMillis = fallbackEndMillis - nowMillis,
            )
        }

        return null
    }

    private fun isInInternalBreak(
        item: CourseScheduleWidgetItem,
        snapshot: CourseScheduleWidgetSnapshot,
        now: Calendar = Calendar.getInstance(),
    ): Boolean {
        if (item.sectionCount <= 1) {
            return false
        }
        val displayDate = Calendar.getInstance().apply {
            timeInMillis = snapshot.displayDateMillis
        }
        if (!isSameDay(displayDate, now)) {
            return false
        }

        val nowMillis = now.timeInMillis
        for (sectionIndex in item.startSection until item.endSection) {
            val currentSection = snapshot.sectionTimesByIndex[sectionIndex] ?: continue
            val nextSection = snapshot.sectionTimesByIndex[sectionIndex + 1] ?: continue
            val currentEndMillis = parseTodayTimeMillis(currentSection.end, now) ?: continue
            val nextStartMillis = parseTodayTimeMillis(nextSection.start, now) ?: continue
            if (nextStartMillis > currentEndMillis && nowMillis in currentEndMillis until nextStartMillis) {
                return true
            }
        }
        return false
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

        if (snapshot.reminderMinutes == AUTO_REMINDER_MINUTES) {
            val nextUpcomingCourse = resolveNextUpcomingCourse(snapshot, now) ?: return false
            if (item.stableId != nextUpcomingCourse.stableId) {
                return false
            }

            val ongoingCourse = resolveOngoingCourse(snapshot, now)
            if (ongoingCourse != null &&
                shouldDelayAutoReminderUntilCurrentCourseEnds(
                    ongoingCourse = ongoingCourse,
                    nextUpcomingCourse = nextUpcomingCourse,
                    snapshot = snapshot,
                    now = now,
                )
            ) {
                return false
            }
            return true
        }

        val diffMillis = startMillis - now.timeInMillis
        val reminderWindow = snapshot.reminderMinutes * 60_000L
        return diffMillis > 0 && diffMillis <= reminderWindow
    }

    private fun resolveNextUpcomingCourse(
        snapshot: CourseScheduleWidgetSnapshot,
        now: Calendar = Calendar.getInstance(),
    ): CourseScheduleWidgetItem? {
        val displayDate = Calendar.getInstance().apply {
            timeInMillis = snapshot.displayDateMillis
        }
        if (!isSameDay(displayDate, now)) {
            return null
        }

        val nowMillis = now.timeInMillis
        var nextCourse: CourseScheduleWidgetItem? = null
        var nextStartMillis: Long? = null
        snapshot.courses.forEach { course ->
            val startMillis = parseTodayTimeMillis(course.startTime, now) ?: return@forEach
            if (startMillis <= nowMillis) {
                return@forEach
            }
            nextStartMillis = when {
                nextStartMillis == null -> {
                    nextCourse = course
                    startMillis
                }
                startMillis < nextStartMillis!! -> {
                    nextCourse = course
                    startMillis
                }
                else -> nextStartMillis
            }
        }
        return nextCourse
    }

    private fun resolveOngoingCourse(
        snapshot: CourseScheduleWidgetSnapshot,
        now: Calendar = Calendar.getInstance(),
    ): CourseScheduleWidgetItem? {
        val displayDate = Calendar.getInstance().apply {
            timeInMillis = snapshot.displayDateMillis
        }
        if (!isSameDay(displayDate, now)) {
            return null
        }

        return snapshot.courses.firstOrNull { course ->
            CourseScheduleWidgetData.resolveState(course, snapshot, now) ==
                CourseScheduleItemState.ONGOING
        }
    }

    private fun shouldDelayAutoReminderUntilCurrentCourseEnds(
        ongoingCourse: CourseScheduleWidgetItem,
        nextUpcomingCourse: CourseScheduleWidgetItem,
        snapshot: CourseScheduleWidgetSnapshot,
        now: Calendar = Calendar.getInstance(),
    ): Boolean {
        val ongoingEndMillis = parseTodayTimeMillis(ongoingCourse.endTime, now) ?: return false
        val nextStartMillis = parseTodayTimeMillis(nextUpcomingCourse.startTime, now) ?: return false
        if (nextStartMillis <= ongoingEndMillis) {
            return false
        }

        // 只有紧邻小节且命中配置化小课间时，才允许“上课中”阶段提前展示下一节提醒。
        if (nextUpcomingCourse.startSection != ongoingCourse.endSection + 1) {
            return true
        }

        val configuredBreakMillis = snapshot.breakDurationMillisByEndSection[ongoingCourse.endSection]
            ?: return true
        val actualGapMillis = nextStartMillis - ongoingEndMillis
        return abs(actualGapMillis - configuredBreakMillis) > BREAK_MATCH_TOLERANCE_MILLIS
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
            return "即将上课"
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
