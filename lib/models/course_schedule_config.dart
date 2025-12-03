import 'package:flutter/material.dart';

/// 表示单节课程的时间信息（用于构建课节时间表与渲染）。
class SectionTime {
  /// 课节序号，从 1 开始计数。
  final int index;

  /// 课节所属教学时段名称，例如“上午”“下午”。
  final String segmentName;

  /// 课程开始时间。
  final TimeOfDay start;

  /// 课程结束时间。
  final TimeOfDay end;

  const SectionTime({
    required this.index,
    required this.segmentName,
    required this.start,
    required this.end,
  });
}

/// 配置特定教学时段（如上午/下午/晚上）内的课节数量和每节时长。
class ScheduleSegmentConfig {
  /// 时段名称，用于展示和区分。
  final String name;

  /// 该时段第一节课的起始时间。
  final TimeOfDay startTime;

  /// 该时段包含的课节数量。
  final int classCount;

  /// 定义该时段每节课的时长，若为空则使用全局默认课时。
  final Duration? classDuration;

  /// 定义该时段课间休息时长，若为空则使用全局默认休息时长。
  final Duration? breakDuration;

  /// 针对该时段的逐节课时长设置，长度需与 [classCount] 一致。
  final List<Duration>? perClassDurations;

  /// 针对该时段的逐节课间休息设置，长度需为 [classCount] - 1。
  final List<Duration>? perBreakDurations;

  const ScheduleSegmentConfig({
    required this.name,
    required this.startTime,
    required this.classCount,
    this.classDuration,
    this.breakDuration,
    this.perClassDurations,
    this.perBreakDurations,
  }) : assert(
         perClassDurations == null || perClassDurations.length == classCount,
         'perClassDurations 长度必须与 classCount 一致',
       ),
       assert(
         perBreakDurations == null ||
             perBreakDurations.length == classCount - 1,
         'perBreakDurations 长度必须为 classCount - 1',
       );

  /// 以当前实例为基础生成一个新的 `ScheduleSegmentConfig`，可覆盖指定字段。
  ScheduleSegmentConfig copyWith({
    String? name,
    TimeOfDay? startTime,
    int? classCount,
    Duration? classDuration,
    Duration? breakDuration,
    List<Duration>? perClassDurations,
    List<Duration>? perBreakDurations,
  }) {
    final int targetClassCount = classCount ?? this.classCount;
    assert(
      perClassDurations == null || perClassDurations.length == targetClassCount,
      'perClassDurations 长度必须与 classCount 一致',
    );
    assert(
      perBreakDurations == null ||
          perBreakDurations.length ==
              (targetClassCount > 0 ? targetClassCount - 1 : 0),
      'perBreakDurations 长度必须为 classCount - 1',
    );
    return ScheduleSegmentConfig(
      name: name ?? this.name,
      startTime: startTime ?? this.startTime,
      classCount: targetClassCount,
      classDuration: classDuration ?? this.classDuration,
      breakDuration: breakDuration ?? this.breakDuration,
      perClassDurations: perClassDurations ?? this.perClassDurations,
      perBreakDurations: perBreakDurations ?? this.perBreakDurations,
    );
  }

  /// 将 `ScheduleSegmentConfig` 序列化为 JSON Map，时间以小时/分钟和分钟为单位保存。
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'startTime': {'hour': startTime.hour, 'minute': startTime.minute},
      'classCount': classCount,
      'classDuration': classDuration?.inMinutes,
      'breakDuration': breakDuration?.inMinutes,
      'perClassDurations': perClassDurations?.map((d) => d.inMinutes).toList(),
      'perBreakDurations': perBreakDurations?.map((d) => d.inMinutes).toList(),
    };
  }

  /// 从 JSON Map 反序列化 `ScheduleSegmentConfig`。
  factory ScheduleSegmentConfig.fromJson(Map<String, dynamic> json) {
    return ScheduleSegmentConfig(
      name: json['name'] as String,
      startTime: TimeOfDay(
        hour: json['startTime']['hour'] as int,
        minute: json['startTime']['minute'] as int,
      ),
      classCount: json['classCount'] as int,
      classDuration: json['classDuration'] != null
          ? Duration(minutes: json['classDuration'] as int)
          : null,
      breakDuration: json['breakDuration'] != null
          ? Duration(minutes: json['breakDuration'] as int)
          : null,
      perClassDurations: (json['perClassDurations'] as List?)
          ?.map((e) => Duration(minutes: e as int))
          .toList(),
      perBreakDurations: (json['perBreakDurations'] as List?)
          ?.map((e) => Duration(minutes: e as int))
          .toList(),
    );
  }
}

