package com.lulo.dormdevise

import android.content.SharedPreferences
import org.json.JSONArray
import java.util.Calendar

internal data class CourseScheduleWidgetItem(
    val name: String,
    val location: String,
    val startSection: Int,
    val sectionCount: Int,
    val startTime: String,
    val endTime: String,
    val indicatorColor: Int,
) {
    val endSection: Int
        get() = startSection + sectionCount - 1

    val sectionLabel: String
        get() = if (sectionCount > 1) {
            "$startSection-$endSection 节"
        } else {
            "$startSection 节"
        }

    val stableId: Long
        get() = (
            (name.hashCode().toLong() and 0xFFFFFFFFL) shl 32
        ) or (
            (startSection.toLong() and 0xFFFFL) shl 16
        ) or (
            sectionCount.toLong() and 0xFFFFL
        )
}

internal data class CourseScheduleWidgetSnapshot(
    val currentWeek: Int,
    val weekday: Int,
    val courses: List<CourseScheduleWidgetItem>,
    val displayDateMillis: Long,
    val reminderMinutes: Int,
    val headerFontSizeSp: Float,
    val contentFontSizeSp: Float,
)

internal enum class CourseScheduleItemState {
    UPCOMING,
    ONGOING,
    FINISHED,
}

private data class CourseScheduleRawCourse(
    val name: String,
    val color: Int,
    val sessions: List<CourseScheduleRawSession>,
)

private data class CourseScheduleRawSession(
    val weekday: Int,
    val startSection: Int,
    val sectionCount: Int,
    val location: String,
    val startWeek: Int,
    val endWeek: Int,
    val weekType: Int,
    val customWeeks: List<Int>,
)

private data class CourseScheduleSectionTime(
    val start: String,
    val end: String,
)

internal object CourseScheduleWidgetData {
    private const val DEFAULT_HEADER_FONT_SIZE = 14
    private const val DEFAULT_CONTENT_FONT_SIZE = 12
    private const val DEFAULT_REMINDER_MINUTES = 0
    private const val MINUTE_MILLIS = 60_000L

    private val LEGACY_INDICATOR_COLORS = intArrayOf(
        0xFF4285F4.toInt(),
        0xFF34A853.toInt(),
        0xFFFBBC05.toInt(),
        0xFFEA4335.toInt(),
        0xFF9C27B0.toInt(),
        0xFF9E9E9E.toInt(),
    )

    fun buildSnapshot(
        widgetData: SharedPreferences,
        displayDate: Calendar = Calendar.getInstance(),
    ): CourseScheduleWidgetSnapshot {
        val targetDate = Calendar.getInstance().apply {
            timeInMillis = displayDate.timeInMillis
        }
        val reminderMinutes = widgetData
            .getInt("course_widget_reminder_minutes", DEFAULT_REMINDER_MINUTES)
            .coerceIn(0, 60)
        val headerFontSizeSp = widgetData
            .getInt("course_widget_header_font_size", DEFAULT_HEADER_FONT_SIZE)
            .coerceIn(10, 24)
            .toFloat()
        val contentFontSizeSp = widgetData
            .getInt("course_widget_content_font_size", DEFAULT_CONTENT_FONT_SIZE)
            .coerceIn(9, 20)
            .toFloat()
        val currentWeek = resolveCurrentWeek(widgetData, targetDate)
        val weekday = resolveWeekday(targetDate)
        val todayCourses = if (currentWeek > 0) {
            val sections = parseSections(widgetData.getString("course_widget_sections", null))
            val allCourses = parseAllCourses(widgetData.getString("course_widget_all_courses", null))
            if (sections.isNotEmpty() && allCourses.isNotEmpty()) {
                buildTodayCourses(
                    courses = allCourses,
                    sections = sections,
                    currentWeek = currentWeek,
                    weekday = weekday,
                )
            } else if (isSameDay(targetDate, Calendar.getInstance())) {
                parseLegacyTodayCourses(widgetData.getString("course_widget_today_courses", null))
            } else {
                emptyList()
            }
        } else {
            emptyList()
        }

        return CourseScheduleWidgetSnapshot(
            currentWeek = currentWeek,
            weekday = weekday,
            courses = todayCourses,
            displayDateMillis = targetDate.timeInMillis,
            reminderMinutes = reminderMinutes,
            headerFontSizeSp = headerFontSizeSp,
            contentFontSizeSp = contentFontSizeSp,
        )
    }

    fun resolveFocusIndex(
        snapshot: CourseScheduleWidgetSnapshot,
        now: Calendar = Calendar.getInstance(),
    ): Int {
        if (snapshot.courses.isEmpty()) return 0

        val ongoingIndex = snapshot.courses.indexOfFirst { course ->
            resolveState(course, snapshot, now) == CourseScheduleItemState.ONGOING
        }
        if (ongoingIndex >= 0) return ongoingIndex

        val upcomingIndex = snapshot.courses.indexOfFirst { course ->
            resolveState(course, snapshot, now) == CourseScheduleItemState.UPCOMING
        }
        return if (upcomingIndex >= 0) upcomingIndex else 0
    }

