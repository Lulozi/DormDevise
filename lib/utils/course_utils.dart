import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/course_schedule_config.dart';

/// 课程卡片预设背景色池（Material Design 100/200 色调的柔和色）。
///
/// 作为课程颜色的唯一数据源，供课程编辑页和课表爬取等模块共同引用。
/// 新增颜色只需在此列表追加即可全局生效。
const List<Color> kCoursePresetColors = <Color>[
  Color(0xFFFFCDD2), // 浅红
  Color(0xFFF8BBD0), // 浅粉
  Color(0xFFE1BEE7), // 浅紫
  Color(0xFFD1C4E9), // 浅深紫
  Color(0xFFC5CAE9), // 浅靛蓝
  Color(0xFFBBDEFB), // 浅蓝
  Color(0xFFB3E5FC), // 浅浅蓝
  Color(0xFFB2EBF2), // 浅青
  Color(0xFFB2DFDB), // 浅蓝绿
  Color(0xFFC8E6C9), // 浅绿
  Color(0xFFDCEDC8), // 浅浅绿
  Color(0xFFF0F4C3), // 浅黄绿
  Color(0xFFFFF9C4), // 浅黄
  Color(0xFFFFECB3), // 浅琥珀
  Color(0xFFFFE0B2), // 浅橙
  Color(0xFFFFCCBC), // 浅深橙
];

/// 根据 `CourseSession` 的 start/end/weekType 生成周次展示字符串
/// - 连续：返回 "第 start-end 周"
/// - 非连续：返回 "第a,b,c 周"
String formatWeeks(CourseSession session) {
  final List<int> weeks = <int>[];
  for (int w = session.startWeek; w <= session.endWeek; w++) {
    if (session.occursInWeek(w)) {
      weeks.add(w);
    }
  }
  if (weeks.isEmpty) return '';
  if (weeks.length == 1) return '第${weeks.first}周';
  // 判断周数是否连续
  bool contiguous = true;
  for (int i = 1; i < weeks.length; i++) {
    if (weeks[i] - weeks[i - 1] != 1) {
      contiguous = false;
      break;
    }
  }
  if (contiguous) {
    return '第${weeks.first}-${weeks.last}周';
  }
  return '第${weeks.join('，')}周';
}

// ---------------------------------------------------------------------------
// 跨时段课程分段
// ---------------------------------------------------------------------------

/// 将跨越多个教学时段的课程排课拆分为多段。
///
/// 例如，若配置中上午为 1-4 节、下午为 5-8 节，而某课程排在 1-8 节，
/// 则该排课会被拆分为 1-4 节（上午）和 5-8 节（下午）两段。
///
/// 这样可以保证课表渲染时每段精确对齐到所属时段，避免跨时段显示异常。
List<Course> splitCrossSegmentSessions(
  List<Course> courses,
  CourseScheduleConfig config,
) {
  // 根据配置计算每个时段的节次范围边界
  // 例如：上午 4 节 → [1,4]，下午 4 节 → [5,8]，晚上 3 节 → [9,11]
  final List<_SegmentBoundary> boundaries = <_SegmentBoundary>[];
  int sectionOffset = 1;
  for (final ScheduleSegmentConfig seg in config.segments) {
    boundaries.add(
      _SegmentBoundary(
        start: sectionOffset,
        end: sectionOffset + seg.classCount - 1,
      ),
    );
    sectionOffset += seg.classCount;
  }

  if (boundaries.isEmpty) return courses;

  return courses.map((Course course) {
    final List<CourseSession> newSessions = <CourseSession>[];
    for (final CourseSession session in course.sessions) {
      final List<CourseSession> split = _splitSessionBySegments(
        session,
        boundaries,
      );
      newSessions.addAll(split);
    }
    return Course(
      name: course.name,
      teacher: course.teacher,
      color: course.color,
      sessions: newSessions,
    );
  }).toList();
}

/// 将单个排课按时段边界拆分。
///
/// 若该排课完全属于某一时段，则原样返回；否则在每个时段边界处切分。
List<CourseSession> _splitSessionBySegments(
  CourseSession session,
  List<_SegmentBoundary> boundaries,
) {
  final int sessionStart = session.startSection;
  final int sessionEnd = sessionStart + session.sectionCount - 1;

  // 找出该排课实际跨越的时段
  final List<CourseSession> result = <CourseSession>[];
  for (final _SegmentBoundary bound in boundaries) {
    // 计算该排课与当前时段的交集
    final int overlapStart = sessionStart > bound.start
        ? sessionStart
        : bound.start;
    final int overlapEnd = sessionEnd < bound.end ? sessionEnd : bound.end;

    if (overlapStart > overlapEnd) continue; // 无交集

    result.add(
      CourseSession(
        weekday: session.weekday,
        startSection: overlapStart,
        sectionCount: overlapEnd - overlapStart + 1,
        location: session.location,
        startWeek: session.startWeek,
        endWeek: session.endWeek,
        weekType: session.weekType,
        customWeeks: session.customWeeks,
      ),
    );
  }

  // 若未匹配到任何时段（异常情况），保留原排课
  return result.isEmpty ? <CourseSession>[session] : result;
}

/// 教学时段节次边界（包含两端）。
class _SegmentBoundary {
  final int start;
  final int end;
  const _SegmentBoundary({required this.start, required this.end});
}
