import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../models/course.dart';
import '../../../../models/course_schedule_config.dart';
import 'course_detail_sheet.dart';

/// 渲染课程表网格的组件，支持按照指定工作日展示课程区块。
class CourseScheduleTable extends StatefulWidget {
  /// 展示的课程列表 (courses)。
  final List<Course> courses;

  /// 当前选择的周次 (currentWeek)。
  final int currentWeek;

  /// 课节时间信息列表 (sections)。
  final List<SectionTime> sections;

  /// 展示顺序对应的星期文本 (weekdays)。
  final List<String> weekdays;

  /// 展示的具体星期索引 (weekdayIndexes)，周一为 1。
  final List<int> weekdayIndexes;

  /// 对应周次的日期列表 (weekDates)，用于在表头展示日期。
  final List<DateTime>? weekDates;

  /// 左侧时间列的宽度 (timeColumnWidth)。
  final double timeColumnWidth;

  /// 单节课的高度 (sectionHeight)。
  final double sectionHeight;

  /// 支持的最大周次数量 (maxWeek)。
  final int maxWeek;

  /// 周次变更时触发的回调 (onWeekChanged)。
  final ValueChanged<int>? onWeekChanged;

  /// 点击节次列时触发的回调 (onSectionTap)。
  final ValueChanged<SectionTime>? onSectionTap;

  /// 点击周次表头时触发的回调 (onWeekHeaderTap)。
  final VoidCallback? onWeekHeaderTap;

  /// 点击时间列任意位置时触发的回调 (onTimeColumnTap)（除了周次表头）。
  final VoidCallback? onTimeColumnTap;

  /// 是否渲染左侧时间列 (includeTimeColumn)。
  final bool includeTimeColumn;

  /// 是否包裹默认的白色卡片外观 (applySurface)。
  final bool applySurface;

  /// 控制垂直滚动的控制器 (scrollController)，便于与外部同步。
  final ScrollController? scrollController;

  /// 预留的左侧空白宽度 (leadingInset)，便于外部叠加独立列。
  final double leadingInset;

  /// 是否显示非本周课程 (showNonCurrentWeek)。
  final bool showNonCurrentWeek;

  /// 点击添加课程的回调 (onAddCourseTap)。
  final void Function(int weekday, int section)? onAddCourseTap;

  /// 课程被修改的回调 (onCourseChanged) (旧课程, 新课程)
  final void Function(Course oldCourse, Course newCourse)? onCourseChanged;

  /// 课程被删除的回调 (onCourseDeleted) (被删除的课程)
  final void Function(Course course)? onCourseDeleted;

  const CourseScheduleTable({
    super.key,
    required this.courses,
    required this.currentWeek,
    required this.sections,
    this.weekdays = const <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'],
    this.weekdayIndexes = const <int>[1, 2, 3, 4, 5, 6, 7],
    this.weekDates,
    this.timeColumnWidth = 64,
    this.sectionHeight = 76,
    this.maxWeek = 20,
    this.onWeekChanged,
    this.onSectionTap,
    this.onWeekHeaderTap,
    this.onTimeColumnTap,
    this.includeTimeColumn = true,
    this.applySurface = true,
    this.scrollController,
    this.leadingInset = 0,
    this.showNonCurrentWeek = false,
    this.onAddCourseTap,
    this.onCourseChanged,
    this.onCourseDeleted,
  }) : assert(
         weekdays.length == weekdayIndexes.length,
         'weekdays 与 weekdayIndexes 长度必须一致',
       );

