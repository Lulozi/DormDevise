import 'package:flutter/material.dart';
// 允许扩展方法导入（仅用于扩展方法），用于 `toARGB32()` 等颜色序列化方法
// ignore: unused_import
import 'package:dormdevise/utils/index.dart';

/// 课程在周次上的单双周限制枚举（用于描述课程每周的适用规则）。
enum CourseWeekType {
  /// 所有周次都适用。
  all,

  /// 仅适用单周。
  single,

  /// 仅适用双周。
  double,
}

/// 表示课程的一次具体排课信息（单次上课的时间/教室/周次范围等）。
class CourseSession {
  /// 所属星期，取值范围 1（周一）至 7（周日）。
  final int weekday;

  /// 开始课节序号，从 1 开始计数。
  final int startSection;

  /// 连续占用的课节数量。
  final int sectionCount;

  /// 上课地点描述。
  final String location;

  /// 起始周次（包含）。
  final int startWeek;

  /// 结束周次（包含）。
  final int endWeek;

  /// 周次类型限制（单双周或全周）。
  final CourseWeekType weekType;

  /// 自定义周次列表（若非空，则忽略 weekType，仅匹配列表中的周次）。
  final List<int> customWeeks;

  const CourseSession({
    required this.weekday,
    required this.startSection,
    required this.sectionCount,
    required this.location,
    required this.startWeek,
    required this.endWeek,
    this.weekType = CourseWeekType.all,
    this.customWeeks = const [],
  });

  /// 检查传入周次是否包含在当前排课范围内，遵循自定义周次或单双周逻辑。
  bool occursInWeek(int week) {
    if (customWeeks.isNotEmpty) {
      return customWeeks.contains(week);
    }
    if (week < startWeek || week > endWeek) {
      return false;
    }
    if (weekType == CourseWeekType.all) {
      return true;
    }
    final bool isEvenWeek = week % 2 == 0;
    if (weekType == CourseWeekType.single) {
      return !isEvenWeek;
    }
    return isEvenWeek;
  }

  /// 将 CourseSession 序列化为 JSON Map，便于持久化存储或网络传输。
  Map<String, dynamic> toJson() {
    return {
      'weekday': weekday,
      'startSection': startSection,
      'sectionCount': sectionCount,
      'location': location,
      'startWeek': startWeek,
      'endWeek': endWeek,
      'weekType': weekType.index,
      if (customWeeks.isNotEmpty) 'customWeeks': customWeeks,
    };
  }

  /// 从 JSON Map 反序列化为 `CourseSession` 对象。
  factory CourseSession.fromJson(Map<String, dynamic> json) {
    return CourseSession(
      weekday: json['weekday'] as int,
      startSection: json['startSection'] as int,
      sectionCount: json['sectionCount'] as int,
      location: json['location'] as String,
      startWeek: json['startWeek'] as int,
      endWeek: json['endWeek'] as int,
      weekType: CourseWeekType.values[json['weekType'] as int],
      customWeeks: (json['customWeeks'] as List<dynamic>?)?.cast<int>() ?? [],
    );
  }
}

/// 表示课程的基本信息及其所有排课片段（多个 `CourseSession`）。
class Course {
  /// 课程名称。
  final String name;

  /// 任课教师。
  final String teacher;

  /// 展示颜色，用于课表卡片背景。
  final Color color;

  /// 课程的所有安排片段。
  final List<CourseSession> sessions;

  const Course({
    required this.name,
    required this.teacher,
    required this.color,
    required this.sessions,
  });

  /// 基于传入的周次筛选出当前应该展示的 `CourseSession` 列表。
  List<CourseSession> sessionsForWeek(int week) {
    return sessions.where((session) => session.occursInWeek(week)).toList();
  }

  /// 将 Course 对象序列化为 JSON Map（颜色为 ARGB32 整数）。
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'teacher': teacher,
      'color': color.toARGB32(),
      'sessions': sessions.map((s) => s.toJson()).toList(),
    };
  }

  /// 从 JSON Map 反序列化为 Course 对象。
  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      name: json['name'] as String,
      teacher: json['teacher'] as String,
      color: colorFromARGB32(json['color'] as int),
      sessions: (json['sessions'] as List)
          .map((e) => CourseSession.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
