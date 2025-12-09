import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/course.dart';
import '../models/course_schedule_config.dart';
import '../models/schedule_metadata.dart';
import 'notification_service.dart';

/// 课程表数据服务，负责课程和配置的持久化。
class CourseService {
  CourseService._();

  static final CourseService instance = CourseService._();

  static const String _coursesKey = 'course_service_courses';
  static const String _configKey = 'course_service_config';
  static const String _semesterStartKey = 'course_service_semester_start';
  static const String _maxWeekKey = 'course_service_max_week';
  static const String _tableNameKey = 'course_service_table_name';
  static const String _showWeekendKey = 'course_service_show_weekend';
  static const String _showNonCurrentWeekKey =
      'course_service_show_non_current_week';
  static const String _reminderEnabledKey = 'course_service_reminder_enabled';
  static const String _reminderTimeKey = 'course_service_reminder_time';
  static const String _reminderMethodKey = 'course_service_reminder_method';

  static const String _schedulesKey = 'course_service_schedules';
  static const String _currentScheduleIdKey =
      'course_service_current_schedule_id';

  /// 获取当前 Schedule ID
  Future<String> getCurrentScheduleId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currentScheduleIdKey) ?? 'default';
  }

  /// 获取当前 Schedule ID 对应的 Key
  Future<String> _getKey(String baseKey, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String targetId =
        scheduleId ?? (prefs.getString(_currentScheduleIdKey) ?? 'default');
    if (targetId == 'default') {
      return baseKey;
    }
    return '${baseKey}_$targetId';
  }

  /// 加载所有课程表元数据
  Future<List<ScheduleMetadata>> loadSchedules() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_schedulesKey);
    if (raw == null || raw.isEmpty) {
      // 如果没有多课表数据，假设存在一个默认课表
      return [ScheduleMetadata(id: 'default', name: '我的课表')];
    }
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => ScheduleMetadata.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('加载课程表列表失败: $e');
      return [ScheduleMetadata(id: 'default', name: '我的课表')];
    }
  }

  /// 保存课程表元数据列表
  Future<void> _saveSchedules(List<ScheduleMetadata> schedules) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = jsonEncode(schedules.map((s) => s.toJson()).toList());
    await prefs.setString(_schedulesKey, raw);
  }

  /// 创建新课程表
  Future<String> createSchedule(String name) async {
    final schedules = await loadSchedules();
    if (schedules.any((s) => s.name == name)) {
      throw Exception('课程表名称已存在');
    }
    final newId = const Uuid().v4();
    final newSchedule = ScheduleMetadata(id: newId, name: name);
    // 新建课表放到列表起始位置，保证新课表在界面上“置顶”可见
    schedules.insert(0, newSchedule);
    await _saveSchedules(schedules);
    return newId;
  }

  /// 更新课程表顺序
  Future<void> updateScheduleOrder(List<ScheduleMetadata> schedules) async {
    await _saveSchedules(schedules);
  }

  /// 切换当前课程表
  Future<void> switchSchedule(String id) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentScheduleIdKey, id);
  }

  /// 加载所有课程。
  Future<List<Course>> loadCourses([String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_coursesKey, scheduleId);
    final String? raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Course.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('加载课程失败: $e');
      return [];
    }
  }

  /// 保存所有课程。
  Future<void> saveCourses(List<Course> courses, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_coursesKey, scheduleId);
    final String raw = jsonEncode(courses.map((c) => c.toJson()).toList());
    await prefs.setString(key, raw);
    await _rescheduleReminders(scheduleId);
  }

  /// 加载课程表配置。
  Future<CourseScheduleConfig> loadConfig([String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_configKey, scheduleId);
    final String? raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return CourseScheduleConfig.njuDefaults();
    }
    try {
      return CourseScheduleConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('加载配置失败: $e');
      return CourseScheduleConfig.njuDefaults();
    }
  }

  /// 保存课程表配置。
  Future<void> saveConfig(
    CourseScheduleConfig config, [
    String? scheduleId,
  ]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_configKey, scheduleId);
    final String raw = jsonEncode(config.toJson());
    await prefs.setString(key, raw);
    await _rescheduleReminders(scheduleId);
  }

  /// 加载学期开始时间。
  Future<DateTime?> loadSemesterStart([String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_semesterStartKey, scheduleId);
    final int? millis = prefs.getInt(key);
    if (millis == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// 保存学期开始时间。
  Future<void> saveSemesterStart(DateTime date, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_semesterStartKey, scheduleId);
    await prefs.setInt(key, date.millisecondsSinceEpoch);
    await _rescheduleReminders(scheduleId);
  }

  /// 加载最大周数。
  Future<int> loadMaxWeek([String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_maxWeekKey, scheduleId);
    return prefs.getInt(key) ?? 20;
  }

  /// 保存最大周数。
  Future<void> saveMaxWeek(int maxWeek, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_maxWeekKey, scheduleId);
    await prefs.setInt(key, maxWeek);
  }

  /// 加载课程表名称。
  Future<String> loadTableName([String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_tableNameKey, scheduleId);

    String? name = prefs.getString(key);
    if (name == null) {
      // 尝试从 metadata 获取
      final targetId =
          scheduleId ?? (prefs.getString(_currentScheduleIdKey) ?? 'default');
      final schedules = await loadSchedules();
      final schedule = schedules.firstWhere(
        (s) => s.id == targetId,
        orElse: () => ScheduleMetadata(id: 'default', name: '我的课表'),
      );
      name = schedule.name;
    }
    return name;
  }

  /// 保存课程表名称。
  Future<void> saveTableName(String name, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_tableNameKey, scheduleId);
    await prefs.setString(key, name);

    final targetId =
        scheduleId ?? (prefs.getString(_currentScheduleIdKey) ?? 'default');
    final schedules = await loadSchedules();
    final index = schedules.indexWhere((s) => s.id == targetId);
    if (index != -1) {
      // 检查重名（排除自己）
      if (schedules.any((s) => s.name == name && s.id != targetId)) {
        throw Exception('课程表名称已存在');
      }
      schedules[index] = ScheduleMetadata(id: targetId, name: name);
      await _saveSchedules(schedules);
    }
  }

  /// 加载是否显示周末。
  Future<bool> loadShowWeekend([String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_showWeekendKey, scheduleId);
    return prefs.getBool(key) ?? false;
  }

  /// 保存是否显示周末。
  Future<void> saveShowWeekend(bool show, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_showWeekendKey, scheduleId);
    await prefs.setBool(key, show);
  }

  /// 加载是否显示非本周课程。
  Future<bool> loadShowNonCurrentWeek([String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_showNonCurrentWeekKey, scheduleId);
    return prefs.getBool(key) ?? true;
  }

  /// 保存是否显示非本周课程。
  Future<void> saveShowNonCurrentWeek(bool show, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_showNonCurrentWeekKey, scheduleId);
    await prefs.setBool(key, show);
  }

  /// 删除课程表
  Future<void> deleteSchedules(List<String> ids) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final schedules = await loadSchedules();
    final currentId = await getCurrentScheduleId();

    // 过滤掉要删除的 ID
    schedules.removeWhere((s) => ids.contains(s.id));

    // 如果删除了当前课程表，或列表被清空，就需要重新设置当前课程表
    if (ids.contains(currentId) || schedules.isEmpty) {
      if (schedules.isNotEmpty) {
        await switchSchedule(schedules.first.id);
      } else {
        // 如果删空了，自动追加一个默认课表并切换至该课表
        final newId = const Uuid().v4();
        schedules.add(ScheduleMetadata(id: newId, name: '我的课表'));
        await switchSchedule(newId);

        // 初始化默认配置
        final now = DateTime.now();
        DateTime defaultStart;
        if (now.month >= 1 && now.month <= 7) {
          // 上半年，默认2月开学
          defaultStart = DateTime(now.year, 2, 20);
        } else {
          // 下半年，默认9月开学
          defaultStart = DateTime(now.year, 9, 1);
        }
        await saveSemesterStart(defaultStart, newId);
        await saveConfig(CourseScheduleConfig.njuDefaults(), newId);
        await saveMaxWeek(20, newId);
        await saveShowWeekend(false, newId);
        await saveShowNonCurrentWeek(true, newId);
      }
    }

    await _saveSchedules(schedules);

    // 清理相关数据 (可选，为了保持存储整洁)
    for (final id in ids) {
      await prefs.remove('${_coursesKey}_$id');
      await prefs.remove('${_configKey}_$id');
      await prefs.remove('${_semesterStartKey}_$id');
      await prefs.remove('${_maxWeekKey}_$id');
      await prefs.remove('${_tableNameKey}_$id');
      await prefs.remove('${_showWeekendKey}_$id');
      await prefs.remove('${_showNonCurrentWeekKey}_$id');
      await prefs.remove('${_reminderEnabledKey}_$id');
      await prefs.remove('${_reminderTimeKey}_$id');
      await prefs.remove('${_reminderMethodKey}_$id');
    }
  }

  /// 加载是否启用课程提醒
  Future<bool> loadReminderEnabled([String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final String key = await _getKey(_reminderEnabledKey, scheduleId);
    return prefs.getBool(key) ?? false;
  }

  /// 保存是否启用课程提醒
  Future<void> saveReminderEnabled(bool enabled, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_reminderEnabledKey, scheduleId);
    await prefs.setBool(key, enabled);
    await _rescheduleReminders(scheduleId);
  }

  /// 加载课程提醒时间（分钟）
  Future<int> loadReminderTime([String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final String key = await _getKey(_reminderTimeKey, scheduleId);
    return prefs.getInt(key) ?? 15;
  }

  /// 保存课程提醒时间
  Future<void> saveReminderTime(int minutes, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_reminderTimeKey, scheduleId);
    await prefs.setInt(key, minutes);
    await _rescheduleReminders(scheduleId);
  }

  /// 加载课程提醒方式
  Future<String> loadReminderMethod([String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final String key = await _getKey(_reminderMethodKey, scheduleId);
    return prefs.getString(key) ?? 'notification';
  }

  /// 保存课程提醒方式
  Future<void> saveReminderMethod(String method, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_reminderMethodKey, scheduleId);
    await prefs.setString(key, method);
    await _rescheduleReminders(scheduleId);
  }

  /// 批量保存课程提醒设置
  Future<void> saveAllReminderSettings({
    required bool enabled,
    required int time,
    required String method,
    String? scheduleId,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final enabledKey = await _getKey(_reminderEnabledKey, scheduleId);
    final timeKey = await _getKey(_reminderTimeKey, scheduleId);
    final methodKey = await _getKey(_reminderMethodKey, scheduleId);

    await prefs.setBool(enabledKey, enabled);
    await prefs.setInt(timeKey, time);
    await prefs.setString(methodKey, method);

    await _rescheduleReminders(scheduleId);
  }

  /// 初始化/刷新提醒（通常在应用启动时调用）
  /// 初始化/刷新提醒（通常在应用启动时调用）
  /// - 默认行为：如果方法为 `alarm` 且已存在原生闹钟 ID，则不在启动时重新调度，避免重复创建。
  /// - 如果需要强制重调度（例如用户修改了课程或提醒设置），请传入 `force = true`。
  Future<void> initializeReminders({bool force = false}) async {
    if (!force) {
      final method = await loadReminderMethod();
      if (method == 'alarm') {
        final nativeIds = await NotificationService.instance
            .getNativeAlarmIds();
        if (nativeIds.isNotEmpty) {
          debugPrint(
            'Native alarms already exist; skipping reschedule on startup.',
          );
          return;
        }
      }
    }
    await _rescheduleReminders();
  }

  /// 重新调度提醒
  Future<void> _rescheduleReminders([String? scheduleId]) async {
    final enabled = await loadReminderEnabled(scheduleId);
    if (!enabled) {
      await NotificationService.instance.cancelAllReminders();
      return;
    }

    // 确保已请求通知权限
    await NotificationService.instance.requestPermissions();

    final courses = await loadCourses(scheduleId);
    final config = await loadConfig(scheduleId);
    final semesterStart = await loadSemesterStart(scheduleId);
    final reminderTime = await loadReminderTime(scheduleId);
    final reminderMethod = await loadReminderMethod(scheduleId);

    // 如果未设置开学时间，使用默认策略（与 TablePage/deleteSchedules 逻辑尽量保持一致）
    final DateTime effectiveStart =
        semesterStart ??
        (() {
          final now = DateTime.now();
          if (now.month >= 1 && now.month <= 7) {
            return DateTime(now.year, 2, 20);
          } else {
            return DateTime(now.year, 9, 1);
          }
        })();

    await NotificationService.instance.scheduleReminders(
      courses: courses,
      config: config,
      semesterStart: effectiveStart,
      reminderMinutes: reminderTime,
      method: reminderMethod,
    );
  }
}