    fun resolveState(
        item: CourseScheduleWidgetItem,
        snapshot: CourseScheduleWidgetSnapshot,
        now: Calendar = Calendar.getInstance(),
    ): CourseScheduleItemState {
        val displayDate = Calendar.getInstance().apply {
            timeInMillis = snapshot.displayDateMillis
        }
        if (!isSameDay(displayDate, now)) {
            return if (displayDate.before(dayStart(now))) {
                CourseScheduleItemState.FINISHED
            } else {
                CourseScheduleItemState.UPCOMING
            }
        }

        val nowMillis = now.timeInMillis
        val startMillis = parseTodayTimeMillis(item.startTime, now) ?: return CourseScheduleItemState.UPCOMING
        val endMillis = parseTodayTimeMillis(item.endTime, now) ?: return CourseScheduleItemState.UPCOMING

        return when {
            nowMillis >= endMillis -> CourseScheduleItemState.FINISHED
            nowMillis >= startMillis -> CourseScheduleItemState.ONGOING
            else -> CourseScheduleItemState.UPCOMING
        }
    }

    fun computeNextRefreshAtMillis(
        snapshot: CourseScheduleWidgetSnapshot,
        now: Calendar = Calendar.getInstance(),
    ): Long? {
        val nowMillis = now.timeInMillis
        val reminderWindowMillis = snapshot.reminderMinutes.coerceAtLeast(0) * MINUTE_MILLIS
        var nextMillis: Long? = null
        val displayDate = Calendar.getInstance().apply {
            timeInMillis = snapshot.displayDateMillis
        }
        if (!isSameDay(displayDate, now)) {
            return nextMillis
        }

        snapshot.courses.forEach { item ->
            val startMillis = parseTodayTimeMillis(item.startTime, now)
            val endMillis = parseTodayTimeMillis(item.endTime, now)

            if (startMillis != null && startMillis > nowMillis) {
                nextMillis = minOfNullable(nextMillis, startMillis)

                if (reminderWindowMillis > 0L) {
                    val reminderStartMillis = startMillis - reminderWindowMillis
                    if (nowMillis < reminderStartMillis) {
                        nextMillis = minOfNullable(nextMillis, reminderStartMillis)
                    } else {
                        val nextMinuteTick = ((nowMillis / MINUTE_MILLIS) + 1) * MINUTE_MILLIS
                        if (nextMinuteTick < startMillis) {
                            nextMillis = minOfNullable(nextMillis, nextMinuteTick)
                        }
                    }
                }
            }
            if (endMillis != null && endMillis > nowMillis) {
                nextMillis = minOfNullable(nextMillis, endMillis)
            }
        }

        return nextMillis?.plus(1_000L)
    }

    private fun resolveCurrentWeek(
        widgetData: SharedPreferences,
        now: Calendar,
    ): Int {
        val semesterStartMillis = widgetData
            .getString("course_widget_semester_start_millis", null)
            ?.toLongOrNull()
        val maxWeek = widgetData.getInt("course_widget_max_week", 0)
        if (semesterStartMillis == null || maxWeek <= 0) {
            return widgetData.getInt("course_widget_current_week", 0)
        }

        val semesterStartMonday = mondayOf(Calendar.getInstance().apply {
            timeInMillis = semesterStartMillis
        })
        val todayMonday = mondayOf(Calendar.getInstance().apply {
            timeInMillis = now.timeInMillis
        })
        val daysDiff = (todayMonday.timeInMillis - semesterStartMonday.timeInMillis) / MILLIS_PER_DAY
        val currentWeek = (daysDiff / 7).toInt() + 1
        return if (currentWeek in 1..maxWeek) currentWeek else 0
    }

    private fun resolveWeekday(calendar: Calendar): Int {
        return when (calendar.get(Calendar.DAY_OF_WEEK)) {
            Calendar.SUNDAY -> 7
            else -> calendar.get(Calendar.DAY_OF_WEEK) - 1
        }
    }

    private fun buildTodayCourses(
        courses: List<CourseScheduleRawCourse>,
        sections: List<CourseScheduleSectionTime>,
        currentWeek: Int,
        weekday: Int,
    ): List<CourseScheduleWidgetItem> {
        return buildList {
            courses.forEach { course ->
                course.sessions.forEach { session ->
                    if (!session.occursInWeek(currentWeek) || session.weekday != weekday) {
                        return@forEach
                    }

                    val startIndex = session.startSection - 1
                    val endIndex = startIndex + session.sectionCount - 1
                    add(
                        CourseScheduleWidgetItem(
                            name = course.name,
                            location = session.location,
                            startSection = session.startSection,
                            sectionCount = session.sectionCount,
                            startTime = sections.getOrNull(startIndex)?.start ?: "",
                            endTime = sections.getOrNull(endIndex)?.end ?: "",
                            indicatorColor = if (course.color != 0) {
                                course.color
                            } else {
                                LEGACY_INDICATOR_COLORS.first()
                            },
                        ),
                    )
                }
            }
        }.sortedBy { it.startSection }
    }

