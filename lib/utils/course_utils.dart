import '../models/course.dart';

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
