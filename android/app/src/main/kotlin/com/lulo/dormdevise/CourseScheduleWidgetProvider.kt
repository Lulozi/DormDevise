package com.lulo.dormdevise

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar

/**
 * 课表桌面组件提供者，支持滚动查看全天课程，并根据当前上课状态更新样式。
 */
class CourseScheduleWidgetProvider : HomeWidgetProvider() {

    companion object {
        private const val ACTION_REFRESH_STATE = "com.lulo.dormdevise.action.COURSE_WIDGET_REFRESH_STATE"
        private const val ACTION_SYNC_TO_TODAY = "com.lulo.dormdevise.action.COURSE_WIDGET_SYNC_TO_TODAY"
        private const val ACTION_NAVIGATE_DATE = "com.lulo.dormdevise.action.COURSE_WIDGET_NAVIGATE_DATE"
        private const val REFRESH_REQUEST_CODE = 42031
        private const val MIDNIGHT_SYNC_REQUEST_CODE = 42032
        private const val DISPLAY_DATE_KEY_PREFIX = "course_widget_display_date_"
        private const val EXTRA_DAY_DELTA = "dayDelta"
        private val WEEKDAY_NAMES = arrayOf("", "周一", "周二", "周三", "周四", "周五", "周六", "周日")

        fun refreshAllWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(
                ComponentName(context, CourseScheduleWidgetProvider::class.java),
            )
            if (appWidgetIds.isEmpty()) {
                cancelScheduledRefreshes(context)
                return
            }
            performUpdate(
                context = context,
                appWidgetManager = appWidgetManager,
                appWidgetIds = appWidgetIds,
                widgetData = HomeWidgetPlugin.getData(context),
            )
        }

        fun syncAllWidgetsToToday(context: Context) {
            val widgetData = HomeWidgetPlugin.getData(context)
            clearDisplayDateForAllWidgets(context, widgetData)
            refreshAllWidgets(context.applicationContext)
        }