    private fun parseAllCourses(json: String?): List<CourseScheduleRawCourse> {
        if (json.isNullOrBlank()) return emptyList()

        return try {
            val array = JSONArray(json)
            buildList {
                for (index in 0 until array.length()) {
                    val obj = array.getJSONObject(index)
                    val sessionsArray = obj.optJSONArray("sessions") ?: JSONArray()
                    val sessions = buildList {
                        for (sessionIndex in 0 until sessionsArray.length()) {
                            val sessionObj = sessionsArray.getJSONObject(sessionIndex)
                            add(
                                CourseScheduleRawSession(
                                    weekday = sessionObj.optInt("weekday", 1),
                                    startSection = sessionObj.optInt("startSection", 1),
                                    sectionCount = sessionObj.optInt("sectionCount", 1),
                                    location = sessionObj.optString("location", ""),
                                    startWeek = sessionObj.optInt("startWeek", 1),
                                    endWeek = sessionObj.optInt("endWeek", 1),
                                    weekType = sessionObj.optInt("weekType", 0),
                                    customWeeks = parseCustomWeeks(sessionObj.optJSONArray("customWeeks")),
                                ),
                            )
                        }
                    }
                    add(
                        CourseScheduleRawCourse(
                            name = obj.optString("name", ""),
                            color = obj.optInt("color", LEGACY_INDICATOR_COLORS.first()),
                            sessions = sessions,
                        ),
                    )
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun parseSections(json: String?): List<CourseScheduleSectionTime> {
        if (json.isNullOrBlank()) return emptyList()

        return try {
            val array = JSONArray(json)
            buildList {
                for (index in 0 until array.length()) {
                    val obj = array.getJSONObject(index)
                    add(
                        CourseScheduleSectionTime(
                            start = obj.optString("start", ""),
                            end = obj.optString("end", ""),
                        ),
                    )
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun parseLegacyTodayCourses(json: String?): List<CourseScheduleWidgetItem> {
        if (json.isNullOrBlank()) return emptyList()

        return try {
            val array = JSONArray(json)
            buildList {
                for (index in 0 until array.length()) {
                    val obj = array.getJSONObject(index)
                    add(
                        CourseScheduleWidgetItem(
                            name = obj.optString("name", ""),
                            location = obj.optString("location", ""),
                            startSection = obj.optInt("startSection", 1),
                            sectionCount = obj.optInt("sectionCount", 1),
                            startTime = obj.optString("startTime", ""),
                            endTime = obj.optString("endTime", ""),
                            indicatorColor = obj.optInt(
                                "indicatorColor",
                                LEGACY_INDICATOR_COLORS[
                                    obj.optInt("colorIndex", 0).mod(LEGACY_INDICATOR_COLORS.size)
                                ],
                            ),
                        ),
                    )
                }
            }.sortedBy { it.startSection }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun parseCustomWeeks(array: JSONArray?): List<Int> {
        if (array == null) return emptyList()
        return buildList {
            for (index in 0 until array.length()) {
                add(array.optInt(index))
            }
        }
    }

    private fun CourseScheduleRawSession.occursInWeek(week: Int): Boolean {
        if (customWeeks.isNotEmpty()) {
            return customWeeks.contains(week)
        }
        if (week < startWeek || week > endWeek) {
            return false
        }
        return when (weekType) {
            1 -> week % 2 == 1
            2 -> week % 2 == 0
            else -> true
        }
    }

    private fun parseTodayTimeMillis(timeText: String, base: Calendar): Long? {
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

    private fun mondayOf(calendar: Calendar): Calendar {
        return Calendar.getInstance().apply {
            timeInMillis = calendar.timeInMillis
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            add(Calendar.DAY_OF_MONTH, -(resolveWeekday(this) - 1))
        }
    }

    private fun dayStart(calendar: Calendar): Calendar {
        return Calendar.getInstance().apply {
            timeInMillis = calendar.timeInMillis
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
    }

    private fun isSameDay(a: Calendar, b: Calendar): Boolean {
        return a.get(Calendar.YEAR) == b.get(Calendar.YEAR) &&
            a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)
    }

    private fun minOfNullable(current: Long?, candidate: Long): Long {
        return current?.coerceAtMost(candidate) ?: candidate
    }

    private const val MILLIS_PER_DAY = 24 * 60 * 60 * 1000L
}
