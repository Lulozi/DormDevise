import 'dart:async';
import 'dart:convert';

import 'package:dormdevise/services/course_service.dart';
import 'package:dormdevise/utils/course_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 课表桌面组件的数据模型
class CourseWidgetItem {
  const CourseWidgetItem({
    required this.name,
    required this.location,
    required this.startSection,
    required this.sectionCount,
    required this.startTime,
    required this.endTime,
    required this.indicatorColor,
  });

  final String name;
  final String location;
  final int startSection;
  final int sectionCount;
  final String startTime;
  final String endTime;
  final int indicatorColor;

  Map<String, dynamic> toJson() => {
    'name': name,
    'location': location,
    'startSection': startSection,
    'sectionCount': sectionCount,
    'startTime': startTime,
    'endTime': endTime,
    'indicatorColor': indicatorColor,
  };
}

/// 课表组件显示设置。
class CourseWidgetDisplaySettings {
  const CourseWidgetDisplaySettings({
    required this.headerFontSize,
    required this.contentFontSize,
    required this.reminderMinutes,
  });

  static const int minHeaderFontSize = 10;
  static const int maxHeaderFontSize = 24;
  static const int minContentFontSize = 9;
  static const int maxContentFontSize = 20;
  static const int minReminderMinutes = 0;
  static const int maxReminderMinutes = 60;
  static const int reminderStepMinutes = 5;

  static const int defaultHeaderFontSize = 14;
  static const int defaultContentFontSize = 12;
  static const int defaultReminderMinutes = 0;

  final int headerFontSize;
  final int contentFontSize;
  final int reminderMinutes;

  CourseWidgetDisplaySettings normalized() {
    return CourseWidgetDisplaySettings(
      headerFontSize: headerFontSize
          .clamp(minHeaderFontSize, maxHeaderFontSize)
          .toInt(),
      contentFontSize: contentFontSize
          .clamp(minContentFontSize, maxContentFontSize)
          .toInt(),
      reminderMinutes: _normalizeReminderMinutes(reminderMinutes),
    );
  }

  static int _normalizeReminderMinutes(int minutes) {
    final int clamped = minutes.clamp(minReminderMinutes, maxReminderMinutes);
    if (clamped == 0) {
      return 0;
    }
    final int snapped =
        (clamped / reminderStepMinutes).round() * reminderStepMinutes;
    return snapped.clamp(minReminderMinutes, maxReminderMinutes).toInt();
  }
}

/// 课表桌面组件服务，负责将课程数据同步到 Android 桌面组件。
class CourseWidgetService {
  CourseWidgetService._();

  static final CourseWidgetService instance = CourseWidgetService._();

  static const String _androidProviderQualified =
      'com.lulo.dormdevise.CourseScheduleWidgetProvider';
  static const String _androidProviderName = 'CourseScheduleWidgetProvider';
  static const MethodChannel _homeWidgetChannel = MethodChannel(
    'dormdevise/home_widget',
  );
  static const String _headerFontSizeKey = 'course_widget_header_font_size';
  static const String _contentFontSizeKey = 'course_widget_content_font_size';
  static const String _reminderMinutesKey = 'course_widget_reminder_minutes';

  bool _initialized = false;

