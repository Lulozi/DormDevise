import 'package:flutter/material.dart';

import '../../../models/course.dart';
import '../../../models/course_schedule_config.dart';

/// 渲染课程表网格的组件，支持按照指定工作日展示课程区块。
class CourseScheduleTable extends StatelessWidget {
  /// 展示的课程列表。
  final List<Course> courses;

  /// 当前选择的周次。
  final int currentWeek;

  /// 课节时间信息列表。
  final List<SectionTime> sections;

  /// 展示顺序对应的星期文本。
  final List<String> weekdays;

  /// 展示的具体星期索引，周一为 1。
  final List<int> weekdayIndexes;

  /// 对应周次的日期列表，用于在表头展示日期。
  final List<DateTime>? weekDates;

  /// 左侧时间列的宽度。
  final double timeColumnWidth;

  /// 单节课的高度。
  final double sectionHeight;

  /// 支持的最大周次数量。
  final int maxWeek;

  /// 周次变更时触发的回调。
  final ValueChanged<int>? onWeekChanged;

  /// 点击节次列时触发的回调。
  final ValueChanged<SectionTime>? onSectionTap;

  const CourseScheduleTable({
    super.key,
    required this.courses,
    required this.currentWeek,
    required this.sections,
    this.weekdays = const <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'],
    this.weekdayIndexes = const <int>[1, 2, 3, 4, 5, 6, 7],
    this.weekDates,
    this.timeColumnWidth = 84,
    this.sectionHeight = 76,
    this.maxWeek = 20,
    this.onWeekChanged,
    this.onSectionTap,
  }) : assert(
         weekdays.length == weekdayIndexes.length,
         'weekdays 与 weekdayIndexes 长度必须一致',
       );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : timeColumnWidth + weekdayIndexes.length * 120;
        final double gridWidth = (maxWidth - timeColumnWidth).clamp(
          0,
          double.infinity,
        );
        final double dayWidth = weekdayIndexes.isEmpty
            ? gridWidth
            : gridWidth / weekdayIndexes.length;
        final double tableHeight = sections.length * sectionHeight;

        final Map<int, int> columnMap = <int, int>{
          for (int i = 0; i < weekdayIndexes.length; i++) weekdayIndexes[i]: i,
        };
        final List<_CourseBlock> blocks = _buildBlocks(columnMap);

        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              children: <Widget>[
                _buildHeaderRow(context, dayWidth),
                Expanded(
                  child: Scrollbar(
                    thumbVisibility: false,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: SizedBox(
                        height: tableHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SizedBox(
                              width: timeColumnWidth,
                              child: _buildTimeColumn(context),
                            ),
                            SizedBox(
                              width: dayWidth * weekdayIndexes.length,
                              child: Stack(
                                children: <Widget>[
                                  Positioned.fill(
                                    child: _buildGridLayer(context, dayWidth),
                                  ),
                                  for (final _CourseBlock block in blocks)
                                    _buildCourseBlock(context, block, dayWidth),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 构建星期表头。
  Widget _buildHeaderRow(BuildContext context, double dayWidth) {
    final Color borderColor = Theme.of(
      context,
    ).dividerColor.withValues(alpha: 0.18);
    final bool hasDates =
        weekDates != null && weekDates!.length == weekdays.length;

    return Container(
      height: 78,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: timeColumnWidth,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: borderColor)),
            ),
            child: _buildWeekSelectorCell(context),
          ),
          for (int i = 0; i < weekdays.length; i++)
            SizedBox(
              width: dayWidth,
              child: _buildHeaderDayCell(
                context,
                label: weekdays[i],
                date: hasDates ? weekDates![i] : null,
              ),
            ),
        ],
      ),
    );
  }

  /// 构建表头中的单个日期单元。
  Widget _buildHeaderDayCell(
    BuildContext context, {
    required String label,
    DateTime? date,
  }) {
    final bool isToday = date != null && _isSameDate(date, DateTime.now());
    final TextTheme textTheme = Theme.of(context).textTheme;
    final Color primary = Theme.of(context).colorScheme.primary;
    final TextStyle labelStyle = textTheme.bodyMedium!.copyWith(
      fontWeight: FontWeight.w600,
      color: isToday ? primary : Colors.black87,
    );
    final TextStyle dateStyle = textTheme.bodySmall!.copyWith(
      color: isToday ? primary : Colors.black54,
      letterSpacing: 0.4,
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(label, style: labelStyle),
        if (date != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(_formatDate(date), style: dateStyle),
        ],
      ],
    );
  }

