/// 课程表配置模型，用于存储课程时间设置
class TimetableConfig {
  /// 当前周次
  final int currentWeek;

  /// 总周数
  final int totalWeeks;

  /// 每天的课程节数
  final int sectionsPerDay;

  /// 每节课的时间安排
  final List<TimeSection> timeSections;

  TimetableConfig({
    required this.currentWeek,
    required this.totalWeeks,
    required this.sectionsPerDay,
    required this.timeSections,
  });

  /// 从JSON创建配置对象
  factory TimetableConfig.fromJson(Map<String, dynamic> json) {
    return TimetableConfig(
      currentWeek: json['currentWeek'] as int,
      totalWeeks: json['totalWeeks'] as int,
      sectionsPerDay: json['sectionsPerDay'] as int,
      timeSections: (json['timeSections'] as List<dynamic>)
          .map((e) => TimeSection.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 转换为JSON格式
  Map<String, dynamic> toJson() {
    return {
      'currentWeek': currentWeek,
      'totalWeeks': totalWeeks,
      'sectionsPerDay': sectionsPerDay,
      'timeSections': timeSections.map((e) => e.toJson()).toList(),
    };
  }

  /// 创建默认配置
  factory TimetableConfig.defaultConfig() {
    return TimetableConfig(
      currentWeek: 1,
      totalWeeks: 20,
      sectionsPerDay: 12,
      timeSections: [
        TimeSection(section: 1, startTime: '08:00', endTime: '08:45'),
        TimeSection(section: 2, startTime: '08:55', endTime: '09:40'),
        TimeSection(section: 3, startTime: '10:00', endTime: '10:45'),
        TimeSection(section: 4, startTime: '10:55', endTime: '11:40'),
        TimeSection(section: 5, startTime: '13:30', endTime: '14:15'),
        TimeSection(section: 6, startTime: '14:25', endTime: '15:10'),
        TimeSection(section: 7, startTime: '15:30', endTime: '16:15'),
        TimeSection(section: 8, startTime: '16:25', endTime: '17:10'),
        TimeSection(section: 9, startTime: '18:30', endTime: '19:15'),
        TimeSection(section: 10, startTime: '19:25', endTime: '20:10'),
        TimeSection(section: 11, startTime: '20:20', endTime: '21:05'),
        TimeSection(section: 12, startTime: '21:15', endTime: '22:00'),
      ],
    );
  }

  /// 创建配置副本
  TimetableConfig copyWith({
    int? currentWeek,
    int? totalWeeks,
    int? sectionsPerDay,
    List<TimeSection>? timeSections,
  }) {
    return TimetableConfig(
      currentWeek: currentWeek ?? this.currentWeek,
      totalWeeks: totalWeeks ?? this.totalWeeks,
      sectionsPerDay: sectionsPerDay ?? this.sectionsPerDay,
      timeSections: timeSections ?? this.timeSections,
    );
  }
}

/// 单节课时间段
class TimeSection {
  /// 第几节课
  final int section;

  /// 开始时间（格式：HH:mm）
  final String startTime;

  /// 结束时间（格式：HH:mm）
  final String endTime;

  TimeSection({
    required this.section,
    required this.startTime,
    required this.endTime,
  });

  /// 从JSON创建时间段对象
  factory TimeSection.fromJson(Map<String, dynamic> json) {
    return TimeSection(
      section: json['section'] as int,
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String,
    );
  }

  /// 转换为JSON格式
  Map<String, dynamic> toJson() {
    return {
      'section': section,
      'startTime': startTime,
      'endTime': endTime,
    };
  }
}
