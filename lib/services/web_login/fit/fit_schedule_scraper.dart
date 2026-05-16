import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../models/course.dart';
import '../../../utils/course_utils.dart';

// ---------------------------------------------------------------------------
// 爬取结果
// ---------------------------------------------------------------------------

/// 爬取结果，包含原始课程数据和学年学期信息。
class FitScrapeResult {
  /// 原始爬取数据列表，每条包含课程字段的 Map。
  final List<Map<String, dynamic>> rawItems;

  /// 学年学期（如 "2025-2026 第2学期"），可能为空。
  final String academicTerm;

  const FitScrapeResult({required this.rawItems, this.academicTerm = ''});

  bool get isEmpty => rawItems.isEmpty;
  bool get isNotEmpty => rawItems.isNotEmpty;
}

// ---------------------------------------------------------------------------
// 爬取服务
// ---------------------------------------------------------------------------

/// 福州理工学院（正方教务系统 v9）课表页面爬取服务。
///
/// 负责从登录后的课表页面中提取课程信息，返回 [Course] 列表。
/// 基于真实 DOM 结构解析 `<div class="timetable_con">` 内的课程条目。
class FitScheduleScraper {
  const FitScheduleScraper._();

  // -------------------------------------------------------------------------
  // 页面爬取（JS 注入）
  // -------------------------------------------------------------------------