/// 管理课程表的全局与分时段配置，支持生成具体节次与时长计算。
class CourseScheduleConfig {
  /// 全局默认单节课时长。
  final Duration defaultClassDuration;

  /// 全局默认课间休息时长。
  final Duration defaultBreakDuration;

  /// 需要渲染的教学时段配置列表。
  final List<ScheduleSegmentConfig> segments;

  /// 是否启用分段课间休息时长。
  final bool useSegmentBreakDurations;

  CourseScheduleConfig({
    required this.defaultClassDuration,
    required this.defaultBreakDuration,
    required List<ScheduleSegmentConfig> segments,
    this.useSegmentBreakDurations = false,
  }) : segments = List<ScheduleSegmentConfig>.unmodifiable(segments);

  /// 返回基于南京大学常见排课的默认配置（上下午 4 节，晚上 3 节）。
  factory CourseScheduleConfig.njuDefaults() {
    return CourseScheduleConfig(
      defaultClassDuration: const Duration(minutes: 45),
      defaultBreakDuration: const Duration(minutes: 10),
      segments: <ScheduleSegmentConfig>[
        const ScheduleSegmentConfig(
          name: '上午',
          startTime: TimeOfDay(hour: 8, minute: 0),
          classCount: 4,
        ),
        const ScheduleSegmentConfig(
          name: '下午',
          startTime: TimeOfDay(hour: 13, minute: 30),
          classCount: 4,
        ),
        const ScheduleSegmentConfig(
          name: '晚上',
          startTime: TimeOfDay(hour: 18, minute: 30),
          classCount: 3,
          classDuration: Duration(minutes: 45),
        ),
      ],
      useSegmentBreakDurations: false,
    );
  }

  /// 将 `CourseScheduleConfig` 序列化为 JSON Map，便于持久化。
  Map<String, dynamic> toJson() {
    return {
      'defaultClassDuration': defaultClassDuration.inMinutes,
      'defaultBreakDuration': defaultBreakDuration.inMinutes,
      'segments': segments.map((s) => s.toJson()).toList(),
      'useSegmentBreakDurations': useSegmentBreakDurations,
    };
  }

  /// 从 JSON Map 创建 `CourseScheduleConfig` 对象。
  factory CourseScheduleConfig.fromJson(Map<String, dynamic> json) {
    return CourseScheduleConfig(
      defaultClassDuration: Duration(
        minutes: json['defaultClassDuration'] as int,
      ),
      defaultBreakDuration: Duration(
        minutes: json['defaultBreakDuration'] as int,
      ),
      segments: (json['segments'] as List)
          .map((e) => ScheduleSegmentConfig.fromJson(e as Map<String, dynamic>))
          .toList(),
      useSegmentBreakDurations: json['useSegmentBreakDurations'] as bool,
    );
  }

  /// 根据当前配置生成一个从 1 开始的连续 `SectionTime` 列表，按分段合并。
  List<SectionTime> generateSections() {
    final List<SectionTime> sections = <SectionTime>[];
    int sectionIndex = 1;
    for (final ScheduleSegmentConfig segment in segments) {
      sections.addAll(_buildSegmentSections(segment, sectionIndex));
      sectionIndex += segment.classCount;
    }
    return sections;
  }