  /// 初始化服务
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await syncWidget();
  }

  /// 读取课表组件显示设置。
  Future<CourseWidgetDisplaySettings> loadDisplaySettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return CourseWidgetDisplaySettings(
      headerFontSize:
          prefs.getInt(_headerFontSizeKey) ??
          CourseWidgetDisplaySettings.defaultHeaderFontSize,
      contentFontSize:
          prefs.getInt(_contentFontSizeKey) ??
          CourseWidgetDisplaySettings.defaultContentFontSize,
      reminderMinutes:
          prefs.getInt(_reminderMinutesKey) ??
          CourseWidgetDisplaySettings.defaultReminderMinutes,
    ).normalized();
  }

  /// 保存课表组件显示设置，并触发组件刷新。
  Future<void> saveDisplaySettings(
    CourseWidgetDisplaySettings settings, {
    bool syncWidgetAfterSave = true,
  }) async {
    final CourseWidgetDisplaySettings normalized = settings.normalized();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_headerFontSizeKey, normalized.headerFontSize);
    await prefs.setInt(_contentFontSizeKey, normalized.contentFontSize);
    await prefs.setInt(_reminderMinutesKey, normalized.reminderMinutes);
    if (syncWidgetAfterSave) {
      await syncWidget();
    }
  }

  /// 同步课程数据到桌面组件
  Future<void> syncWidget({bool resetDisplayDateToToday = false}) async {
    try {
      final now = DateTime.now();
      final weekday = now.weekday; // 1=周一, 7=周日
      final CourseWidgetDisplaySettings displaySettings =
          await loadDisplaySettings();

      // 计算当前周次
      final semesterStart = await CourseService.instance.loadSemesterStart();
      final tableName = await CourseService.instance.loadTableName();
      final allCourses = await CourseService.instance.loadCourses();
      final hasConfiguredSchedule =
          semesterStart != null || allCourses.isNotEmpty;
      int currentWeek = 0;
      if (semesterStart != null) {
        final semesterStartMonday = _getWeekStartMonday(semesterStart);
        final todayMonday = _getWeekStartMonday(now);
        final daysDiff = todayMonday.difference(semesterStartMonday).inDays;
        currentWeek = (daysDiff ~/ 7) + 1;

        final maxWeek = await CourseService.instance.loadMaxWeek();
        if (currentWeek < 1 || currentWeek > maxWeek) {
          currentWeek = 0; // 不在学期范围内
        }
      }

      // 获取今日课程
      final courses = allCourses;
      final config = await CourseService.instance.loadConfig();
      final sections = config.generateSections();
      final maxWeek = await CourseService.instance.loadMaxWeek();

      final todayCourses = <CourseWidgetItem>[];

      if (currentWeek > 0) {
        for (final course in courses) {
          final sessionsForWeek = course.sessionsForWeek(currentWeek);
          for (final session in sessionsForWeek) {
            if (session.weekday == weekday) {
              // 获取时间
              String startTime = '';
              String endTime = '';

              final startIdx = session.startSection - 1;
              final endIdx = startIdx + session.sectionCount - 1;

              if (startIdx >= 0 && startIdx < sections.length) {
                final start = sections[startIdx].start;
                startTime =
                    '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
              }
              if (endIdx >= 0 && endIdx < sections.length) {
                final end = sections[endIdx].end;
                endTime =
                    '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
              }

              todayCourses.add(
                CourseWidgetItem(
                  name: course.name,
                  location: session.location,
                  startSection: session.startSection,
                  sectionCount: session.sectionCount,
                  startTime: startTime,
                  endTime: endTime,
                  indicatorColor: _resolveIndicatorColor(
                    course.color,
                  ).toARGB32(),
                ),
              );
            }
          }
        }

        // 按开始节次排序
        todayCourses.sort((a, b) => a.startSection.compareTo(b.startSection));
      }

      // 保存数据到 SharedPreferences
      final coursesJson = jsonEncode(
        todayCourses.map((e) => e.toJson()).toList(),
      );
      await HomeWidget.saveWidgetData<String>(
        'course_widget_today_courses',
        coursesJson,
      );
      await HomeWidget.saveWidgetData<int>(
        'course_widget_current_week',
        currentWeek,
      );
      await HomeWidget.saveWidgetData<int>('course_widget_weekday', weekday);
      await HomeWidget.saveWidgetData<String>(
        'course_widget_all_courses',
        jsonEncode(allCourses.map((course) => course.toJson()).toList()),
      );
      await HomeWidget.saveWidgetData<String>(
        'course_widget_sections',
        jsonEncode(
          sections
              .map(
                (section) => <String, String>{
                  'start':
                      '${section.start.hour.toString().padLeft(2, '0')}:${section.start.minute.toString().padLeft(2, '0')}',
                  'end':
                      '${section.end.hour.toString().padLeft(2, '0')}:${section.end.minute.toString().padLeft(2, '0')}',
                },
              )
              .toList(),
        ),
      );
      await HomeWidget.saveWidgetData<String>(
        'course_widget_semester_start_millis',
        semesterStart?.millisecondsSinceEpoch.toString() ?? '',
      );
      await HomeWidget.saveWidgetData<int>('course_widget_max_week', maxWeek);
      await HomeWidget.saveWidgetData<String>(
        'course_widget_table_name',
        tableName,
      );
      await HomeWidget.saveWidgetData<bool>(
        'course_widget_is_configured',
        hasConfiguredSchedule,
      );
      await HomeWidget.saveWidgetData<int>(
        _headerFontSizeKey,
        displaySettings.headerFontSize,
      );
      await HomeWidget.saveWidgetData<int>(
        _contentFontSizeKey,
        displaySettings.contentFontSize,
      );
      await HomeWidget.saveWidgetData<int>(
        _reminderMinutesKey,
        displaySettings.reminderMinutes,
      );

      // 发生课程表导入、编辑或保存时，强制把组件视图切回今天再刷新。
      if (resetDisplayDateToToday) {
        try {
          await _homeWidgetChannel.invokeMethod<void>(
            'syncCourseWidgetToToday',
          );
        } on MissingPluginException {
          await HomeWidget.updateWidget(
            name: _androidProviderName,
            qualifiedAndroidName: _androidProviderQualified,
          );
        } on PlatformException {
          await HomeWidget.updateWidget(
            name: _androidProviderName,
            qualifiedAndroidName: _androidProviderQualified,
          );
        } catch (_) {
          await HomeWidget.updateWidget(
            name: _androidProviderName,
            qualifiedAndroidName: _androidProviderQualified,
          );
        }
      } else {
        await HomeWidget.updateWidget(
          name: _androidProviderName,
          qualifiedAndroidName: _androidProviderQualified,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('同步课表组件失败: $e\n$stackTrace');
    }
  }

  /// 获取某天所在周的周一日期
  DateTime _getWeekStartMonday(DateTime date) {
    final dayOfWeek = date.weekday;
    return DateTime(date.year, date.month, date.day - (dayOfWeek - 1));
  }

  /// 组件颜色直接复用课程背景色，避免桌面端再维护一套独立的预设列表。
  Color _resolveIndicatorColor(Color color) {
    if (color.a == 0) {
      return kCoursePresetColors.first;
    }
    return color;
  }

  /// 释放资源
  void dispose() {
    _initialized = false;
  }
}
