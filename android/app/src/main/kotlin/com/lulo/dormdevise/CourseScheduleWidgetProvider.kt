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
import kotlin.math.roundToInt

/**
 * 课表桌面组件提供者，支持滚动查看全天课程，并根据当前上课状态更新样式。
 */
class CourseScheduleWidgetProvider : HomeWidgetProvider() {

    companion object {
        private const val ACTION_REFRESH_STATE = "com.lulo.dormdevise.action.COURSE_WIDGET_REFRESH_STATE"
        private const val ACTION_BOOTSTRAP_REFRESH =
            "com.lulo.dormdevise.action.COURSE_WIDGET_BOOTSTRAP_REFRESH"
        private const val ACTION_SYNC_TO_TODAY = "com.lulo.dormdevise.action.COURSE_WIDGET_SYNC_TO_TODAY"
        private const val ACTION_NAVIGATE_DATE = "com.lulo.dormdevise.action.COURSE_WIDGET_NAVIGATE_DATE"
        private const val ACTION_DATE_TEXT_TAP = "com.lulo.dormdevise.action.COURSE_WIDGET_DATE_TEXT_TAP"
        private const val ACTION_OPEN_ROUTE = "com.lulo.dormdevise.action.COURSE_WIDGET_OPEN_ROUTE"
        private const val REFRESH_REQUEST_CODE = 42031
        private const val MIDNIGHT_SYNC_REQUEST_CODE = 42032
        private const val BOOTSTRAP_REFRESH_REQUEST_CODE = 42033
        private const val REFRESH_ALARM_TYPE = AlarmManager.RTC_WAKEUP
        private const val DISPLAY_DATE_KEY_PREFIX = "course_widget_display_date_"
        private const val LAST_DATE_TAP_AT_KEY_PREFIX = "course_widget_last_date_tap_at_"
        private const val WIDGET_WIDTH_DP_KEY_PREFIX = "course_widget_width_dp_"
        private const val WIDGET_HEIGHT_DP_KEY_PREFIX = "course_widget_height_dp_"
        private const val BOOTSTRAP_COMPLETED_KEY_PREFIX = "course_widget_bootstrap_completed_"
        private const val DATE_DOUBLE_TAP_WINDOW_MILLIS = 500L
        private const val BOOTSTRAP_REFRESH_DELAY_MILLIS = 900L
        private const val EXTRA_ROUTE = "route"
        private const val EXTRA_DAY_DELTA = "dayDelta"
        private const val COMPACT_WIDGET_MAX_WIDTH_DP = 220f
        private const val MEDIUM_WIDGET_MAX_WIDTH_DP = 300f
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
            val collectionWidgetIds = mutableListOf<Int>()
            var needsBootstrapRefresh = false

            appWidgetIds.forEach { widgetId ->
                val widgetSize = resolveWidgetSize(appWidgetManager.getAppWidgetOptions(widgetId))
                saveWidgetSize(widgetData, widgetId, widgetSize)
                if (shouldUseBootstrapLoadingPass(widgetData, widgetId)) {
                    markBootstrapCompleted(widgetData, widgetId)
                    appWidgetManager.updateAppWidget(widgetId, buildLoadingRemoteViews(context))
                    needsBootstrapRefresh = true
                    return@forEach
                }
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
                    widgetSize = widgetSize,
                )
                appWidgetManager.updateAppWidget(widgetId, views)
                collectionWidgetIds += widgetId
            }