  /// 计算时间列所需宽度，避免文本换行。
  static double resolveTimeColumnWidth(
    BuildContext context,
    List<SectionTime> sections, {
    double minWidth = 64,
  }) {
    if (sections.isEmpty) {
      return minWidth;
    }
    final TextDirection direction = Directionality.of(context);
    final TextTheme textTheme = Theme.of(context).textTheme;
    final TextStyle indexStyle = textTheme.titleSmall!.copyWith(
      fontWeight: FontWeight.w600,
      color: const Color(0xFF3D4555),
      letterSpacing: 0.3,
    );
    final TextStyle timeStyle = textTheme.bodySmall!.copyWith(
      color: const Color(0xFF6C768A),
    );

    double maxWidth = 0;
    for (final SectionTime section in sections) {
      final TextPainter indexPainter = TextPainter(
        text: TextSpan(text: '${section.index} 节', style: indexStyle),
        textDirection: direction,
      )..layout();
      final TextPainter startPainter = TextPainter(
        text: TextSpan(text: _formatTime(section.start), style: timeStyle),
        textDirection: direction,
      )..layout();
      final TextPainter endPainter = TextPainter(
        text: TextSpan(text: _formatTime(section.end), style: timeStyle),
        textDirection: direction,
      )..layout();

      final double candidate =
          math.max(
            indexPainter.width,
            math.max(startPainter.width, endPainter.width),
          ) +
          24;

      maxWidth = math.max(maxWidth, candidate);
    }
    return math.max(maxWidth, minWidth);
  }

  @override
  State<CourseScheduleTable> createState() => _CourseScheduleTableState();
}

class _CourseScheduleTableState extends State<CourseScheduleTable> {
  late final ScrollController _horizontalController;
  double _horizontalOffset = 0;
  ({int weekday, int section})? _selectedSlot;

  List<Course> get courses => widget.courses;
  int get currentWeek => widget.currentWeek;
  List<SectionTime> get sections => widget.sections;
  List<String> get weekdays => widget.weekdays;
  List<int> get weekdayIndexes => widget.weekdayIndexes;
  List<DateTime>? get weekDates => widget.weekDates;
  double get timeColumnWidth => widget.timeColumnWidth;
  double get sectionHeight => widget.sectionHeight;
  int get maxWeek => widget.maxWeek;
  ValueChanged<int>? get onWeekChanged => widget.onWeekChanged;
  ValueChanged<SectionTime>? get onSectionTap => widget.onSectionTap;
  VoidCallback? get onWeekHeaderTap => widget.onWeekHeaderTap;
  VoidCallback? get onTimeColumnTap => widget.onTimeColumnTap;
  bool get includeTimeColumn => widget.includeTimeColumn;
  bool get applySurface => widget.applySurface;
  ScrollController? get scrollController => widget.scrollController;
  double get leadingInset => widget.leadingInset;
  bool get showNonCurrentWeek => widget.showNonCurrentWeek;
  void Function(int weekday, int section)? get onAddCourseTap =>
      widget.onAddCourseTap;

  @override
  void initState() {
    super.initState();
    _horizontalController = ScrollController();
    _horizontalController.addListener(_handleHorizontalScroll);
  }

  void _handleHorizontalScroll() {
    if (!mounted) {
      return;
    }
    final double clampedOffset = _horizontalController.offset.clamp(
      0.0,
      double.infinity,
    );
    if ((clampedOffset - _horizontalOffset).abs() < 0.5) {
      return;
    }
    setState(() {
      _horizontalOffset = clampedOffset;
    });
  }

