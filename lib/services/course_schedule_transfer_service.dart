import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/course_schedule_config.dart';
import '../utils/index.dart';
import '../utils/qr_transfer_codec.dart';

/// 课表分享/导入使用的压缩传输模型。
class CourseScheduleTransferBundle {
  const CourseScheduleTransferBundle({
    required this.tableName,
    required this.semesterStart,
    required this.maxWeek,
    required this.showWeekend,
    required this.showNonCurrentWeek,
    required this.isScheduleLocked,
    required this.scheduleConfig,
    required this.courses,
  });

  final String tableName;
  final DateTime semesterStart;
  final int maxWeek;
  final bool showWeekend;
  final bool showNonCurrentWeek;
  final bool isScheduleLocked;
  final CourseScheduleConfig scheduleConfig;
  final List<Course> courses;
}

/// 课表二维码传输编解码。
class CourseScheduleTransferService {
  CourseScheduleTransferService._();

  static const String payloadType = 'schedule';
  static const int payloadVersion = 1;

  /// 生成课表导入码。
  static String encodeBundle(CourseScheduleTransferBundle bundle) {
    return QrTransferCodec.encodeJson(
      type: payloadType,
      version: payloadVersion,
      payload: _encodeBundle(bundle),
    );
  }

  /// 解析课表导入码。
  static CourseScheduleTransferBundle decodeBundle(String raw) {
    final DecodedQrTransferPayload? decoded = QrTransferCodec.tryDecode(raw);
    if (decoded == null) {
      throw const FormatException('未识别到课表导入码');
    }
    if (decoded.type != payloadType) {
      throw const FormatException('二维码不是课表导入码');
    }

    final dynamic payload = decoded.decodeJson();
    if (payload is! Map) {
      throw const FormatException('课表数据格式错误');
    }

    return _decodeBundle(Map<String, dynamic>.from(payload));
  }

  /// 兼容识别旧版仅包含链接的分享二维码。
  static bool isLegacyShareLink(String raw) {
    final Uri? uri = Uri.tryParse(raw.trim());
    return uri != null &&
        uri.host == 'dormdevise.app' &&
        uri.path == '/schedule/share';
  }

  static Map<String, Object?> _encodeBundle(
    CourseScheduleTransferBundle bundle,
  ) {
    return <String, Object?>{
      'n': bundle.tableName,
      'ss': bundle.semesterStart.millisecondsSinceEpoch,
      'mw': bundle.maxWeek,
      'sw': bundle.showWeekend,
      'sn': bundle.showNonCurrentWeek,
      'lk': bundle.isScheduleLocked,
      'cfg': _encodeConfig(bundle.scheduleConfig),
      'cs': bundle.courses.map(_encodeCourse).toList(growable: false),
    };
  }