            if (collectionWidgetIds.isNotEmpty()) {
                appWidgetManager.notifyAppWidgetViewDataChanged(
                    collectionWidgetIds.toIntArray(),
                    R.id.course_widget_list,
                )
            }
            val nextRefreshAtMillis = resolveNextRefreshAtMillisForAllWidgets(
                context = context,
                appWidgetManager = appWidgetManager,
                widgetData = widgetData,
            )
            scheduleNextStateRefresh(context, nextRefreshAtMillis)
            scheduleMidnightSync(context)
            if (needsBootstrapRefresh) {
                scheduleBootstrapRefresh(context)
            }
        }

        private fun resolveNextRefreshAtMillisForAllWidgets(
            context: Context,
            appWidgetManager: AppWidgetManager,
            widgetData: SharedPreferences,
        ): Long? {
            val allWidgetIds = appWidgetManager.getAppWidgetIds(
                ComponentName(context, CourseScheduleWidgetProvider::class.java),
            )
            var nextRefreshAtMillis: Long? = null
            allWidgetIds.forEach { widgetId ->
                val snapshot = CourseScheduleWidgetData.buildSnapshot(
                    widgetData = widgetData,
                    displayDate = resolveDisplayDateCalendar(
                        widgetData = widgetData,
                        widgetId = widgetId,
                    ),
                )
                val widgetRefreshAtMillis = CourseScheduleWidgetData.computeNextRefreshAtMillis(snapshot)
                nextRefreshAtMillis = minOfNullable(nextRefreshAtMillis, widgetRefreshAtMillis)
            }
            return nextRefreshAtMillis
        }

        private fun buildRemoteViews(
            context: Context,
            appWidgetManager: AppWidgetManager,
            widgetId: Int,
            tableName: String?,
            snapshot: CourseScheduleWidgetSnapshot,
            isConfigured: Boolean,
            widgetSize: SizeF?,
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_course_schedule)
            val weekdayName = getWeekdayName(snapshot.weekday)
            val widthProfile = resolveWidthProfile(widgetSize?.width ?: 0f)
            val dateText = buildDateText(
                weekdayName = weekdayName,
                currentWeek = snapshot.currentWeek,
                widthProfile = widthProfile,
            )
            val headerFontSize = when (widthProfile) {
                CourseWidgetWidthProfile.COMPACT ->
                    (snapshot.headerFontSizeSp - 2f).coerceAtLeast(11f)
                CourseWidgetWidthProfile.MEDIUM -> snapshot.headerFontSizeSp
                CourseWidgetWidthProfile.EXPANDED ->
                    (snapshot.headerFontSizeSp + 1f).coerceAtMost(24f)
            }
            val dateFontSize = when (widthProfile) {
                CourseWidgetWidthProfile.COMPACT ->
                    (headerFontSize - 3f).coerceAtLeast(8.5f)
                CourseWidgetWidthProfile.MEDIUM -> (headerFontSize - 3f).coerceAtLeast(9f)
                CourseWidgetWidthProfile.EXPANDED -> (headerFontSize - 2.5f).coerceAtLeast(10f)
            }
            val arrowFontSize = when (widthProfile) {
                CourseWidgetWidthProfile.COMPACT ->
                    (headerFontSize - 2.5f).coerceAtLeast(9.5f)
                CourseWidgetWidthProfile.MEDIUM -> (headerFontSize - 2f).coerceAtLeast(10f)
                CourseWidgetWidthProfile.EXPANDED -> (headerFontSize - 1.5f).coerceAtLeast(10.5f)
            }
            val emptyTextSize = when (widthProfile) {
                CourseWidgetWidthProfile.COMPACT ->
                    (snapshot.contentFontSizeSp - 1.5f).coerceAtLeast(9.5f)
                CourseWidgetWidthProfile.MEDIUM ->
                    (snapshot.contentFontSizeSp - 1f).coerceAtLeast(10f)
                CourseWidgetWidthProfile.EXPANDED -> snapshot.contentFontSizeSp.coerceAtLeast(10.5f)
            }

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
            applyArrowTouchAreaSizing(
                context = context,
                views = views,
                headerFontSizeSp = headerFontSize,
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
            if (Build.VERSION.SDK_INT > Build.VERSION_CODES.Q) {
                views.setScrollPosition(
                    R.id.course_widget_list,
                    resolveScrollAnchorIndex(
                        widgetHeightDp = widgetSize?.height ?: 0f,
                        snapshot = snapshot,
                    ),
                )
            }

            val defaultRoute = buildWidgetRoute(snapshot)
            val openRoutePendingIntent = buildOpenRoutePendingIntent(
                context = context,
                requestCode = widgetId * 10 + 1,
                widgetId = widgetId,
                route = defaultRoute,
            )
            views.setOnClickPendingIntent(R.id.course_widget_title, openRoutePendingIntent)
            views.setOnClickPendingIntent(R.id.course_widget_empty, openRoutePendingIntent)
            views.setOnClickPendingIntent(R.id.course_widget_empty_text, openRoutePendingIntent)
            views.setOnClickPendingIntent(
                R.id.course_widget_date,
                buildDateTextTapPendingIntent(context, widgetId),
            )
            views.setPendingIntentTemplate(
                R.id.course_widget_list,
                buildTemplateOpenRoutePendingIntent(
                    context = context,
                    requestCode = widgetId * 10 + 2,
                    widgetId = widgetId,
                ),
            )
            val prevDayIntent = buildNavigateDatePendingIntent(context, widgetId, -1)
            val nextDayIntent = buildNavigateDatePendingIntent(context, widgetId, 1)
            views.setOnClickPendingIntent(R.id.course_widget_prev_day_anchor, prevDayIntent)
            views.setOnClickPendingIntent(R.id.course_widget_prev_day, prevDayIntent)
            views.setOnClickPendingIntent(R.id.course_widget_next_day_anchor, nextDayIntent)
            views.setOnClickPendingIntent(R.id.course_widget_next_day, nextDayIntent)

            return views
        }

        private fun buildLoadingRemoteViews(context: Context): RemoteViews {
            return RemoteViews(context.packageName, R.layout.widget_course_schedule_loading)
        }

        private fun buildOpenRoutePendingIntent(
            context: Context,
            requestCode: Int,
            widgetId: Int,
            route: String,
        ): PendingIntent {
            val openIntent = Intent(context, CourseScheduleWidgetProvider::class.java).apply {
                action = ACTION_OPEN_ROUTE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
                putExtra(EXTRA_ROUTE, route)
            }
            return PendingIntent.getBroadcast(
                context,
                requestCode,
                openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun buildTemplateOpenRoutePendingIntent(
            context: Context,
            requestCode: Int,
            widgetId: Int,
        ): PendingIntent {
            val templateIntent = Intent(context, CourseScheduleWidgetProvider::class.java).apply {
                action = ACTION_OPEN_ROUTE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            }
            return PendingIntent.getBroadcast(
                context,
                requestCode,
                templateIntent,
                flags,
            )
        }

        private fun launchAppRoute(
            context: Context,
            route: String,
        ) {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: return
            launchIntent.putExtra(EXTRA_ROUTE, route)
            launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            context.startActivity(launchIntent)
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

        private fun buildDateTextTapPendingIntent(
            context: Context,
            widgetId: Int,
        ): PendingIntent {
            val tapIntent = Intent(context, CourseScheduleWidgetProvider::class.java).apply {
                action = ACTION_DATE_TEXT_TAP
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            }
            return PendingIntent.getBroadcast(
                context,
                widgetId * 10 + 5,
                tapIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun applyArrowTouchAreaSizing(
            context: Context,
            views: RemoteViews,
            headerFontSizeSp: Float,
        ) {
            val sideSp = (headerFontSizeSp * 1.6f + 2f).coerceIn(22f, 32f)
            val outerPadSp = sideSp - 6f
            val innerPadSp = 4f
            
            val outerPadPx = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_SP,
                outerPadSp,
                context.resources.displayMetrics,
            ).roundToInt()
            val innerPadPx = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_SP,
                innerPadSp,
                context.resources.displayMetrics,
            ).roundToInt()

            views.setViewPadding(R.id.course_widget_prev_day, outerPadPx, 0, innerPadPx, 0)
            views.setViewPadding(R.id.course_widget_next_day, innerPadPx, 0, outerPadPx, 0)
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
                        REFRESH_ALARM_TYPE,
                        triggerAtMillis,
                        refreshIntent,
                    )
                } else {
                    alarmManager.setExact(REFRESH_ALARM_TYPE, triggerAtMillis, refreshIntent)
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
                        REFRESH_ALARM_TYPE,
                        triggerAtMillis,
                        syncIntent,
                    )
                } else {
                    alarmManager.setExact(REFRESH_ALARM_TYPE, triggerAtMillis, syncIntent)
                }
            } catch (_: SecurityException) {
                scheduleBestEffort(alarmManager, triggerAtMillis, syncIntent)
            }
        }

        private fun scheduleBootstrapRefresh(context: Context) {
            val refreshIntent = buildBootstrapRefreshPendingIntent(context)
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val triggerAtMillis = System.currentTimeMillis() + BOOTSTRAP_REFRESH_DELAY_MILLIS
            alarmManager.cancel(refreshIntent)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    REFRESH_ALARM_TYPE,
                    triggerAtMillis,
                    refreshIntent,
                )
            } else {
                alarmManager.setExact(REFRESH_ALARM_TYPE, triggerAtMillis, refreshIntent)
            }
        }

        private fun scheduleBestEffort(
            alarmManager: AlarmManager,
            triggerAtMillis: Long,
            pendingIntent: PendingIntent,
        ) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(REFRESH_ALARM_TYPE, triggerAtMillis, pendingIntent)
            } else {
                alarmManager.set(REFRESH_ALARM_TYPE, triggerAtMillis, pendingIntent)
            }
        }

        private fun cancelScheduledRefreshes(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(buildRefreshPendingIntent(context))
            alarmManager.cancel(buildMidnightSyncPendingIntent(context))
            alarmManager.cancel(buildBootstrapRefreshPendingIntent(context))
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

        private fun buildBootstrapRefreshPendingIntent(context: Context): PendingIntent {
            val refreshIntent = Intent(context, CourseScheduleWidgetProvider::class.java).apply {
                action = ACTION_BOOTSTRAP_REFRESH
            }
            return PendingIntent.getBroadcast(
                context,
                BOOTSTRAP_REFRESH_REQUEST_CODE,
                refreshIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun getWeekdayName(dayOfWeek: Int): String {
            return if (dayOfWeek in 1..7) WEEKDAY_NAMES[dayOfWeek] else "今天"
        }

        private fun resolveScrollAnchorIndex(
            widgetHeightDp: Float,
            snapshot: CourseScheduleWidgetSnapshot,
        ): Int {
            if (snapshot.courses.isEmpty()) {
                return 0
            }
            val focusIndex = CourseScheduleWidgetData.resolveFocusIndex(snapshot)
            val visibleCount = estimateVisibleCourseCount(
                widgetHeightDp,
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

        private fun saveLastDateTapAt(
            widgetData: SharedPreferences,
            widgetId: Int,
            timestampMillis: Long,
        ) {
            widgetData.edit().putLong(lastDateTapAtKey(widgetId), timestampMillis).apply()
        }

        private fun consumeDateDoubleTap(
            widgetData: SharedPreferences,
            widgetId: Int,
            timestampMillis: Long,
        ): Boolean {
            val lastTapAt = widgetData.getLong(lastDateTapAtKey(widgetId), 0L)
            if (lastTapAt > 0L && timestampMillis - lastTapAt <= DATE_DOUBLE_TAP_WINDOW_MILLIS) {
                clearLastDateTapAt(widgetData, widgetId)
                return true
            }
            saveLastDateTapAt(widgetData, widgetId, timestampMillis)
            return false
        }

        private fun clearLastDateTapAt(
            widgetData: SharedPreferences,
            widgetId: Int,
        ) {
            widgetData.edit().remove(lastDateTapAtKey(widgetId)).apply()
        }

        private fun clearDisplayDateForAllWidgets(context: Context, widgetData: SharedPreferences) {
            val appWidgetIds = AppWidgetManager.getInstance(context).getAppWidgetIds(
                ComponentName(context, CourseScheduleWidgetProvider::class.java),
            )
            appWidgetIds.forEach { widgetId ->
                clearDisplayDate(widgetData, widgetId)
                clearLastDateTapAt(widgetData, widgetId)
            }
        }

        private fun buildDateText(
            weekdayName: String,
            currentWeek: Int,
            widthProfile: CourseWidgetWidthProfile,
        ): String {
            if (currentWeek <= 0) {
                return weekdayName
            }
            return when (widthProfile) {
                CourseWidgetWidthProfile.COMPACT -> weekdayName
                CourseWidgetWidthProfile.MEDIUM -> "$weekdayName · ${currentWeek}周"
                CourseWidgetWidthProfile.EXPANDED -> "$weekdayName · 第${currentWeek}周"
            }
        }

        private fun resolveWidthProfile(widthDp: Float): CourseWidgetWidthProfile {
            return when {
                widthDp in 0f..COMPACT_WIDGET_MAX_WIDTH_DP -> CourseWidgetWidthProfile.COMPACT
                widthDp in (COMPACT_WIDGET_MAX_WIDTH_DP + 0.01f)..MEDIUM_WIDGET_MAX_WIDTH_DP ->
                    CourseWidgetWidthProfile.MEDIUM
                else -> CourseWidgetWidthProfile.EXPANDED
            }
        }

        private fun saveWidgetSize(
            widgetData: SharedPreferences,
            widgetId: Int,
            widgetSize: SizeF?,
        ) {
            widgetData.edit().apply {
                if (widgetSize == null) {
                    remove(widgetWidthKey(widgetId))
                    remove(widgetHeightKey(widgetId))
                } else {
                    putFloat(widgetWidthKey(widgetId), widgetSize.width)
                    putFloat(widgetHeightKey(widgetId), widgetSize.height)
                }
            }.apply()
        }

        private fun shouldUseBootstrapLoadingPass(
            widgetData: SharedPreferences,
            widgetId: Int,
        ): Boolean {
            return Build.VERSION.SDK_INT <= Build.VERSION_CODES.Q &&
                !widgetData.getBoolean(bootstrapCompletedKey(widgetId), false)
        }

        private fun markBootstrapCompleted(
            widgetData: SharedPreferences,
            widgetId: Int,
        ) {
            widgetData.edit().putBoolean(bootstrapCompletedKey(widgetId), true).apply()
        }

        private fun clearWidgetSize(
            widgetData: SharedPreferences,
            widgetId: Int,
        ) {
            widgetData.edit()
                .remove(widgetWidthKey(widgetId))
                .remove(widgetHeightKey(widgetId))
                .apply()
        }

        private fun clearBootstrapCompleted(
            widgetData: SharedPreferences,
            widgetId: Int,
        ) {
            widgetData.edit().remove(bootstrapCompletedKey(widgetId)).apply()
        }

        private fun displayDateKey(widgetId: Int): String {
            return "$DISPLAY_DATE_KEY_PREFIX$widgetId"
        }

        private fun lastDateTapAtKey(widgetId: Int): String {
            return "$LAST_DATE_TAP_AT_KEY_PREFIX$widgetId"
        }

        internal fun widgetWidthKey(widgetId: Int): String {
            return "$WIDGET_WIDTH_DP_KEY_PREFIX$widgetId"
        }

        internal fun widgetHeightKey(widgetId: Int): String {
            return "$WIDGET_HEIGHT_DP_KEY_PREFIX$widgetId"
        }

        private fun bootstrapCompletedKey(widgetId: Int): String {
            return "$BOOTSTRAP_COMPLETED_KEY_PREFIX$widgetId"
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
            ACTION_BOOTSTRAP_REFRESH -> {
                refreshAllWidgets(context.applicationContext)
                return
            }
            ACTION_SYNC_TO_TODAY -> {
                val widgetData = HomeWidgetPlugin.getData(context)
                clearDisplayDateForAllWidgets(context, widgetData)
                refreshAllWidgets(context.applicationContext)
                return
            }
            ACTION_DATE_TEXT_TAP -> {
                val widgetId = intent.getIntExtra(
                    AppWidgetManager.EXTRA_APPWIDGET_ID,
                    AppWidgetManager.INVALID_APPWIDGET_ID,
                )
                if (widgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                    val widgetData = HomeWidgetPlugin.getData(context)
                    if (consumeDateDoubleTap(widgetData, widgetId, System.currentTimeMillis())) {
                        clearDisplayDate(widgetData, widgetId)
                    }
                    // 单击/双击日期都触发一次同步刷新，确保点击后内容即时更新。
                    performUpdate(
                        context = context,
                        appWidgetManager = AppWidgetManager.getInstance(context),
                        appWidgetIds = intArrayOf(widgetId),
                        widgetData = widgetData,
                    )
                    return
                }
            }
            ACTION_NAVIGATE_DATE -> {
                val widgetId = intent.getIntExtra(
                    AppWidgetManager.EXTRA_APPWIDGET_ID,
                    AppWidgetManager.INVALID_APPWIDGET_ID,
                )
                if (widgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                    val widgetData = HomeWidgetPlugin.getData(context)
                    clearLastDateTapAt(widgetData, widgetId)
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
            ACTION_OPEN_ROUTE -> {
                // 任何组件点击先刷新一轮，再进入应用页面。
                refreshAllWidgets(context.applicationContext)
                val route = intent.getStringExtra(EXTRA_ROUTE).orEmpty().ifBlank { "/table" }
                launchAppRoute(context, route)
                return
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
            clearLastDateTapAt(widgetData, widgetId)
            clearWidgetSize(widgetData, widgetId)
            clearBootstrapCompleted(widgetData, widgetId)
        }
        refreshAllWidgets(context.applicationContext)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        cancelScheduledRefreshes(context.applicationContext)
    }

    private enum class CourseWidgetWidthProfile {
        COMPACT,
        MEDIUM,
        EXPANDED,
    }
}
