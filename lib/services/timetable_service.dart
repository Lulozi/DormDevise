import 'dart:convert';
import 'package:dormdevise/models/course.dart';
import 'package:dormdevise/models/timetable_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 课程表数据服务，负责课程和配置的持久化存储
class TimetableService {
  static const String _coursesKey = 'timetable_courses';
  static const String _configKey = 'timetable_config';

  /// 获取所有课程
  Future<List<Course>> getCourses() async {
    final prefs = await SharedPreferences.getInstance();
    final String? coursesJson = prefs.getString(_coursesKey);
    
    if (coursesJson == null) {
      return [];
    }

    final List<dynamic> coursesList = json.decode(coursesJson);
    return coursesList
        .map((e) => Course.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 保存所有课程
  Future<void> saveCourses(List<Course> courses) async {
    final prefs = await SharedPreferences.getInstance();
    final String coursesJson = json.encode(
      courses.map((e) => e.toJson()).toList(),
    );
    await prefs.setString(_coursesKey, coursesJson);
  }

  /// 添加单个课程
  Future<void> addCourse(Course course) async {
    final courses = await getCourses();
    courses.add(course);
    await saveCourses(courses);
  }

  /// 更新课程
  Future<void> updateCourse(Course course) async {
    final courses = await getCourses();
    final index = courses.indexWhere((c) => c.id == course.id);
    if (index != -1) {
      courses[index] = course;
      await saveCourses(courses);
    }
  }

  /// 删除课程
  Future<void> deleteCourse(String courseId) async {
    final courses = await getCourses();
    courses.removeWhere((c) => c.id == courseId);
    await saveCourses(courses);
  }

  /// 获取特定周次和星期的课程
  Future<List<Course>> getCoursesForWeekday(int week, int weekday) async {
    final courses = await getCourses();
    return courses.where((course) {
      return course.weekday == weekday && course.weeks.contains(week);
    }).toList();
  }

  /// 获取课程表配置
  Future<TimetableConfig> getConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final String? configJson = prefs.getString(_configKey);
    
    if (configJson == null) {
      return TimetableConfig.defaultConfig();
    }

    return TimetableConfig.fromJson(
      json.decode(configJson) as Map<String, dynamic>,
    );
  }

  /// 保存课程表配置
  Future<void> saveConfig(TimetableConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final String configJson = json.encode(config.toJson());
    await prefs.setString(_configKey, configJson);
  }

  /// 清除所有数据
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_coursesKey);
    await prefs.remove(_configKey);
  }
}
