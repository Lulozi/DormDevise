import 'package:flutter/material.dart';

/// 课程在周次上的单双周限制。
enum CourseWeekType {
  /// 所有周次都适用。
  all,

  /// 仅适用单周。
  single,

  /// 仅适用双周。
  double,
}

/// 课程在课表中的一次具体安排。
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

  const CourseSession({
    required this.weekday,
    required this.startSection,
    required this.sectionCount,
    required this.location,
    required this.startWeek,
    required this.endWeek,
    this.weekType = CourseWeekType.all,
  });

  /// 判断指定周次是否需要上课。
  bool occursInWeek(int week) {
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
}

/// 表示一门课程及其全部排课安排。
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

  /// 根据当前周次筛选需要呈现的排课列表。
  List<CourseSession> sessionsForWeek(int week) {
    return sessions.where((session) => session.occursInWeek(week)).toList();
  }
}