        private fun performUpdate(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray,
            widgetData: SharedPreferences,
        ) {
            if (appWidgetIds.isEmpty()) {
                cancelScheduledRefreshes(context)
                return
            }

            val tableName = widgetData.getString("course_widget_table_name", null)
            val isConfigured = widgetData.getBoolean("course_widget_is_configured", false)
            var nextRefreshAtMillis: Long? = null

            appWidgetIds.forEach { widgetId ->
                val snapshot = CourseScheduleWidgetData.buildSnapshot(
                    widgetData = widgetData,
                    displayDate = resolveDisplayDateCalendar(
                        widgetData = widgetData,
                        widgetId = widgetId,
                    ),
                )
                val views = buildRemoteViews(
                    context = context,
                    appWidgetManager = appWidgetManager,
                    widgetId = widgetId,
                    tableName = tableName,
                    snapshot = snapshot,
                    isConfigured = isConfigured,
                )
                appWidgetManager.updateAppWidget(widgetId, views)
                val widgetRefreshAtMillis = CourseScheduleWidgetData.computeNextRefreshAtMillis(snapshot)
                nextRefreshAtMillis = minOfNullable(nextRefreshAtMillis, widgetRefreshAtMillis)
            }

            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.course_widget_list)
            scheduleNextStateRefresh(context, nextRefreshAtMillis)
            scheduleMidnightSync(context)
        }

        private fun buildRemoteViews(
            context: Context,
            appWidgetManager: AppWidgetManager,
            widgetId: Int,
            tableName: String?,
            snapshot: CourseScheduleWidgetSnapshot,
            isConfigured: Boolean,
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_course_schedule)
            val weekdayName = getWeekdayName(snapshot.weekday)
            val dateText = if (snapshot.currentWeek > 0) {
                "$weekdayName · 第${snapshot.currentWeek}周"
            } else {
                weekdayName
            }
            val headerFontSize = snapshot.headerFontSizeSp
            val dateFontSize = (headerFontSize - 3f).coerceAtLeast(9f)
            val arrowFontSize = (headerFontSize - 2f).coerceAtLeast(10f)
            val emptyTextSize = (snapshot.contentFontSizeSp - 1f).coerceAtLeast(10f)

            views.setTextViewText(
                R.id.course_widget_title,
                tableName?.takeIf { it.isNotBlank() } ?: context.getString(R.string.course_widget_name),
            )
            views.setTextViewText(R.id.course_widget_date, dateText)
            views.setTextViewTextSize(
                R.id.course_widget_title,
                TypedValue.COMPLEX_UNIT_SP,
                headerFontSize,
            )
            views.setTextViewTextSize(
                R.id.course_widget_date,
                TypedValue.COMPLEX_UNIT_SP,
                dateFontSize,
            )
            views.setTextViewTextSize(
                R.id.course_widget_prev_day,
                TypedValue.COMPLEX_UNIT_SP,
                arrowFontSize,
            )
            views.setTextViewTextSize(
                R.id.course_widget_next_day,
                TypedValue.COMPLEX_UNIT_SP,
                arrowFontSize,
            )
            views.setTextViewText(
                R.id.course_widget_empty_text,
                context.getString(
                    if (isConfigured) R.string.course_widget_empty else R.string.course_widget_not_configured,
                ),
            )
            views.setTextViewTextSize(
                R.id.course_widget_empty_text,
                TypedValue.COMPLEX_UNIT_SP,
                emptyTextSize,
            )
            views.setTextColor(
                R.id.course_widget_empty_text,
                ContextCompat.getColor(context, R.color.widget_gray),
            )
            views.setViewVisibility(R.id.course_widget_empty, View.VISIBLE)

            val serviceIntent = Intent(context, CourseScheduleWidgetListService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.course_widget_list, serviceIntent)
            views.setEmptyView(R.id.course_widget_list, R.id.course_widget_empty)
            views.setScrollPosition(
                R.id.course_widget_list,
                resolveScrollAnchorIndex(
                    appWidgetManager = appWidgetManager,
                    widgetId = widgetId,
                    snapshot = snapshot,
                ),
            )

            buildLaunchPendingIntent(
                context = context,
                requestCode = widgetId * 10 + 1,
                route = buildWidgetRoute(snapshot),
            )?.let { pendingIntent ->
                views.setOnClickPendingIntent(R.id.course_widget_root, pendingIntent)
            }
            buildTemplateLaunchPendingIntent(
                context = context,
                requestCode = widgetId * 10 + 2,
            )?.let { pendingIntent ->
                views.setPendingIntentTemplate(R.id.course_widget_list, pendingIntent)
            }
            views.setOnClickPendingIntent(
                R.id.course_widget_prev_day,
                buildNavigateDatePendingIntent(context, widgetId, -1),
            )
            views.setOnClickPendingIntent(
                R.id.course_widget_next_day,
                buildNavigateDatePendingIntent(context, widgetId, 1),
            )

            return views
        }

        private fun buildLaunchPendingIntent(
            context: Context,
            requestCode: Int,
            route: String,
        ): PendingIntent? {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: return null
            launchIntent.putExtra("route", route)
            launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            return PendingIntent.getActivity(
                context,
                requestCode,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun buildTemplateLaunchPendingIntent(
            context: Context,
            requestCode: Int,
        ): PendingIntent? {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: return null
            launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            }
            return PendingIntent.getActivity(
                context,
                requestCode,
                launchIntent,
                flags,
            )
        }

        private fun buildNavigateDatePendingIntent(
            context: Context,
            widgetId: Int,
            dayDelta: Int,
        ): PendingIntent {
            val navigateIntent = Intent(context, CourseScheduleWidgetProvider::class.java).apply {
                action = ACTION_NAVIGATE_DATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
                putExtra(EXTRA_DAY_DELTA, dayDelta)
            }
            return PendingIntent.getBroadcast(
                context,
                widgetId * 10 + if (dayDelta < 0) 3 else 4,
                navigateIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun scheduleNextStateRefresh(
            context: Context,
            triggerAtMillis: Long?,
        ) {
            val refreshIntent = buildRefreshPendingIntent(context)
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(refreshIntent)

            triggerAtMillis ?: return

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    !alarmManager.canScheduleExactAlarms()
                ) {
                    scheduleBestEffort(alarmManager, triggerAtMillis, refreshIntent)
                    return
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC,
                        triggerAtMillis,
                        refreshIntent,
                    )
                } else {
                    alarmManager.setExact(AlarmManager.RTC, triggerAtMillis, refreshIntent)
                }
            } catch (_: SecurityException) {
                scheduleBestEffort(alarmManager, triggerAtMillis, refreshIntent)
            }
        }

        private fun scheduleMidnightSync(context: Context) {
            val syncIntent = buildMidnightSyncPendingIntent(context)
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(syncIntent)

            val triggerAtMillis = nextDayStartMillis(Calendar.getInstance()) + 1_000L

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    !alarmManager.canScheduleExactAlarms()
                ) {
                    scheduleBestEffort(alarmManager, triggerAtMillis, syncIntent)
                    return
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC,
                        triggerAtMillis,
                        syncIntent,
                    )
                } else {
                    alarmManager.setExact(AlarmManager.RTC, triggerAtMillis, syncIntent)
                }
            } catch (_: SecurityException) {
                scheduleBestEffort(alarmManager, triggerAtMillis, syncIntent)
            }
        }

        private fun scheduleBestEffort(
            alarmManager: AlarmManager,
            triggerAtMillis: Long,
            pendingIntent: PendingIntent,
        ) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC, triggerAtMillis, pendingIntent)
            } else {
                alarmManager.set(AlarmManager.RTC, triggerAtMillis, pendingIntent)
            }
        }

        private fun cancelScheduledRefreshes(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(buildRefreshPendingIntent(context))
            alarmManager.cancel(buildMidnightSyncPendingIntent(context))
        }

        private fun buildRefreshPendingIntent(context: Context): PendingIntent {
            val refreshIntent = Intent(context, CourseScheduleWidgetProvider::class.java).apply {
                action = ACTION_REFRESH_STATE
            }
            return PendingIntent.getBroadcast(
                context,
                REFRESH_REQUEST_CODE,
                refreshIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun buildMidnightSyncPendingIntent(context: Context): PendingIntent {
            val refreshIntent = Intent(context, CourseScheduleWidgetProvider::class.java).apply {
                action = ACTION_SYNC_TO_TODAY
            }
            return PendingIntent.getBroadcast(
                context,
                MIDNIGHT_SYNC_REQUEST_CODE,
                refreshIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun getWeekdayName(dayOfWeek: Int): String {
            return if (dayOfWeek in 1..7) WEEKDAY_NAMES[dayOfWeek] else "今天"
        }

        private fun resolveScrollAnchorIndex(
            appWidgetManager: AppWidgetManager,
            widgetId: Int,
            snapshot: CourseScheduleWidgetSnapshot,
        ): Int {
            if (snapshot.courses.isEmpty()) {
                return 0
            }
            val focusIndex = CourseScheduleWidgetData.resolveFocusIndex(snapshot)
            val visibleCount = estimateVisibleCourseCount(
                resolveWidgetSize(appWidgetManager.getAppWidgetOptions(widgetId))?.height ?: 0f,
                snapshot.courses.size,
            )
            return focusIndex.coerceAtMost((snapshot.courses.size - visibleCount).coerceAtLeast(0))
        }

        private fun estimateVisibleCourseCount(
            widgetHeightDp: Float,
            totalCount: Int,
        ): Int {
            if (totalCount <= 0) {
                return 1
            }
            if (widgetHeightDp <= 0f) {
                return minOf(2, totalCount)
            }
            val availableHeight = (widgetHeightDp - 34f).coerceAtLeast(44f)
            val rowHeight = 46f
            return (availableHeight / rowHeight).toInt().coerceIn(1, totalCount)
        }

        private fun resolveWidgetSize(options: Bundle): SizeF? {
            val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH).toFloat()
            val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT).toFloat()
            if (minWidth > 0f && minHeight > 0f) {
                return SizeF(minWidth, minHeight)
            }

            return getWidgetSizes(options)
                .filter { size -> size.width > 0f && size.height > 0f }
                .minByOrNull { size -> size.width * size.height }
        }

        private fun getWidgetSizes(options: Bundle): List<SizeF> {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                return emptyList()
            }

            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                options.getParcelableArrayList(AppWidgetManager.OPTION_APPWIDGET_SIZES, SizeF::class.java)
                    ?: emptyList()
            } else {
                @Suppress("DEPRECATION")
                options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
                    ?: emptyList()
            }
        }

        internal fun resolveDisplayDateCalendar(
            widgetData: SharedPreferences,
            widgetId: Int,
        ): Calendar {
            val storedMillis = widgetData
                .getString(displayDateKey(widgetId), null)
                ?.toLongOrNull()
            return Calendar.getInstance().apply {
                if (storedMillis != null) {
                    timeInMillis = storedMillis
                }
            }
        }

        internal fun buildWidgetRoute(
            snapshot: CourseScheduleWidgetSnapshot,
            startSection: Int? = null,
            courseName: String? = null,
        ): String {
            val queryParts = buildList {
                add("fromWidget=1")
                if (snapshot.currentWeek > 0) {
                    add("week=${snapshot.currentWeek}")
                }
                if (snapshot.weekday in 1..7) {
                    add("weekday=${snapshot.weekday}")
                }
                if (startSection != null && startSection > 0) {
                    add("section=$startSection")
                }
                if (!courseName.isNullOrBlank()) {
                    add("course=${Uri.encode(courseName)}")
                }
            }
            return if (queryParts.isEmpty()) {
                "/table"
            } else {
                "/table?${queryParts.joinToString("&")}"
            }
        }

        private fun shiftDisplayDate(
            widgetData: SharedPreferences,
            widgetId: Int,
            dayDelta: Int,
        ) {
            val nextDate = resolveDisplayDateCalendar(widgetData, widgetId).apply {
                add(Calendar.DAY_OF_YEAR, dayDelta)
            }
            widgetData.edit()
                .putString(displayDateKey(widgetId), nextDate.timeInMillis.toString())
                .apply()
        }

        private fun clearDisplayDate(
            widgetData: SharedPreferences,
            widgetId: Int,
        ) {
            widgetData.edit().remove(displayDateKey(widgetId)).apply()
        }

        private fun clearDisplayDateForAllWidgets(context: Context, widgetData: SharedPreferences) {
            val appWidgetIds = AppWidgetManager.getInstance(context).getAppWidgetIds(
                ComponentName(context, CourseScheduleWidgetProvider::class.java),
            )
            appWidgetIds.forEach { widgetId ->
                clearDisplayDate(widgetData, widgetId)
            }
        }

        private fun displayDateKey(widgetId: Int): String {
            return "$DISPLAY_DATE_KEY_PREFIX$widgetId"
        }

        private fun nextDayStartMillis(calendar: Calendar): Long {
            return Calendar.getInstance().apply {
                timeInMillis = calendar.timeInMillis
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }.timeInMillis
        }

        private fun minOfNullable(current: Long?, candidate: Long?): Long? {
            return when {
                candidate == null -> current
                current == null -> candidate
                else -> minOf(current, candidate)
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_REFRESH_STATE -> {
                refreshAllWidgets(context.applicationContext)
                return
            }
            ACTION_SYNC_TO_TODAY -> {
                val widgetData = HomeWidgetPlugin.getData(context)
                clearDisplayDateForAllWidgets(context, widgetData)
                refreshAllWidgets(context.applicationContext)
                return
            }
            ACTION_NAVIGATE_DATE -> {
                val widgetId = intent.getIntExtra(
                    AppWidgetManager.EXTRA_APPWIDGET_ID,
                    AppWidgetManager.INVALID_APPWIDGET_ID,
                )
                if (widgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                    val widgetData = HomeWidgetPlugin.getData(context)
                    shiftDisplayDate(
                        widgetData = widgetData,
                        widgetId = widgetId,
                        dayDelta = intent.getIntExtra(EXTRA_DAY_DELTA, 0),
                    )
                    performUpdate(
                        context = context,
                        appWidgetManager = AppWidgetManager.getInstance(context),
                        appWidgetIds = intArrayOf(widgetId),
                        widgetData = widgetData,
                    )
                    return
                }
            }
        }
        super.onReceive(context, intent)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        performUpdate(context, appWidgetManager, appWidgetIds, widgetData)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        performUpdate(
            context = context,
            appWidgetManager = appWidgetManager,
            appWidgetIds = intArrayOf(appWidgetId),
            widgetData = HomeWidgetPlugin.getData(context),
        )
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        val widgetData = HomeWidgetPlugin.getData(context)
        appWidgetIds.forEach { widgetId ->
            clearDisplayDate(widgetData, widgetId)
        }
        refreshAllWidgets(context.applicationContext)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        cancelScheduledRefreshes(context.applicationContext)
    }
}