  static CourseScheduleTransferBundle _decodeBundle(Map<String, dynamic> map) {
    final dynamic rawConfig = map['cfg'];
    final Map<String, dynamic> configMap = rawConfig is Map
        ? Map<String, dynamic>.from(rawConfig)
        : <String, dynamic>{};

    return CourseScheduleTransferBundle(
      tableName: (map['n']?.toString() ?? '').trim().isEmpty
          ? '导入课表'
          : map['n'].toString().trim(),
      semesterStart: DateTime.fromMillisecondsSinceEpoch(
        (map['ss'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
      maxWeek: (map['mw'] as num?)?.toInt() ?? 20,
      showWeekend: map['sw'] == true,
      showNonCurrentWeek: map['sn'] != false,
      isScheduleLocked: map['lk'] == true,
      scheduleConfig: _decodeConfig(configMap),
      courses: (map['cs'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map<dynamic, dynamic> item) {
            return _decodeCourse(Map<String, dynamic>.from(item));
          })
          .toList(growable: false),
    );
  }

  static Map<String, Object?> _encodeConfig(CourseScheduleConfig config) {
    return <String, Object?>{
      'cd': config.defaultClassDuration.inMinutes,
      'bd': config.defaultBreakDuration.inMinutes,
      'u': config.useSegmentBreakDurations,
      'sg': config.segments.map(_encodeSegment).toList(growable: false),
    };
  }

  static CourseScheduleConfig _decodeConfig(Map<String, dynamic> map) {
    final List<dynamic> segments = map['sg'] as List<dynamic>? ?? <dynamic>[];
    return CourseScheduleConfig(
      defaultClassDuration: Duration(
        minutes: (map['cd'] as num?)?.toInt() ?? 40,
      ),
      defaultBreakDuration: Duration(
        minutes: (map['bd'] as num?)?.toInt() ?? 15,
      ),
      useSegmentBreakDurations: map['u'] == true,
      segments: segments
          .whereType<Map>()
          .map((Map<dynamic, dynamic> item) {
            return _decodeSegment(Map<String, dynamic>.from(item));
          })
          .toList(growable: false),
    );
  }

  static Map<String, Object?> _encodeSegment(ScheduleSegmentConfig segment) {
    return <String, Object?>{
      'n': segment.name,
      's': segment.startTime.hour * 60 + segment.startTime.minute,
      'c': segment.classCount,
      if (segment.classDuration != null) 'd': segment.classDuration!.inMinutes,
      if (segment.perClassDurations != null &&
          segment.perClassDurations!.isNotEmpty)
        'pd': segment.perClassDurations!
            .map((Duration duration) => duration.inMinutes)
            .toList(growable: false),
      if (segment.breakDuration != null) 'b': segment.breakDuration!.inMinutes,
      if (segment.perBreakDurations != null &&
          segment.perBreakDurations!.isNotEmpty)
        'pb': segment.perBreakDurations!
            .map((Duration duration) => duration.inMinutes)
            .toList(growable: false),
    };
  }

  static ScheduleSegmentConfig _decodeSegment(Map<String, dynamic> map) {
    final int startMinutes = (map['s'] as num?)?.toInt() ?? 0;
    return ScheduleSegmentConfig(
      name: map['n']?.toString() ?? '',
      startTime: TimeOfDay(hour: startMinutes ~/ 60, minute: startMinutes % 60),
      classCount: (map['c'] as num?)?.toInt() ?? 0,
      classDuration: map['d'] == null
          ? null
          : Duration(minutes: (map['d'] as num).toInt()),
      perClassDurations: _decodeDurations(map['pd']),
      breakDuration: map['b'] == null
          ? null
          : Duration(minutes: (map['b'] as num).toInt()),
      perBreakDurations: _decodeDurations(map['pb']),
    );
  }

  static Map<String, Object?> _encodeCourse(Course course) {
    return <String, Object?>{
      'n': course.name,
      't': course.teacher,
      'c': course.color.toARGB32(),
      's': course.sessions.map(_encodeSession).toList(growable: false),
    };
  }

  static Course _decodeCourse(Map<String, dynamic> map) {
    return Course(
      name: map['n']?.toString() ?? '',
      teacher: map['t']?.toString() ?? '',
      color: colorFromARGB32((map['c'] as num?)?.toInt() ?? 0xFF4F6BED),
      sessions: (map['s'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map<dynamic, dynamic> item) {
            return _decodeSession(Map<String, dynamic>.from(item));
          })
          .toList(growable: false),
    );
  }

  static Map<String, Object?> _encodeSession(CourseSession session) {
    return <String, Object?>{
      'd': session.weekday,
      's': session.startSection,
      'l': session.sectionCount,
      'p': session.location,
      'w': session.startWeek,
      'e': session.endWeek,
      'y': session.weekType.index,
      if (session.customWeeks.isNotEmpty) 'x': session.customWeeks,
    };
  }

  static CourseSession _decodeSession(Map<String, dynamic> map) {
    final int weekTypeIndex = ((map['y'] as num?)?.toInt() ?? 0).clamp(
      0,
      CourseWeekType.values.length - 1,
    );
    return CourseSession(
      weekday: (map['d'] as num?)?.toInt() ?? 1,
      startSection: (map['s'] as num?)?.toInt() ?? 1,
      sectionCount: (map['l'] as num?)?.toInt() ?? 1,
      location: map['p']?.toString() ?? '',
      startWeek: (map['w'] as num?)?.toInt() ?? 1,
      endWeek: (map['e'] as num?)?.toInt() ?? 1,
      weekType: CourseWeekType.values[weekTypeIndex],
      customWeeks: (map['x'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic item) => (item as num).toInt())
          .toList(growable: false),
    );
  }

  static List<Duration>? _decodeDurations(dynamic raw) {
    if (raw is! List) {
      return null;
    }
    return raw
        .map((dynamic item) => Duration(minutes: (item as num).toInt()))
        .toList(growable: false);
  }
}
