/// 课程信息模型，用于存储单个课程的详细信息
class Course {
  /// 课程唯一标识
  final String id;

  /// 课程名称
  final String name;

  /// 教室/地点
  final String? location;

  /// 教师姓名
  final String? teacher;

  /// 星期几（1-7，1表示周一，7表示周日）
  final int weekday;

  /// 第几节课开始（1-12）
  final int startSection;

  /// 第几节课结束（1-12）
  final int endSection;

  /// 周次列表（如[1,2,3]表示第1-3周有课）
  final List<int> weeks;

  /// 课程颜色（用于UI显示）
  final int color;

  Course({
    required this.id,
    required this.name,
    this.location,
    this.teacher,
    required this.weekday,
    required this.startSection,
    required this.endSection,
    required this.weeks,
    required this.color,
  });

  /// 从JSON创建课程对象
  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'] as String,
      name: json['name'] as String,
      location: json['location'] as String?,
      teacher: json['teacher'] as String?,
      weekday: json['weekday'] as int,
      startSection: json['startSection'] as int,
      endSection: json['endSection'] as int,
      weeks: (json['weeks'] as List<dynamic>).cast<int>(),
      color: json['color'] as int,
    );
  }

  /// 转换为JSON格式
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'location': location,
      'teacher': teacher,
      'weekday': weekday,
      'startSection': startSection,
      'endSection': endSection,
      'weeks': weeks,
      'color': color,
    };
  }

  /// 创建课程副本
  Course copyWith({
    String? id,
    String? name,
    String? location,
    String? teacher,
    int? weekday,
    int? startSection,
    int? endSection,
    List<int>? weeks,
    int? color,
  }) {
    return Course(
      id: id ?? this.id,
      name: name ?? this.name,
      location: location ?? this.location,
      teacher: teacher ?? this.teacher,
      weekday: weekday ?? this.weekday,
      startSection: startSection ?? this.startSection,
      endSection: endSection ?? this.endSection,
      weeks: weeks ?? this.weeks,
      color: color ?? this.color,
    );
  }
}
