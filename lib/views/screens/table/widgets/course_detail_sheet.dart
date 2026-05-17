import 'package:flutter/material.dart';
import '../../../../models/course.dart';
import '../../../../utils/color_extensions.dart';
import '../course_edit_page.dart';

/// 课程详情底部弹窗
class CourseDetailSheet extends StatelessWidget {
  /// 课程详情项列表 (items)
  final List<CourseDetailItem> items;
  final List<Course> allCourses;
  final int maxWeek;
  final bool isReadOnly;

  const CourseDetailSheet({
    super.key,
    required this.items,
    required this.allCourses,
    this.maxWeek = 20,
    this.isReadOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 合并同一课程、同一时段、不同教室的项为同一卡片
    final List<_MergedCourseCard> mergedCards = _mergeCards(items);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context),
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              shrinkWrap: true,
              itemCount: mergedCards.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _buildMergedCourseCard(context, mergedCards[index]);
              },
            ),
          ),
          if (!isReadOnly) _buildAddButton(context),
        ],
      ),
    );
  }

  /// 将课程详情项按"同一课程名 + 同一时段"合并。
  ///
  /// 同一课程、同一 weekday、同一 startSection、同一 sectionCount
  /// 但不同教室的项合并为同一张卡片，卡片内按教室分组展示各自的周次。
  static List<_MergedCourseCard> _mergeCards(List<CourseDetailItem> items) {
    // 按 (课程名, weekday, startSection, sectionCount) 分组
    final Map<String, List<CourseDetailItem>> grouped = {};
    for (final item in items) {
      final key =
          '${item.course.name}|${item.session.weekday}|${item.session.startSection}|${item.session.sectionCount}';
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(item);
    }

    final List<_MergedCourseCard> cards = [];
    for (final entry in grouped.entries) {
      final groupItems = entry.value;
      if (groupItems.isEmpty) continue;

      // 取第一项作为课程参考
      final firstItem = groupItems.first;
      final course = firstItem.course;
      final session = firstItem.session;

      // 构建时段标签
      final weekdayStr = _staticWeekdayToString(session.weekday);
      final String timeLabel;
      if (session.sectionCount == 1) {
        timeLabel = '$weekdayStr 第 ${session.startSection} 节';
      } else {
        timeLabel =
            '$weekdayStr 第 ${session.startSection}-${session.startSection + session.sectionCount - 1} 节';
      }
      final String timeRange =
          '(${_staticFormatTime(firstItem.startTime)} - ${_staticFormatTime(firstItem.endTime)})';

      // 收集各教室及其周次信息（去重同教室名，合并周次）
      final Map<String, Set<int>> classroomWeeks = {};
      for (final item in groupItems) {
        final loc = item.session.location.trim().isEmpty
            ? '未命名教室'
            : item.session.location.trim();
        classroomWeeks.putIfAbsent(loc, () => {});
        classroomWeeks[loc]!.addAll(_staticResolveSortedWeeks(item.session));
      }

      // 构建教室周次信息列表
      final List<_ClassroomWeekInfo> classrooms = [];
      final Set<int> allWeeksUnion = {};
      for (final entry2 in classroomWeeks.entries) {
        final weeks = entry2.value;
        allWeeksUnion.addAll(weeks);
        classrooms.add(
          _ClassroomWeekInfo(
            location: entry2.key,
            weekLabel: _staticFormatWeeksSet(weeks),
          ),
        );
      }

      // 排序：按教室名（空教室排前面，有名字按字母序）
      classrooms.sort((a, b) {
        final aEmpty = a.location.isEmpty || a.location == '未命名教室';
        final bEmpty = b.location.isEmpty || b.location == '未命名教室';
        if (aEmpty && !bEmpty) return -1;
        if (!aEmpty && bEmpty) return 1;
        return a.location.compareTo(b.location);
      });

      // 计算总上课周数（所有教室周次的并集）
      final String totalWeeksLabel = _staticFormatWeeksSet(allWeeksUnion);

      cards.add(
        _MergedCourseCard(
          course: course,
          classrooms: classrooms,
          timeLabel: timeLabel,
          timeRange: timeRange,
          totalWeeksLabel: totalWeeksLabel,
        ),
      );
    }

    // 对合并卡片排序：先按最早周次，再按课程名
    cards.sort((a, b) {
      // 计算各自的最早周次
      int aEarliest = 999;
      for (final cr in a.classrooms) {
        final w = _parseEarliestWeek(cr.weekLabel);
        if (w < aEarliest) aEarliest = w;
      }
      int bEarliest = 999;
      for (final cr in b.classrooms) {
        final w = _parseEarliestWeek(cr.weekLabel);
        if (w < bEarliest) bEarliest = w;
      }
      final weekCompare = aEarliest.compareTo(bEarliest);
      if (weekCompare != 0) return weekCompare;
      return a.course.name.compareTo(b.course.name);
    });

    return cards;
  }

  /// 静态周次格式化（避免实例方法调用限制）。
  static String _staticFormatWeeksSet(Set<int> weeks) {
    if (weeks.isEmpty) return '未配置';
    final sorted = weeks.toList()..sort();
    if (sorted.length == 1) return '第${sorted.first}周';

    final buffer = StringBuffer();
    int rangeStart = sorted.first;
    int rangeEnd = sorted.first;

    for (int i = 1; i < sorted.length; i++) {
      if (sorted[i] == rangeEnd + 1) {
        rangeEnd = sorted[i];
      } else {
        if (buffer.isNotEmpty) buffer.write('、');
        if (rangeStart == rangeEnd) {
          buffer.write('$rangeStart');
        } else {
          buffer.write('$rangeStart-$rangeEnd');
        }
        rangeStart = sorted[i];
        rangeEnd = sorted[i];
      }
    }
    if (buffer.isNotEmpty) buffer.write('、');
    if (rangeStart == rangeEnd) {
      buffer.write('$rangeStart');
    } else {
      buffer.write('$rangeStart-$rangeEnd');
    }
    return '第${buffer.toString()}周';
  }

  /// 静态解析周次列表。
  static List<int> _staticResolveSortedWeeks(CourseSession session) {
    if (session.customWeeks.isNotEmpty) {
      final List<int> weeks = session.customWeeks.toSet().toList()..sort();
      return weeks;
    }
    final List<int> weeks = <int>[];
    for (int week = session.startWeek; week <= session.endWeek; week++) {
      if (session.occursInWeek(week)) {
        weeks.add(week);
      }
    }
    return weeks;
  }

  /// 静态星期转换。
  static String _staticWeekdayToString(int weekday) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    if (weekday >= 1 && weekday <= 7) return weekdays[weekday - 1];
    return '';
  }

  /// 从周次标签中解析最早周次数字（如 "第1-10周" → 1, "未配置" → 999）。
  static int _parseEarliestWeek(String weekLabel) {
    if (weekLabel == '未配置') return 999;
    // 提取第一个连续数字
    final match = RegExp(r'\d+').firstMatch(weekLabel);
    if (match != null) {
      return int.tryParse(match.group(0)!) ?? 999;
    }
    return 999;
  }

  /// 静态时间格式化。
  static String _staticFormatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Widget _buildAddButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextButton(
        onPressed: () async {
          final navigator = Navigator.of(context);
          final result = await navigator.push(
            MaterialPageRoute(
              builder: (context) => CourseEditPage(
                existingCourses: allCourses,
                initialWeekday: items.isNotEmpty
                    ? items.first.session.weekday
                    : null,
                initialSection: items.isNotEmpty
                    ? items.first.session.startSection
                    : null,
                maxWeek: maxWeek,
              ),
              fullscreenDialog: true,
            ),
          );

          if (result != null && result is Course) {
            navigator.pop({'action': 'create', 'newCourse': result});
          }
        },
        child: Text(
          '新建课程',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  /// 构建顶部标题栏
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.center,
            child: Text(
              '课程详情',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建合并后的课程卡片（同一课程、同一时段、不同教室合并为单卡片）。
  Widget _buildMergedCourseCard(BuildContext context, _MergedCourseCard card) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：课程名 + 编辑按钮
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? dimColorForDark(card.course.color)
                      : card.course.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  card.course.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              if (!isReadOnly)
                GestureDetector(
                  onTap: () {
                    final navigator = Navigator.of(context);
                    navigator
                        .push(
                          MaterialPageRoute(
                            settings: RouteSettings(arguments: card.course),
                            builder: (context) => CourseEditPage(
                              course: card.course,
                              existingCourses: allCourses,
                              maxWeek: maxWeek,
                            ),
                            fullscreenDialog: true,
                          ),
                        )
                        .then((result) {
                          if (result != null) {
                            if (result == 'delete') {
                              navigator.pop({
                                'action': 'delete',
                                'target': card.course,
                              });
                            } else if (result is Course) {
                              navigator.pop({
                                'action': 'update',
                                'target': card.course,
                                'newCourse': result,
                              });
                            }
                          }
                        });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '编辑',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // 教室区域：多教室与单教室采用不同格式
          if (card.classrooms.length > 1)
            // 多教室格式：教室1：教室名1 缩进 · 周次
            ...card.classrooms.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final cr = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow(context, '教室$idx', cr.location),
                    // 周次信息靠左对齐，与上方教室名对齐。
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.outline,
                          height: 1.5,
                        ),
                        children: [
                          const TextSpan(
                            text: '· ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: cr.weekLabel),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            })
          else if (card.classrooms.length == 1)
            // 单教室格式：教室：教室名
            _buildDetailRow(context, '教室', card.classrooms.first.location),
          // 备注（如老师）
          _buildDetailRow(context, '备注（如老师）', card.course.teacher),
          const SizedBox(height: 4),
          // 时段
          _buildDetailRow(
            context,
            card.timeLabel,
            card.timeRange,
            showColon: false,
          ),
          const SizedBox(height: 4),
          // 总上课周数
          _buildDetailRow(context, card.totalWeeksLabel, '', showColon: false),
        ],
      ),
    );
  }

  /// 构建详情行（标签 + 值）
  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value, {
    bool showColon = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final List<InlineSpan> children = <InlineSpan>[];
    if (value.trim().isEmpty) {
      children.add(TextSpan(text: showColon ? '$label： ' : label));
    } else {
      children.add(TextSpan(text: showColon ? '$label： ' : '$label '));
      children.add(
        TextSpan(
          text: value,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 13, color: colorScheme.outline, height: 1.5),
        children: children,
      ),
    );
  }
}

/// 课程详情项数据模型
class CourseDetailItem {
  /// 课程信息 (course)
  final Course course;

  /// 课节信息 (session)
  final CourseSession session;

  /// 开始时间 (startTime)
  final TimeOfDay startTime;

  /// 结束时间 (endTime)
  final TimeOfDay endTime;

  CourseDetailItem({
    required this.course,
    required this.session,
    required this.startTime,
    required this.endTime,
  });
}

// 合并卡片数据模型

/// 合并后的课程卡片数据（同一课程、同一时段、不同教室合并）。
class _MergedCourseCard {
  /// 课程信息。
  final Course course;

  /// 各教室及其周次信息列表。
  final List<_ClassroomWeekInfo> classrooms;

  /// 时段标签，如 "周一 第1-2节"。
  final String timeLabel;

  /// 时间范围，如 "(08:00-09:40)"。
  final String timeRange;

  /// 所有教室周次的并集标签。
  final String totalWeeksLabel;

  const _MergedCourseCard({
    required this.course,
    required this.classrooms,
    required this.timeLabel,
    required this.timeRange,
    required this.totalWeeksLabel,
  });
}

/// 教室周次信息（单个教室的周次显示）。
class _ClassroomWeekInfo {
  /// 教室名称。
  final String location;

  /// 周次显示文本，如 "第1-10周"。
  final String weekLabel;

  const _ClassroomWeekInfo({required this.location, required this.weekLabel});
}