  /// 构建表头左侧的周次选择器。
  Widget _buildWeekSelectorCell(BuildContext context) {
    final int clampedWeek = currentWeek.clamp(1, maxWeek);
    final TextStyle optionStyle = Theme.of(context).textTheme.titleSmall!
        .copyWith(fontWeight: FontWeight.w700, color: Colors.black87);
    final Color background = const Color(0xFFE9EDF5);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: clampedWeek,
            isExpanded: true,
            borderRadius: BorderRadius.circular(14),
            alignment: Alignment.center,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
            dropdownColor: Colors.white,
            style: optionStyle,
            onChanged: onWeekChanged == null
                ? null
                : (int? value) {
                    if (value != null && value != currentWeek) {
                      onWeekChanged!(value);
                    }
                  },
            items: List<DropdownMenuItem<int>>.generate(
              maxWeek,
              (int index) => DropdownMenuItem<int>(
                value: index + 1,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('${index + 1}周', style: optionStyle),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建课表网格背景。
  Widget _buildGridLayer(BuildContext context, double dayWidth) {
    final Color borderColor = Theme.of(
      context,
    ).dividerColor.withValues(alpha: 0.14);
    final Color altRowColor = Colors.grey.withValues(alpha: 0.03);

    return Column(
      children: <Widget>[
        for (int row = 0; row < sections.length; row++)
          SizedBox(
            height: sectionHeight,
            child: Row(
              children: <Widget>[
                for (int day = 0; day < weekdayIndexes.length; day++)
                  Container(
                    width: dayWidth,
                    decoration: BoxDecoration(
                      color: row.isOdd ? altRowColor : Colors.white,
                      border: Border(
                        right: BorderSide(color: borderColor),
                        bottom: BorderSide(color: borderColor),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// 构建课程区块。
  Widget _buildCourseBlock(
    BuildContext context,
    _CourseBlock block,
    double dayWidth,
  ) {
    final List<Color> gradientColors = <Color>[
      block.course.color.withValues(alpha: 0.92),
      block.course.color.withValues(alpha: 0.78),
    ];
    final TextTheme textTheme = Theme.of(context).textTheme;
    final TextStyle titleStyle = textTheme.titleSmall!.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w700,
    );
    final TextStyle detailStyle = textTheme.bodySmall!.copyWith(
      color: Colors.white.withValues(alpha: 0.9),
    );

    return Positioned(
      left: block.columnIndex * dayWidth,
      top: (block.session.startSection - 1) * sectionHeight,
      width: dayWidth,
      height: block.session.sectionCount * sectionHeight,
      child: Container(
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: gradientColors.first.withValues(alpha: 0.25),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                block.course.name,
                style: titleStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                block.course.teacher,
                style: detailStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                block.session.location,
                style: detailStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.menu_book_outlined,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                  const Spacer(),
                  Text(
                    '${_formatTime(block.startTime)}-${_formatTime(block.endTime)}',
                    style: detailStyle.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 根据当前周次构建需展示的课程区块。
  List<_CourseBlock> _buildBlocks(Map<int, int> columnMap) {
    final List<_CourseBlock> blocks = <_CourseBlock>[];
    if (sections.isEmpty) {
      return blocks;
    }
    for (final Course course in courses) {
      final List<CourseSession> weekSessions = course.sessionsForWeek(
        currentWeek,
      );
      for (final CourseSession session in weekSessions) {
        final int? columnIndex = columnMap[session.weekday];
        if (columnIndex == null) {
          continue;
        }
        final SectionTime startSection = sections.firstWhere(
          (SectionTime info) => info.index == session.startSection,
          orElse: () => sections.first,
        );
        final int endIndex = session.startSection + session.sectionCount - 1;
        final SectionTime endSection = sections.firstWhere(
          (SectionTime info) => info.index == endIndex,
          orElse: () => startSection,
        );
        blocks.add(
          _CourseBlock(
            course: course,
            session: session,
            columnIndex: columnIndex,
            startTime: startSection.start,
            endTime: endSection.end,
          ),
        );
      }
    }
    return blocks;
  }

  /// 构建时间列，支持进入节次配置。
  Widget _buildTimeColumn(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < sections.length; i++)
          _buildTimeCell(
            context,
            section: sections[i],
            isSegmentStart:
                i == 0 ||
                sections[i - 1].segmentName != sections[i].segmentName,
          ),
      ],
    );
  }

  /// 构建单个节次单元。
  Widget _buildTimeCell(
    BuildContext context, {
    required SectionTime section,
    required bool isSegmentStart,
  }) {
    final Color borderColor = Theme.of(
      context,
    ).dividerColor.withValues(alpha: 0.14);
    final TextTheme textTheme = Theme.of(context).textTheme;
    final TextStyle indexStyle = textTheme.titleSmall!.copyWith(
      fontWeight: FontWeight.w700,
      color: Colors.black87,
    );
    final TextStyle timeStyle = textTheme.bodySmall!.copyWith(
      color: Colors.black54,
      height: 1.1,
    );

    return InkWell(
      onTap: onSectionTap != null ? () => onSectionTap!(section) : null,
      child: Container(
        height: sectionHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            right: BorderSide(color: borderColor),
            bottom: BorderSide(color: borderColor),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (isSegmentStart) ...<Widget>[
                _buildSegmentTag(context, section.segmentName),
                const SizedBox(height: 6),
              ],
              Text('${section.index} 节', style: indexStyle),
              const SizedBox(height: 6),
              Text(_formatTime(section.start), style: timeStyle),
              Text(_formatTime(section.end), style: timeStyle),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建设定的时段标签。
  Widget _buildSegmentTag(BuildContext context, String name) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final TextStyle tagStyle = Theme.of(context).textTheme.labelSmall!.copyWith(
      color: primary,
      fontWeight: FontWeight.w600,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(name, style: tagStyle),
      ),
    );
  }

  /// 使用 24 小时制格式化时间。
  String _formatTime(TimeOfDay time) {
    final String hour = time.hour.toString().padLeft(2, '0');
    final String minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// 将日期格式化为自然语言展示。
  String _formatDate(DateTime date) {
    final String month = date.month.toString();
    final String day = date.day.toString().padLeft(2, '0');
    return '$month/$day';
  }

  /// 判断两个日期是否同一天。
  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

/// 内部的课程区块数据模型。
class _CourseBlock {
  /// 区块对应的课程。
  final Course course;

  /// 区块对应的节次安排。
  final CourseSession session;

  /// 区块所在列索引。
  final int columnIndex;

  /// 区块起始时间。
  final TimeOfDay startTime;

  /// 区块结束时间。
  final TimeOfDay endTime;

  const _CourseBlock({
    required this.course,
    required this.session,
    required this.columnIndex,
    required this.startTime,
    required this.endTime,
  });
}