  /// 为指定的教学时段（`ScheduleSegmentConfig`）生成该段内所有课节的 `SectionTime` 信息。
  List<SectionTime> _buildSegmentSections(
    ScheduleSegmentConfig segment,
    int startIndex,
  ) {
    final List<SectionTime> sectionTimes = <SectionTime>[];
    TimeOfDay currentStart = segment.startTime;
    for (int i = 0; i < segment.classCount; i++) {
      final Duration classDuration = resolveClassDuration(segment, i);
      final TimeOfDay currentEnd = _addDuration(currentStart, classDuration);
      sectionTimes.add(
        SectionTime(
          index: startIndex + i,
          segmentName: segment.name,
          start: currentStart,
          end: currentEnd,
        ),
      );
      if (i < segment.classCount - 1) {
        final Duration breakDuration = resolveBreakDuration(segment, i);
        currentStart = _addDuration(currentEnd, breakDuration);
      }
    }
    return sectionTimes;
  }

  /// 获取指定时段第 index 节课的时长，优先使用逐节配置，否则回退至段配置或全局默认。
  Duration resolveClassDuration(ScheduleSegmentConfig segment, int index) {
    if (segment.perClassDurations != null &&
        segment.perClassDurations!.length > index) {
      return segment.perClassDurations![index];
    }
    return segment.classDuration ?? defaultClassDuration;
  }

  /// 获取指定时段第 index 节课后的休息时长，优先使用逐节配置或分段休息配置。
  Duration resolveBreakDuration(ScheduleSegmentConfig segment, int index) {
    if (!useSegmentBreakDurations) {
      return defaultBreakDuration;
    }
    if (segment.perBreakDurations != null &&
        segment.perBreakDurations!.length > index) {
      return segment.perBreakDurations![index];
    }
    if (segment.breakDuration != null) {
      return segment.breakDuration!;
    }
    return defaultBreakDuration;
  }

  /// 返回指定段内每节课的时长列表。
  List<Duration> getClassDurations(ScheduleSegmentConfig segment) {
    return List<Duration>.generate(
      segment.classCount,
      (int index) => resolveClassDuration(segment, index),
    );
  }

  /// 返回指定段内每节课间的休息时长列表（节数 - 1）。
  List<Duration> getBreakDurations(ScheduleSegmentConfig segment) {
    return List<Duration>.generate(
      segment.classCount > 0 ? segment.classCount - 1 : 0,
      (int index) => resolveBreakDuration(segment, index),
    );
  }

  /// 获取给定节次所属的分段索引（segments 列表的下标）。
  int segmentIndexForSection(int sectionIndex) {
    int cursor = 1;
    for (int i = 0; i < segments.length; i++) {
      final ScheduleSegmentConfig segment = segments[i];
      final int endIndex = cursor + segment.classCount - 1;
      if (sectionIndex >= cursor && sectionIndex <= endIndex) {
        return i;
      }
      cursor = endIndex + 1;
    }
    return -1;
  }

  /// 复制整个配置并替换第 index 个分段为新的分段配置。
  CourseScheduleConfig replaceSegment(
    int index,
    ScheduleSegmentConfig segment,
  ) {
    final List<ScheduleSegmentConfig> updated =
        List<ScheduleSegmentConfig>.from(segments);
    updated[index] = segment;
    return CourseScheduleConfig(
      defaultClassDuration: defaultClassDuration,
      defaultBreakDuration: defaultBreakDuration,
      segments: updated,
      useSegmentBreakDurations: useSegmentBreakDurations,
    );
  }

  /// 计算在指定起始时间上叠加持续时间后的新时间。
  TimeOfDay _addDuration(TimeOfDay time, Duration duration) {
    final int startMinutes = time.hour * 60 + time.minute;
    final int totalMinutes = startMinutes + duration.inMinutes;
    final int targetHour = (totalMinutes ~/ 60) % 24;
    final int targetMinute = totalMinutes % 60;
    return TimeOfDay(hour: targetHour, minute: targetMinute);
  }
}