  @override
  void dispose() {
    _horizontalController.removeListener(_handleHorizontalScroll);
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double resolvedTimeWidth = includeTimeColumn
            ? timeColumnWidth
            : 0;
        final double rawMaxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : resolvedTimeWidth + weekdayIndexes.length * 120;
        final double maxWidth = math.max(rawMaxWidth - leadingInset, 0);
        final double gridWidth = (maxWidth - resolvedTimeWidth).clamp(
          0,
          double.infinity,
        );
        final double dayWidth = weekdayIndexes.isEmpty
            ? gridWidth
            : gridWidth / weekdayIndexes.length;
        final double daysWidth = weekdayIndexes.isEmpty
            ? gridWidth
            : dayWidth * weekdayIndexes.length;
        final double viewportWidth = math.max(daysWidth, gridWidth);
        final CourseTableGeometry geometry = buildCourseTableGeometry(
          sections,
          sectionHeight,
        );
        final double tableHeight = geometry.totalHeight;
        final Map<int, double> sectionOffsets = geometry.sectionOffsets;

        final Map<int, int> columnMap = <int, int>{
          for (int i = 0; i < weekdayIndexes.length; i++) weekdayIndexes[i]: i,
        };
        final List<_CourseBlock> blocks = _buildBlocks(columnMap);

        Widget content = Column(
          children: <Widget>[
            _buildHeaderRow(
              context,
              dayWidth,
              resolvedTimeWidth,
              viewportWidth,
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: _NoOverscrollBehavior(),
                child: SingleChildScrollView(
                  controller: scrollController,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SizedBox(
                    height: tableHeight,
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          left: includeTimeColumn ? resolvedTimeWidth : 0,
                          child: SingleChildScrollView(
                            controller: _horizontalController,
                            scrollDirection: Axis.horizontal,
                            physics: const ClampingScrollPhysics(),
                            child: SizedBox(
                              width: viewportWidth,
                              height: tableHeight,
                              child: Stack(
                                children: <Widget>[
                                  Positioned.fill(
                                    child: _buildGridLayer(
                                      context,
                                      dayWidth,
                                      geometry.rows,
                                      timeColumnWidth,
                                    ),
                                  ),
                                  if (_selectedSlot != null)
                                    _buildSelectionOverlay(
                                      context,
                                      dayWidth,
                                      sectionOffsets,
                                    ),
                                  for (final _CourseBlock block in blocks)
                                    _buildCourseBlock(
                                      context,
                                      block,
                                      dayWidth,
                                      sectionOffsets,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (includeTimeColumn)
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: resolvedTimeWidth,
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                color: Color(0xFFF4F6FB),
                              ),
                              child: _buildTimeColumn(context, geometry.rows),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

        content = Padding(
          padding: EdgeInsets.only(left: leadingInset),
          child: content,
        );

        if (!applySurface) {
          return content;
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.zero,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(borderRadius: BorderRadius.zero, child: content),
        );
      },
    );
  }

  /// 构建星期表头，与课程区滚动同步保持对齐。
  Widget _buildHeaderRow(
    BuildContext context,
    double dayWidth,
    double timeWidth,
    double viewportWidth,
  ) {
    final Color borderColor = Theme.of(
      context,
    ).dividerColor.withValues(alpha: 0.18);
    final bool hasDates =
        weekDates != null && weekDates!.length == weekdays.length;

    final double effectiveViewportWidth = viewportWidth > 0
        ? viewportWidth
        : dayWidth * weekdays.length;

    final Widget dayHeaders = SizedBox(
      width: effectiveViewportWidth,
      child: Row(
        children: <Widget>[
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

    return SizedBox(
      height: 78,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFF),
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              left: includeTimeColumn ? timeWidth : 0,
              child: ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Transform.translate(
                    offset: Offset(-_horizontalOffset, 0),
                    child: dayHeaders,
                  ),
                ),
              ),
            ),
            if (includeTimeColumn)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: timeWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6FB),
                    border: Border(right: BorderSide(color: borderColor)),
                  ),
                  child: _buildWeekSelectorCell(context),
                ),
              ),
          ],
        ),
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
    final HSLColor hsl = HSLColor.fromColor(primary);
    final Color activeColor = hsl
        .withLightness((hsl.lightness + 0.2).clamp(0.0, 1.0))
        .toColor();

    final TextStyle labelStyle = textTheme.bodyMedium!.copyWith(
      fontWeight: FontWeight.w600,
      color: isToday ? activeColor : const Color(0xFF3D4555),
    );
    final TextStyle dateStyle = textTheme.bodySmall!.copyWith(
      color: isToday ? activeColor : const Color(0xFF6C768A),
      letterSpacing: 0.4,
      fontWeight: isToday ? FontWeight.w600 : null,
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(label, style: labelStyle),
        if (date != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(_formatDate(date), style: dateStyle),
        ],
      ],
    );
  }

