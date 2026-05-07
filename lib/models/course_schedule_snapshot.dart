import 'course.dart';
import 'course_schedule_config.dart';

/// 当前课程表的完整快照，用于减少重复存储读取。
class CourseScheduleSnapshot {
  const CourseScheduleSnapshot({
    required this.scheduleId,
    required this.courses,
    required this.config,
    required this.semesterStart,
    required this.maxWeek,
    required this.tableName,
    required this.showWeekend,
    required this.showNonCurrentWeek,
    required this.isScheduleLocked,
  });

  final String scheduleId;
  final List<Course> courses;
  final CourseScheduleConfig config;
  final DateTime? semesterStart;
  final int maxWeek;
  final String tableName;
  final bool showWeekend;
  final bool showNonCurrentWeek;
  final bool isScheduleLocked;

  CourseScheduleSnapshot copyWith({
    String? scheduleId,
    List<Course>? courses,
    CourseScheduleConfig? config,
    Object? semesterStart = _noOverride,
    int? maxWeek,
    String? tableName,
    bool? showWeekend,
    bool? showNonCurrentWeek,
    bool? isScheduleLocked,
  }) {
    return CourseScheduleSnapshot(
      scheduleId: scheduleId ?? this.scheduleId,
      courses: courses ?? this.courses,
      config: config ?? this.config,
      semesterStart: identical(semesterStart, _noOverride)
          ? this.semesterStart
          : semesterStart as DateTime?,
      maxWeek: maxWeek ?? this.maxWeek,
      tableName: tableName ?? this.tableName,
      showWeekend: showWeekend ?? this.showWeekend,
      showNonCurrentWeek: showNonCurrentWeek ?? this.showNonCurrentWeek,
      isScheduleLocked: isScheduleLocked ?? this.isScheduleLocked,
    );
  }

  /// 返回一份可安全修改的深拷贝。
  CourseScheduleSnapshot copy() {
    return CourseScheduleSnapshot(
      scheduleId: scheduleId,
      courses: cloneCourses(courses),
      config: CourseScheduleConfig.fromJson(config.toJson()),
      semesterStart: semesterStart == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              semesterStart!.millisecondsSinceEpoch,
            ),
      maxWeek: maxWeek,
      tableName: tableName,
      showWeekend: showWeekend,
      showNonCurrentWeek: showNonCurrentWeek,
      isScheduleLocked: isScheduleLocked,
    );
  }

  /// 深拷贝课程列表，避免页面意外修改缓存数据。
  static List<Course> cloneCourses(Iterable<Course> source) {
    return source.map(_cloneCourse).toList(growable: false);
  }

  static Course _cloneCourse(Course course) {
    return Course(
      name: course.name,
      teacher: course.teacher,
      color: course.color,
      sessions: course.sessions.map(_cloneSession).toList(growable: false),
    );
  }

  static CourseSession _cloneSession(CourseSession session) {
    return CourseSession(
      weekday: session.weekday,
      startSection: session.startSection,
      sectionCount: session.sectionCount,
      location: session.location,
      startWeek: session.startWeek,
      endWeek: session.endWeek,
      weekType: session.weekType,
      customWeeks: List<int>.from(session.customWeeks, growable: false),
    );
  }
}

const Object _noOverride = Object();