  /// 从当前 WebView 页面爬取课表数据。
  ///
  /// 返回 [FitScrapeResult]，包含原始课程数据和学年学期信息。
  /// 外层再调用 [parseRawToCourses] 转换为 [Course] 模型。
  ///
  /// JS 脚本基于正方教务系统 v9 的真实 DOM 结构：
  /// 1. 从 `<select#xnm>` / `<select#xqm>` 读取当前学年学期；
  /// 2. 遍历 `<td[id]>` 中的 `<div class="timetable_con">` 提取各字段；
  /// 3. 节次和周次从 `<span[title="节/周"]>` 后的文本中提取。
  static Future<FitScrapeResult> scrapeScheduleRaw(
    InAppWebViewController controller,
  ) async {
    debugPrint('[FIT 爬取] 开始从页面提取课表数据...');

    final CallAsyncJavaScriptResult? result = await controller
        .callAsyncJavaScript(
          functionBody: r'''
        // ---------------------------------------------------------------
        // 正方教务系统 v9 课表爬取脚本
        // 适配 <div class="timetable_con text-left"> 结构
        // ---------------------------------------------------------------

        // === 1. 提取学年学期 ===
        let academicTerm = '';
        try {
          const xnmSel = document.querySelector('#xnm');
          const xqmSel = document.querySelector('#xqm');
          if (xnmSel) {
            const opt = xnmSel.options[xnmSel.selectedIndex];
            if (opt && opt.value) academicTerm = opt.textContent.trim();
          }
          if (xqmSel) {
            const opt = xqmSel.options[xqmSel.selectedIndex];
            if (opt && opt.value) {
              // xqm 的 value 与实际学期的映射：3→1, 12→2, 16→3
              const semMap = { '3': '1', '12': '2', '16': '3' };
              const semNum = semMap[opt.value] || opt.textContent.trim();
              academicTerm += (academicTerm ? ' ' : '') + '第' + semNum + '学期';
            }
          }
        } catch (e) {
          // 学年学期提取失败不影响课程爬取
        }

        // === 2. 遍历课表单元格 ===
        const results = [];
        // 所有带 id 的 <td>（格式 "星期-起始节次"，如 "1-1"、"4-5"）
        const cells = document.querySelectorAll('td.td_wrap[id]');

        if (!cells || cells.length === 0) {
          return { success: false, reason: '未找到课表单元格', academicTerm, results: [] };
        }

        for (const cell of cells) {
          const cellId = cell.getAttribute('id') || '';
          // 从单元格 id 获取星期
          const idParts = cellId.split('-');
          if (idParts.length < 2) continue;
          const weekday = parseInt(idParts[0]);
          if (isNaN(weekday) || weekday < 1 || weekday > 7) continue;

          // 每个单元格内可能有多个 <div class="timetable_con">（多门课程）
          const courseDivs = cell.querySelectorAll('div.timetable_con');
          if (!courseDivs || courseDivs.length === 0) continue;

          for (const div of courseDivs) {
            try {
              // --- 2a. 课程名称 ---
              // 兼容 <span class="title"> / <u class="title"> 等不同标签结构
              const titleNode = div.querySelector('.title');
              const courseNameRaw = titleNode ? titleNode.textContent : '';
              const courseName = (courseNameRaw || '')
                // 合并空白并去掉调课前缀，避免课程名解析失败或不一致
                .replace(/\u00a0/g, ' ')
                .replace(/\s+/g, ' ')
                .replace(/^【[^】]*】\s*/g, '')
                // 去掉中文字符之间被插入的空格（如“云平 台”）
                .replace(/([\u4e00-\u9fa5])\s+([\u4e00-\u9fa5])/g, '$1$2')
                .trim();
              if (!courseName) continue;

              // --- 2b. 节次/周次 ---
              // <span title="节/周"> 在 <font> 内，<font> 在 <p> 内
              // 实际文本在同一个 <p> 下的 textContent 中
              let sectionWeekText = '';
              const swSpan = div.querySelector('span[title="节/周"]');
              if (swSpan) {
                const p = swSpan.closest('p');
                if (p) sectionWeekText = p.textContent.trim();
              }

              // --- 2c. 上课地点 ---
              let location = '';
              const locSpan = div.querySelector('span[title="上课地点"]');
              if (locSpan) {
                const p = locSpan.closest('p');
                if (p) location = p.textContent.trim();
              }

              // --- 2d. 教师（注意 title 末尾可能有空格） ---
              let teacher = '';
              // 用 CSS 属性选择器匹配 title 以"教师"开头
              const teacherSpan = div.querySelector('span[title^="教师"]');
              if (teacherSpan) {
                const p = teacherSpan.closest('p');
                if (p) teacher = p.textContent.trim();
              }

              results.push({
                courseName,
                sectionWeekText,
                location,
                teacher,
                weekday,
              });
            } catch (e) {
              // 单个课程解析失败不影响其他课程
            }
          }
        }

        return { success: true, count: results.length, academicTerm, results };
      ''',
        );

    final Map<String, dynamic> data = _extractMap(result);
    final bool success = data['success'] == true;
    final String academicTerm = (data['academicTerm'] as String?) ?? '';
    final List<dynamic> rawResults =
        (data['results'] as List<dynamic>?) ?? <dynamic>[];

    debugPrint(
      '[FIT 爬取] 原始结果: success=$success, type=${data['type']}, '
      'count=${rawResults.length}, academicTerm=$academicTerm, '
      'reason=${data['reason']}, error=${result?.error}',
    );

    if (!success || rawResults.isEmpty) {
      return FitScrapeResult(
        rawItems: <Map<String, dynamic>>[],
        academicTerm: academicTerm,
      );
    }

    // 打印前 5 条原始数据用于调试
    for (int i = 0; i < rawResults.length && i < 5; i++) {
      debugPrint('[FIT 爬取] 原始[$i]: ${rawResults[i]}');
    }

    final List<Map<String, dynamic>> items = rawResults
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> m) => Map<String, dynamic>.from(m))
        .toList();

    return FitScrapeResult(rawItems: items, academicTerm: academicTerm);
  }

  // -------------------------------------------------------------------------
  // 解析为 Course
  // -------------------------------------------------------------------------

  /// 将原始爬取数据解析为 [Course] 列表。
  ///
  /// 每条原始数据包含：
  /// - `courseName`：课程名称
  /// - `sectionWeekText`：如 "(1-2节)2-5周,7-9周,11-16周"
  /// - `location`：上课地点
  /// - `teacher`：教师
  /// - `weekday`：星期几（1-7）
  ///
  /// 同一门课程（按名称聚合）的多条记录会合并为一个 [Course]。
  static List<Course> parseRawToCourses(List<Map<String, dynamic>> rawList) {
    final Map<String, _CourseBuilder> courseMap = <String, _CourseBuilder>{};

    for (final Map<String, dynamic> item in rawList) {
      // 将中文括号统一替换为英文括号以减少显示占位宽度
      final String courseName = ((item['courseName'] as String?) ?? '')
          .replaceAll('（', '(')
          .replaceAll('）', ')');
      final String sectionWeekText = (item['sectionWeekText'] as String?) ?? '';
      final String location = _normalizeImportedLocation(
        (item['location'] as String?) ?? '',
      );
      final String teacher = ((item['teacher'] as String?) ?? '')
          .replaceAll('（', '(')
          .replaceAll('）', ')');
      final int weekday = (item['weekday'] as int?) ?? 0;

      if (courseName.isEmpty || weekday <= 0) continue;

      // 解析 "(起始节-结束节)周次描述" 格式
      final _SectionWeekInfo? swInfo = _parseSectionWeek(sectionWeekText);
      if (swInfo == null) continue;

      // 为每个周次段分别创建 CourseSession
      for (final _WeekRange wr in swInfo.weekRanges) {
        _addSession(
          courseMap: courseMap,
          courseName: courseName,
          teacher: teacher,
          location: location,
          weekday: weekday,
          sectionStart: swInfo.sectionStart,
          sectionCount: swInfo.sectionCount,
          weekRange: wr,
        );
      }
    }

    final List<Course> courses = courseMap.values
        .map(
          (_CourseBuilder b) => Course(
            name: b.name,
            teacher: b.teacher,
            color: b.color,
            sessions: b.sessions,
          ),
        )
        .toList();

    debugPrint('[FIT 爬取] 解析完成: ${courses.length} 门课程');
    for (final Course c in courses) {
      debugPrint('  - ${c.name} (${c.teacher}): ${c.sessions.length} 个排课');
    }

    return courses;
  }

  // -------------------------------------------------------------------------
  // 节次/周次解析
  // -------------------------------------------------------------------------

  /// 解析 "(1-2节)2-5周,7-9周,11-16周" 格式的节次+周次信息。
  ///
  /// 返回包含起始节次、节次数、以及多段周次范围的 [_SectionWeekInfo]。
  /// 格式说明：
  /// - `(起始-结束节)` 表示连续课节
  /// - 后接一个或多个用逗号分隔的周次段，每段格式为 `N周` 或 `N-M周`
  static _SectionWeekInfo? _parseSectionWeek(String text) {
    if (text.isEmpty) return null;

    // 提取节次：(N-M节)
    final RegExpMatch? sectionMatch = RegExp(
      r'\((\d+)-(\d+)节\)',
    ).firstMatch(text);
    if (sectionMatch == null) return null;

    final int sectionStart = int.parse(sectionMatch.group(1)!);
    final int sectionEnd = int.parse(sectionMatch.group(2)!);
    final int sectionCount = sectionEnd - sectionStart + 1;

    // 提取周次：(N-M节) 之后的部分
    final String weekPart = text.substring(sectionMatch.end).trim();
    final List<_WeekRange> weekRanges = _parseWeekRanges(weekPart);

    if (weekRanges.isEmpty) return null;

    return _SectionWeekInfo(
      sectionStart: sectionStart,
      sectionCount: sectionCount,
      weekRanges: weekRanges,
    );
  }

  /// 解析周次描述（如 "2-5周,7-9周,11-16周" 或 "17周"）。
  ///
  /// 支持格式：
  /// - 连续范围：`2-5周`
  /// - 单周：`17周`
  /// - 单双周：`1-16周(单)` / `1-16周(双)`
  /// - 多段用逗号分隔：`2-5周,7-9周,11-16周`
  static List<_WeekRange> _parseWeekRanges(String text) {
    final List<_WeekRange> ranges = <_WeekRange>[];

    // 按逗号分割各段
    final List<String> segments = text
        .split(',')
        .map((String s) => s.trim())
        .toList();

    for (final String seg in segments) {
      if (seg.isEmpty) continue;

      // 尝试匹配 "N-M周" 或 "N-M周(单/双)"
      final RegExpMatch? rangeMatch = RegExp(
        r'(\d+)-(\d+)周(?:\(([单双])\))?',
      ).firstMatch(seg);
      if (rangeMatch != null) {
        final int start = int.parse(rangeMatch.group(1)!);
        final int end = int.parse(rangeMatch.group(2)!);
        CourseWeekType weekType = CourseWeekType.all;
        if (rangeMatch.group(3) == '单') {
          weekType = CourseWeekType.single;
        } else if (rangeMatch.group(3) == '双') {
          weekType = CourseWeekType.double;
        }
        ranges.add(_WeekRange(start: start, end: end, weekType: weekType));
        continue;
      }

      // 尝试匹配单周 "N周"
      final RegExpMatch? singleMatch = RegExp(r'(\d+)周').firstMatch(seg);
      if (singleMatch != null) {
        final int week = int.parse(singleMatch.group(1)!);
        ranges.add(_WeekRange(start: week, end: week));
        continue;
      }
    }

    return ranges;
  }

  // -------------------------------------------------------------------------
  // 课程聚合
  // -------------------------------------------------------------------------

  /// 向 courseMap 中添加一节课的排课信息。
  ///
  /// 按课程名称聚合——同名课程的多条排课记录合并为同一个 [Course]。
  /// 颜色从 [kCoursePresetColors] 循环分配。
  static void _addSession({
    required Map<String, _CourseBuilder> courseMap,
    required String courseName,
    required String teacher,
    required String location,
    required int weekday,
    required int sectionStart,
    required int sectionCount,
    required _WeekRange weekRange,
  }) {
    final _CourseBuilder builder = courseMap.putIfAbsent(
      courseName,
      () => _CourseBuilder(
        name: courseName,
        teacher: teacher,
        color:
            kCoursePresetColors[courseMap.length % kCoursePresetColors.length],
      ),
    );
    final List<int> incomingWeeks = _expandWeeks(
      start: weekRange.start,
      end: weekRange.end,
      weekType: weekRange.weekType,
    );

    final int existingIndex = builder.sessions.indexWhere(
      (CourseSession s) =>
          s.weekday == weekday &&
          s.startSection == sectionStart &&
          s.sectionCount == sectionCount &&
          s.location == location,
    );

    if (existingIndex != -1) {
      final CourseSession existing = builder.sessions[existingIndex];
      final List<int> existingWeeks = existing.customWeeks.isNotEmpty
          ? List<int>.from(existing.customWeeks)
          : _expandWeeks(
              start: existing.startWeek,
              end: existing.endWeek,
              weekType: existing.weekType,
            );

      final Set<int> mergedWeekSet = <int>{...existingWeeks, ...incomingWeeks};
      final List<int> mergedWeeks = mergedWeekSet.toList()..sort();

      builder.sessions[existingIndex] = CourseSession(
        weekday: weekday,
        startSection: sectionStart,
        sectionCount: sectionCount,
        location: location,
        startWeek: mergedWeeks.first,
        endWeek: mergedWeeks.last,
        weekType: CourseWeekType.all,
        customWeeks: mergedWeeks,
      );
    } else {
      builder.sessions.add(
        CourseSession(
          weekday: weekday,
          startSection: sectionStart,
          sectionCount: sectionCount,
          location: location,
          startWeek: incomingWeeks.first,
          endWeek: incomingWeeks.last,
          weekType: CourseWeekType.all,
          customWeeks: incomingWeeks,
        ),
      );
    }
    // 如果后续出现更完整的教师信息，更新
    if (builder.teacher.isEmpty && teacher.isNotEmpty) {
      builder.teacher = teacher;
    }
  }

  /// 将周次范围按单双周规则展开为显式周次列表，便于去重与合并。
  static List<int> _expandWeeks({
    required int start,
    required int end,
    required CourseWeekType weekType,
  }) {
    final List<int> weeks = <int>[];
    for (int week = start; week <= end; week++) {
      switch (weekType) {
        case CourseWeekType.all:
          weeks.add(week);
        case CourseWeekType.single:
          if (week.isOdd) {
            weeks.add(week);
          }
        case CourseWeekType.double:
          if (week.isEven) {
            weeks.add(week);
          }
      }
    }
    return weeks;
  }

  /// 规范化导入教室文本：去掉开头“XX校区”前缀，仅保留实际上课地点。
  ///
  /// 示例：
  /// - `连江校区博学楼105` -> `博学楼105`
  /// - `连江校区 博学楼105` -> `博学楼105`
  /// - `博学楼105` -> `博学楼105`
  static String _normalizeImportedLocation(String rawLocation) {
    final String text = rawLocation.trim();
    if (text.isEmpty) {
      return text;
    }

    final String stripped = text.replaceFirst(
      RegExp(r'^[\u4e00-\u9fa5A-Za-z]{1,12}校区[\s\-—–·、，,]*'),
      '',
    );

    String normalized = stripped.trim();
    // 若剥离后为空，则回退原值，避免误伤极端数据。
    if (normalized.isEmpty) normalized = text;
    // 将中文括号替换为英文括号以减少占位宽度
    normalized = normalized.replaceAll('（', '(').replaceAll('）', ')');
    return normalized;
  }

  // -------------------------------------------------------------------------
  // 工具方法
  // -------------------------------------------------------------------------

  /// 安全提取 [CallAsyncJavaScriptResult] 中的 Map。
  static Map<String, dynamic> _extractMap(CallAsyncJavaScriptResult? result) {
    final dynamic value = result?.value;
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }
}

// ---------------------------------------------------------------------------
// 内部辅助类
// ---------------------------------------------------------------------------

class _CourseBuilder {
  final String name;
  String teacher;
  final Color color;
  final List<CourseSession> sessions = <CourseSession>[];

  _CourseBuilder({
    required this.name,
    required this.teacher,
    required this.color,
  });
}

/// 节次 + 周次组合信息。
class _SectionWeekInfo {
  /// 起始节次（如 1、3、5）。
  final int sectionStart;

  /// 连续节次数（如 2 表示第1-2节）。
  final int sectionCount;

  /// 多段周次范围列表。
  final List<_WeekRange> weekRanges;

  const _SectionWeekInfo({
    required this.sectionStart,
    required this.sectionCount,
    required this.weekRanges,
  });
}

/// 单段周次范围。
class _WeekRange {
  final int start;
  final int end;
  final CourseWeekType weekType;

  const _WeekRange({
    required this.start,
    required this.end,
    this.weekType = CourseWeekType.all,
  });
}