  /// 构建表头左侧的周次选择器。
  Widget _buildWeekSelectorCell(BuildContext context) {
    final int clampedWeek = currentWeek.clamp(1, maxWeek);
    final TextStyle textStyle = Theme.of(context).textTheme.titleSmall!
        .copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF3D4555));

    return Center(
      child: InkWell(
        onTap: onWeekHeaderTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFEAEBF0),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$clampedWeek 周',
                style: textStyle.copyWith(fontSize: 11, height: 1),
              ),
              const Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: Color(0xFF5D667A),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建课表网格背景。
  Widget _buildGridLayer(
    BuildContext context,
    double dayWidth,
    List<CourseTableRowSlot> rows,
    double timeColumnWidth,
  ) {
    final Color borderColor = Theme.of(
      context,
    ).dividerColor.withValues(alpha: 0.14);
    const Color altRowColor = Color(0xFFF9FAFD);
    const Color breakRowColor = Color(0xFFE8EBF3);
    final TextStyle labelStyle = Theme.of(context).textTheme.labelMedium!
        .copyWith(
          fontWeight: FontWeight.w600,
          color: const Color(0xFF7B8499),
          letterSpacing: 0.5,
          fontSize: 10,
        );

    return Column(
      children: <Widget>[
        for (final CourseTableRowSlot slot in rows)
          if (slot.isBreak)
            Container(
              height: slot.height,
              width: double.infinity,
              decoration: BoxDecoration(
                color: breakRowColor,
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: includeTimeColumn
                  ? null
                  : Center(
                      child: Transform.translate(
                        offset: Offset(-timeColumnWidth / 2, 0),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(slot.breakLabel ?? '', style: labelStyle),
                        ),
                      ),
                    ),
            )
          else
            SizedBox(
              height: slot.height,
              child: Row(
                children: <Widget>[
                  for (int day = 0; day < weekdayIndexes.length; day++)
                    GestureDetector(
                      onTap: () {
                        if (slot.section != null) {
                          setState(() {
                            _selectedSlot = (
                              weekday: weekdayIndexes[day],
                              section: slot.section!.index,
                            );
                          });
                        }
                      },
                      behavior: HitTestBehavior.translucent,
                      child: Container(
                        width: dayWidth,
                        decoration: BoxDecoration(
                          color:
                              slot.sectionOrder != null &&
                                  slot.sectionOrder!.isOdd
                              ? altRowColor
                              : Colors.transparent,
                          border: Border(
                            right: BorderSide(color: borderColor),
                            bottom: BorderSide(color: borderColor),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _buildSelectionOverlay(
    BuildContext context,
    double dayWidth,
    Map<int, double> sectionOffsets,
  ) {
    if (_selectedSlot == null) return const SizedBox.shrink();

    final int weekday = _selectedSlot!.weekday;
    final int section = _selectedSlot!.section;

    // 查找列索引
    final int columnIndex = weekdayIndexes.indexOf(weekday);
    if (columnIndex == -1) return const SizedBox.shrink();

    final double top = sectionOffsets[section] ?? 0.0;

    return Positioned(
      left: columnIndex * dayWidth,
      top: top,
      width: dayWidth,
      height: sectionHeight,
      child: GestureDetector(
        onTap: () {
          if (onAddCourseTap != null) {
            onAddCourseTap!(weekday, section);
          }
          setState(() {
            _selectedSlot = null;
          });
        },
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F3F5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Icon(Icons.add, color: Colors.black87, size: 24),
          ),
        ),
      ),
    );
  }

  /// 构建课程区块。
  Widget _buildCourseBlock(
    BuildContext context,
    _CourseBlock block,
    double dayWidth,
    Map<int, double> sectionOffsets,
  ) {
    final bool isNonCurrent = block.isNonCurrent;
    final List<Color> gradientColors = isNonCurrent
        ? <Color>[const Color(0xFFE0E0E0), const Color(0xFFF5F5F5)]
        : <Color>[
            block.course.color.withValues(alpha: 0.92),
            block.course.color.withValues(alpha: 0.78),
          ];

    final Color textColor = isNonCurrent
        ? const Color(0xFF9E9E9E)
        : const Color(0xFF333333);
    final Color detailColor = isNonCurrent
        ? const Color(0xFFBDBDBD)
        : const Color(0xFF666666);

    final TextTheme textTheme = Theme.of(context).textTheme;
    final TextStyle titleStyle = textTheme.titleSmall!.copyWith(
      color: textColor,
      fontWeight: FontWeight.w700,
    );
    final TextStyle detailStyle = textTheme.bodySmall!.copyWith(
      color: detailColor,
    );

    final double startOffset =
        sectionOffsets[block.session.startSection] ?? 0.0;
    final int endSectionIndex =
        block.session.startSection + block.session.sectionCount - 1;
    final double endOffset = sectionOffsets[endSectionIndex] ?? startOffset;
    final double blockHeight = endOffset + sectionHeight - startOffset;

    return Positioned(
      left: block.columnIndex * dayWidth,
      top: startOffset,
      width: dayWidth,
      height: blockHeight,
      child: GestureDetector(
        onTap: () => _showCourseDetails(context, block),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: gradientColors.first.withValues(alpha: 0.25),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (isNonCurrent)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '[非本周]',
                      style: detailStyle.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Text(
                  block.course.name,
                  style: titleStyle.copyWith(fontSize: 12),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  block.session.location,
                  style: detailStyle.copyWith(fontSize: 10),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCourseDetails(
    BuildContext context,
    _CourseBlock block,
  ) async {
    final List<CourseDetailItem> overlapping = <CourseDetailItem>[];

    for (final Course course in courses) {
      for (final CourseSession session in course.sessions) {
        if (session.weekday == block.session.weekday) {
          final int start1 = session.startSection;
          final int end1 = session.startSection + session.sectionCount - 1;
          final int start2 = block.session.startSection;
          final int end2 =
              block.session.startSection + block.session.sectionCount - 1;

          if (start1 <= end2 && end1 >= start2) {
            final SectionTime startSection = sections.firstWhere(
              (SectionTime s) => s.index == start1,
              orElse: () => sections.first,
            );
            final SectionTime endSection = sections.firstWhere(
              (SectionTime s) => s.index == end1,
              orElse: () => startSection,
            );

            overlapping.add(
              CourseDetailItem(
                course: course,
                session: session,
                startTime: startSection.start,
                endTime: endSection.end,
              ),
            );
          }
        }
      }
    }

    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => CourseDetailSheet(items: overlapping),
    );

    if (result != null && result is Map) {
      final action = result['action'];
      final target = result['target'] as Course;

      if (action == 'delete') {
        widget.onCourseDeleted?.call(target);
      } else if (action == 'update') {
        final newCourse = result['newCourse'] as Course;
        widget.onCourseChanged?.call(target, newCourse);
      }
    }
  }

  /// 根据当前周次构建需展示的课程区块。
  List<_CourseBlock> _buildBlocks(Map<int, int> columnMap) {
    final List<_CourseBlock> blocks = <_CourseBlock>[];
    if (sections.isEmpty) {
      return blocks;
    }
    for (final Course course in courses) {
      // 如果显示非本周课程，则遍历所有 session，否则只遍历本周 session
      final List<CourseSession> candidateSessions = showNonCurrentWeek
          ? course.sessions
          : course.sessionsForWeek(currentWeek);

      for (final CourseSession session in candidateSessions) {
        final int? columnIndex = columnMap[session.weekday];
        if (columnIndex == null) {
          continue;
        }

        final bool isCurrentWeek = session.occursInWeek(currentWeek);
        // 如果不显示非本周课程，且当前 session 不在本周，则跳过（虽然 candidateSessions 已经过滤了，但如果是 showNonCurrentWeek=true，这里需要判断状态）
        if (!showNonCurrentWeek && !isCurrentWeek) {
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
            isNonCurrent: !isCurrentWeek,
          ),
        );
      }
    }
    // 将非本周课程排在前面（底层），本周课程排在后面（顶层）
    blocks.sort((_CourseBlock a, _CourseBlock b) {
      if (a.isNonCurrent && !b.isNonCurrent) {
        return -1;
      }
      if (!a.isNonCurrent && b.isNonCurrent) {
        return 1;
      }
      return 0;
    });
    return blocks;
  }

  /// 构建时间列，支持进入节次配置。
  Widget _buildTimeColumn(BuildContext context, List<CourseTableRowSlot> rows) {
    return GestureDetector(
      onTap: onTimeColumnTap,
      behavior: HitTestBehavior.translucent,
      child: Column(
        children: <Widget>[
          for (final CourseTableRowSlot slot in rows)
            slot.isBreak
                ? _buildBreakCell(context, slot)
                : _buildTimeCell(context, slot),
        ],
      ),
    );
  }

  /// 构建单个节次单元。
  Widget _buildTimeCell(BuildContext context, CourseTableRowSlot slot) {
    final SectionTime section = slot.section!;
    final Color borderColor = Theme.of(
      context,
    ).dividerColor.withValues(alpha: 0.12);
    final TextTheme textTheme = Theme.of(context).textTheme;
    final TextStyle indexStyle = textTheme.titleSmall!.copyWith(
      fontWeight: FontWeight.w600,
      color: const Color(0xFF3D4555),
      letterSpacing: 0.3,
      // 降低字体大小以适应较窄/较短的时间列单元
      fontSize: 12,
    );
    final TextStyle timeStyle = textTheme.bodySmall!.copyWith(
      color: const Color(0xFF6C768A),
      height: 1.05,
      // 更小字体以避免竖直溢出
      fontSize: 11,
    );

    return Container(
      height: slot.height,
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6FB),
        border: Border(
          right: BorderSide(color: borderColor),
          bottom: BorderSide(color: borderColor),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('${section.index} 节', style: indexStyle),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_formatTime(section.start), style: timeStyle),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_formatTime(section.end), style: timeStyle),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建午休、晚修等分隔行单元。
  Widget _buildBreakCell(BuildContext context, CourseTableRowSlot slot) {
    final Color borderColor = Theme.of(
      context,
    ).dividerColor.withValues(alpha: 0.1);
    return Container(
      height: slot.height,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EBF3),
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
    );
  }

  /// 基于节次信息构建表格几何数据。
  CourseTableGeometry buildCourseTableGeometry(
    List<SectionTime> sections,
    double sectionHeight,
  ) {
    // 确保单节高度有最小限制，以免在高缩放或大量节次场景下发生溢出
    final double effectiveSectionHeight = math.max(sectionHeight, 48.0);
    if (sections.isEmpty) {
      return const CourseTableGeometry(
        rows: <CourseTableRowSlot>[],
        totalHeight: 0,
        sectionOffsets: <int, double>{},
      );
    }

    final List<CourseTableRowSlot> rows = <CourseTableRowSlot>[];
    final Map<int, double> sectionOffsets = <int, double>{};
    double cursor = 0;

    for (int i = 0; i < sections.length; i++) {
      final SectionTime section = sections[i];
      sectionOffsets[section.index] = cursor;
      rows.add(
        CourseTableRowSlot.section(
          section: section,
          height: effectiveSectionHeight,
          order: i,
        ),
      );
      cursor += effectiveSectionHeight;

      final bool hasNext = i < sections.length - 1;
      if (hasNext && sections[i + 1].segmentName != section.segmentName) {
        final String breakLabel = _resolveBreakLabel(
          section.segmentName,
          sections[i + 1].segmentName,
        );
        final double breakHeight = _resolveBreakRowHeight(
          effectiveSectionHeight,
        );
        rows.add(
          CourseTableRowSlot.breakRow(label: breakLabel, height: breakHeight),
        );
        cursor += breakHeight;
      }
    }

    return CourseTableGeometry(
      rows: rows,
      totalHeight: cursor,
      sectionOffsets: sectionOffsets,
    );
  }

  /// 推导分隔行的提示文案。
  String _resolveBreakLabel(String currentSegment, String nextSegment) {
    if (currentSegment == '上午' && nextSegment == '下午') {
      return '午休';
    }
    if (currentSegment == '下午' && nextSegment == '晚上') {
      return '晚修';
    }
    return '课间休息';
  }

  /// 计算分隔行高度，使视觉节奏更紧凑。
  double _resolveBreakRowHeight(double sectionHeight) {
    return 24.0;
  }
}

/// 使用 24 小时制格式化时间文本。
String _formatTime(TimeOfDay time) {
  final String hour = time.hour.toString().padLeft(2, '0');
  final String minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// 将日期转换为「月/日」的短格式。
String _formatDate(DateTime date) {
  final String month = date.month.toString();
  final String day = date.day.toString().padLeft(2, '0');
  return '$month/$day';
}

/// 判断两个日期是否属于同一天。
bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// 内部的课程区块数据模型。
class _CourseBlock {
  /// 区块对应的课程 (course)。
  final Course course;

  /// 区块对应的节次安排 (session)。
  final CourseSession session;

  /// 区块所在列索引 (columnIndex)。
  final int columnIndex;

  /// 区块起始时间 (startTime)。
  final TimeOfDay startTime;

  /// 区块结束时间 (endTime)。
  final TimeOfDay endTime;

  /// 是否为非本周课程 (isNonCurrent)。
  final bool isNonCurrent;

  const _CourseBlock({
    required this.course,
    required this.session,
    required this.columnIndex,
    required this.startTime,
    required this.endTime,
    this.isNonCurrent = false,
  });
}

/// 课表的行槽信息，用于区分节次行与分隔行。
class CourseTableRowSlot {
  /// 对应的节次信息 (section)，若为分隔行则为空。
  final SectionTime? section;

  /// 分隔行展示的文案 (breakLabel)。
  final String? breakLabel;

  /// 当前行高度 (height)。
  final double height;

  /// 节次在序列中的顺序 (sectionOrder)，分隔行则为空。
  final int? sectionOrder;

  const CourseTableRowSlot._({
    required this.section,
    required this.breakLabel,
    required this.height,
    required this.sectionOrder,
  });

  /// 构建普通节次行。
  const CourseTableRowSlot.section({
    required SectionTime section,
    required double height,
    required int order,
  }) : this._(
         section: section,
         breakLabel: null,
         height: height,
         sectionOrder: order,
       );

  /// 构建分隔行。
  const CourseTableRowSlot.breakRow({
    required String label,
    required double height,
  }) : this._(
         section: null,
         breakLabel: label,
         height: height,
         sectionOrder: null,
       );

  /// 判断当前行是否为分隔行。
  bool get isBreak => breakLabel != null;
}

/// 网格几何数据，包含行槽、总高度与节次偏移。
class CourseTableGeometry {
  /// 所有行槽信息 (rows)。
  final List<CourseTableRowSlot> rows;

  /// 网格总高度 (totalHeight)。
  final double totalHeight;

  /// 每个节次对应的纵向偏移 (sectionOffsets)。
  final Map<int, double> sectionOffsets;

  const CourseTableGeometry({
    required this.rows,
    required this.totalHeight,
    required this.sectionOffsets,
  });
}

/// 不使用过度滚动效果的滚动行为。
class _NoOverscrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
