import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/course.dart';
import '../models/course_schedule_config.dart';

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

  /// 加载所有课程。
  Future<List<Course>> loadCourses() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_coursesKey);
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
  Future<void> saveCourses(List<Course> courses) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = jsonEncode(courses.map((c) => c.toJson()).toList());
    await prefs.setString(_coursesKey, raw);
  }

  /// 加载课程表配置。
  Future<CourseScheduleConfig> loadConfig() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_configKey);
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
  Future<void> saveConfig(CourseScheduleConfig config) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = jsonEncode(config.toJson());
    await prefs.setString(_configKey, raw);
  }

  /// 加载学期开始时间。
  Future<DateTime?> loadSemesterStart() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? millis = prefs.getInt(_semesterStartKey);
    if (millis == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// 保存学期开始时间。
  Future<void> saveSemesterStart(DateTime date) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_semesterStartKey, date.millisecondsSinceEpoch);
  }

  /// 加载最大周数。
  Future<int> loadMaxWeek() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_maxWeekKey) ?? 20;
  }

  /// 保存最大周数。
  Future<void> saveMaxWeek(int maxWeek) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxWeekKey, maxWeek);
  }

  /// 加载课程表名称。
  Future<String> loadTableName() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tableNameKey) ?? '我的课表';
  }

  /// 保存课程表名称。
  Future<void> saveTableName(String name) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tableNameKey, name);
  }

  /// 加载是否显示周末。
  Future<bool> loadShowWeekend() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showWeekendKey) ?? false;
  }

  /// 保存是否显示周末。
  Future<void> saveShowWeekend(bool show) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showWeekendKey, show);
  }

  /// 加载是否显示非本周课程。
  Future<bool> loadShowNonCurrentWeek() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showNonCurrentWeekKey) ?? true;
  }

  /// 保存是否显示非本周课程。
  Future<void> saveShowNonCurrentWeek(bool show) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showNonCurrentWeekKey, show);
  }
}
