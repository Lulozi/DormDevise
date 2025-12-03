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

  /// 点击日期表头时触发的回调 (onHeaderDateTap)。
  final VoidCallback? onHeaderDateTap;

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

  /// 课程被添加的回调 (onCourseAdded) (新课程)
  final void Function(Course course)? onCourseAdded;

  /// 编辑模式状态改变的回调 (onEditModeChanged) (是否处于编辑模式)
  final ValueChanged<bool>? onEditModeChanged;

  /// 用于强制重置编辑模式的令牌 (editModeResetToken)
  /// 当此对象发生变化时，组件会强制退出编辑模式
  final Object? editModeResetToken;

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
    this.onHeaderDateTap,
    this.onTimeColumnTap,
    this.includeTimeColumn = true,
    this.applySurface = true,
    this.scrollController,
    this.leadingInset = 0,
    this.showNonCurrentWeek = false,
    this.onAddCourseTap,
    this.onCourseChanged,
    this.onCourseDeleted,
    this.onCourseAdded,
    this.onEditModeChanged,
    this.editModeResetToken,
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

class _CourseScheduleTableState extends State<CourseScheduleTable>
    with SingleTickerProviderStateMixin {
  late final ScrollController _horizontalController;
  late final AnimationController _selectionAnimationController;
  late final Animation<double> _selectionAnimation;
  double _horizontalOffset = 0;
  ({int weekday, int section})? _selectedSlot;
  ({int weekday, int section})? _previousSlot;

  // 拖拽相关状态
  _CourseBlock? _selectedBlock; // 当前选中的课程块（编辑模式）
  _CourseBlock? _draggingBlock;
  Offset _dragOffset = Offset.zero;
  Offset _initialDragOffset = Offset.zero; // 拖拽开始时的卡片位置
  double _resizeStartGlobalY = 0.0; // 调整大小的起始Y坐标
  int? _dragTargetWeekday;
  int? _dragTargetSection;
  int? _dragTargetSectionCount;
  bool _isResizing = false; // 是否在调整大小模式
  bool _hasConflict = false; // 是否有冲突

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

  void _updateEditMode() {
    final bool isEditing = _selectedBlock != null || _draggingBlock != null;
    if (widget.onEditModeChanged != null) {
      widget.onEditModeChanged!(isEditing);
    }
  }

  @override
  void initState() {
    super.initState();
    _horizontalController = ScrollController();
    _horizontalController.addListener(_handleHorizontalScroll);
    _selectionAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _selectionAnimation = CurvedAnimation(
      parent: _selectionAnimationController,
      curve: Curves.easeOut,
    );
  }

  void _handleHorizontalScroll() {
    if (!mounted || !_horizontalController.hasClients) {
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
  void didUpdateWidget(CourseScheduleTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editModeResetToken != oldWidget.editModeResetToken) {
      if (_selectedBlock != null ||
          _draggingBlock != null ||
          _selectedSlot != null) {
        setState(() {
          _selectedBlock = null;
          _draggingBlock = null;
          _isResizing = false;
          _dragOffset = Offset.zero;
          _dragTargetWeekday = null;
          _dragTargetSection = null;
          _dragTargetSectionCount = null;
          _hasConflict = false;
          if (_selectedSlot != null) {
            _previousSlot = _selectedSlot;
            _selectedSlot = null;
            _selectionAnimationController.forward(from: 0);
          }
        });
        _updateEditMode();
      }
    }
  }

  @override
  void dispose() {
    _horizontalController.removeListener(_handleHorizontalScroll);
    _horizontalController.dispose();
    _selectionAnimationController.dispose();
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
        final bool shouldScroll = viewportWidth > gridWidth + 1.0;
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
                  physics: _selectedBlock != null || _draggingBlock != null
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SizedBox(
                    height: tableHeight,
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          left: includeTimeColumn ? resolvedTimeWidth : 0,
                          child: shouldScroll
                              ? SingleChildScrollView(
                                  controller: _horizontalController,
                                  scrollDirection: Axis.horizontal,
                                  physics:
                                      _selectedBlock != null ||
                                          _draggingBlock != null
                                      ? const NeverScrollableScrollPhysics()
                                      : const ClampingScrollPhysics(),
                                  child: SizedBox(
                                    width: viewportWidth,
                                    height: tableHeight,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: <Widget>[
                                        Positioned.fill(
                                          child: _buildGridLayer(
                                            context,
                                            dayWidth,
                                            geometry.rows,
                                            timeColumnWidth,
                                          ),
                                        ),
                                        // 编辑模式下的背景点击层（用于取消选中）
                                        if (_selectedBlock != null)
                                          Positioned.fill(
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () {
                                                setState(() {
                                                  _selectedBlock = null;
                                                });
                                                _updateEditMode();
                                              },
                                              child: Container(
                                                color: Colors.transparent,
                                              ),
                                            ),
                                          ),
                                        if (_selectedSlot != null ||
                                            _previousSlot != null)
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
                                            viewportWidth,
                                            tableHeight,
                                          ),
                                        // 拖拽时的悬浮卡片
                                        if (_draggingBlock != null)
                                          _buildDraggingOverlay(
                                            context,
                                            dayWidth,
                                            sectionOffsets,
                                          ),
                                      ],
                                    ),
                                  ),
                                )
                              : SizedBox(
                                  width: viewportWidth,
                                  height: tableHeight,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: <Widget>[
                                      Positioned.fill(
                                        child: _buildGridLayer(
                                          context,
                                          dayWidth,
                                          geometry.rows,
                                          timeColumnWidth,
                                        ),
                                      ),
                                      // 编辑模式下的背景点击层（用于取消选中）
                                      if (_selectedBlock != null)
                                        Positioned.fill(
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              setState(() {
                                                _selectedBlock = null;
                                              });
                                              _updateEditMode();
                                            },
                                            child: Container(
                                              color: Colors.transparent,
                                            ),
                                          ),
                                        ),
                                      if (_selectedSlot != null ||
                                          _previousSlot != null)
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
                                          viewportWidth,
                                          tableHeight,
                                        ),
                                      // 拖拽时的悬浮卡片
                                      if (_draggingBlock != null)
                                        _buildDraggingOverlay(
                                          context,
                                          dayWidth,
                                          sectionOffsets,
                                        ),
                                    ],
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

    return GestureDetector(
      onTap: () {
        if (_selectedBlock != null) {
          setState(() {
            _selectedBlock = null;
          });
          _updateEditMode();
        }
        if (_selectedSlot != null) {
          setState(() {
            _previousSlot = _selectedSlot;
            _selectedSlot = null;
          });
          _selectionAnimationController.forward(from: 0);
        }
        widget.onHeaderDateTap?.call();
      },
      behavior: HitTestBehavior.translucent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(label, style: labelStyle),
          if (date != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(_formatDate(date), style: dateStyle),
          ],
        ],
      ),
    );
  }

  /// 构建表头左侧的周次选择器。
  Widget _buildWeekSelectorCell(BuildContext context) {
    final int clampedWeek = currentWeek.clamp(1, maxWeek);
    final TextStyle textStyle = Theme.of(context).textTheme.titleSmall!
        .copyWith(fontWeight: FontWeight.w700, color: const Color(0xFF3D4555));

    return Center(
      child: InkWell(
        onTap: () {
          if (_selectedBlock != null) {
            setState(() {
              _selectedBlock = null;
            });
            _updateEditMode();
          }
          if (_selectedSlot != null) {
            setState(() {
              _previousSlot = _selectedSlot;
              _selectedSlot = null;
            });
            _selectionAnimationController.forward(from: 0);
          }
          onWeekHeaderTap?.call();
        },
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
                        // 点击空白处时，取消选中的课程块
                        if (_selectedBlock != null) {
                          setState(() {
                            _selectedBlock = null;
                          });
                          _updateEditMode();
                          return; // 如果取消了选中，不进行后续的加号显示
                        }

                        if (slot.section != null) {
                          final newSlot = (
                            weekday: weekdayIndexes[day],
                            section: slot.section!.index,
                          );
                          if (_selectedSlot == newSlot) {
                            setState(() {
                              _previousSlot = _selectedSlot;
                              _selectedSlot = null;
                            });
                            _selectionAnimationController.forward(from: 0);
                            return;
                          }
                          if (_selectedSlot != newSlot) {
                            setState(() {
                              _previousSlot = _selectedSlot;
                              _selectedSlot = newSlot;
                            });
                            _selectionAnimationController.forward(from: 0);
                          }
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
    return AnimatedBuilder(
      animation: _selectionAnimation,
      builder: (context, child) {
        final List<Widget> overlays = [];

        // 渐隐的前一个选择
        if (_previousSlot != null && _selectionAnimation.value < 1.0) {
          final int prevColumnIndex = weekdayIndexes.indexOf(
            _previousSlot!.weekday,
          );
          if (prevColumnIndex != -1) {
            final double prevTop =
                sectionOffsets[_previousSlot!.section] ?? 0.0;
            overlays.add(
              Positioned(
                left: prevColumnIndex * dayWidth,
                top: prevTop,
                width: dayWidth,
                height: sectionHeight,
                child: Opacity(
                  opacity: 1.0 - _selectionAnimation.value,
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
              ),
            );
          }
        }

        // 渐显的当前选择
        if (_selectedSlot != null) {
          final int columnIndex = weekdayIndexes.indexOf(
            _selectedSlot!.weekday,
          );
          if (columnIndex != -1) {
            final double top = sectionOffsets[_selectedSlot!.section] ?? 0.0;
            overlays.add(
              Positioned(
                left: columnIndex * dayWidth,
                top: top,
                width: dayWidth,
                height: sectionHeight,
                child: GestureDetector(
                  onTap: () {
                    if (onAddCourseTap != null) {
                      onAddCourseTap!(
                        _selectedSlot!.weekday,
                        _selectedSlot!.section,
                      );
                    }
                    setState(() {
                      _previousSlot = _selectedSlot;
                      _selectedSlot = null;
                    });
                    _selectionAnimationController.forward(from: 0);
                  },
                  child: Opacity(
                    opacity: _selectionAnimation.value,
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
                ),
              ),
            );
          }
        }

        return Stack(children: overlays);
      },
    );
  }

  /// 构建课程区块。
  Widget _buildCourseBlock(
    BuildContext context,
    _CourseBlock block,
    double dayWidth,
    Map<int, double> sectionOffsets,
    double viewportWidth,
    double tableHeight,
  ) {
    final bool isNonCurrent = block.isNonCurrent;
    final bool isDragging =
        _draggingBlock != null &&
        _draggingBlock!.course == block.course &&
        _draggingBlock!.session == block.session;

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

    final bool isSelected =
        _selectedBlock != null &&
        _selectedBlock!.course == block.course &&
        _selectedBlock!.session == block.session;

    // 构建调整手柄圆点
    Widget buildDotHandle(bool isTop) {
      return Positioned(
        top: isTop ? 0 : null,
        bottom: isTop ? null : 0,
        left: 0,
        right: 0,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            setState(() {
              _draggingBlock = block;
              _isResizing = true;
              _resizeStartGlobalY = details.globalPosition.dy;
              _dragTargetWeekday = block.session.weekday;
              _dragTargetSection = block.session.startSection;
              _dragTargetSectionCount = block.session.sectionCount;
              _hasConflict = false;
            });
            _updateEditMode();
          },
          onPanUpdate: (details) {
            if (_draggingBlock == null || !_isResizing) return;
            final double currentDy = details.globalPosition.dy;
            final double totalDelta = currentDy - _resizeStartGlobalY;
            _handleResizeUpdate(totalDelta, sectionOffsets, isTop);
          },
          onPanEnd: (details) {
            _handleResizeEnd();
          },
          child: Container(
            height: 36, // 进一步增加触摸区域
            color: Colors.transparent,
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final Widget cardContent = Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: gradientColors.first.withValues(alpha: 0.25),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
            // 1. 自适应课程名（标题）
            Flexible(
              fit: FlexFit.loose,
              child: Text(
                block.course.name,
                style: titleStyle.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.fade,
              ),
            ),
            // 2. 教室信息（独立一行，限制最大高度比例）
            if (block.session.location.isNotEmpty) ...[
              const SizedBox(height: 2),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: blockHeight * 0.3, // 最多占用 30% 高度
                ),
                child: Text(
                  '@${block.session.location}',
                  style: detailStyle.copyWith(fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 10, // 允许显示多行，由高度限制
                ),
              ),
            ],
            // 3. 教师/备注信息（独立一行，限制最大高度比例）
            if (block.course.teacher.isNotEmpty) ...[
              const SizedBox(height: 2),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: blockHeight * 0.2, // 最多占用 20% 高度
                ),
                child: Text(
                  block.course.teacher,
                  style: detailStyle.copyWith(fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    // 如果是选中状态，显示带手柄的卡片
    if (isSelected) {
      return Positioned(
        key: ValueKey(
          '${block.course.name}_${block.session.weekday}_${block.session.startSection}',
        ),
        left: block.columnIndex * dayWidth,
        top: startOffset - 10,
        width: dayWidth,
        height: blockHeight + 20,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 10,
              left: 0,
              right: 0,
              height: blockHeight,
              child: GestureDetector(
                onPanStart: (details) {
                  setState(() {
                    _draggingBlock = block;
                    _isResizing = false;
                    _initialDragOffset = details.localPosition;
                    _dragOffset = Offset(
                      block.columnIndex * dayWidth,
                      startOffset,
                    );
                    _dragTargetWeekday = block.session.weekday;
                    _dragTargetSection = block.session.startSection;
                    _dragTargetSectionCount = block.session.sectionCount;
                    _hasConflict = false;
                  });
                  _updateEditMode();
                },
                onPanUpdate: (details) {
                  if (_draggingBlock == null || _isResizing) return;
                  setState(() {
                    _dragOffset = Offset(
                      (block.columnIndex * dayWidth +
                              details.localPosition.dx -
                              _initialDragOffset.dx)
                          .clamp(0, viewportWidth - dayWidth),
                      (startOffset +
                              details.localPosition.dy -
                              _initialDragOffset.dy)
                          .clamp(0, tableHeight - blockHeight),
                    );

                    // 计算目标位置
                    final int targetColumn = (_dragOffset.dx / dayWidth)
                        .round()
                        .clamp(0, weekdayIndexes.length - 1);
                    _dragTargetWeekday = weekdayIndexes[targetColumn];

                    // 找到最近的节次
                    double minDistance = double.infinity;
                    int? closestSection;
                    for (final entry in sectionOffsets.entries) {
                      final distance = (_dragOffset.dy - entry.value).abs();
                      if (distance < minDistance) {
                        minDistance = distance;
                        closestSection = entry.key;
                      }
                    }

                    int targetStart =
                        closestSection ?? block.session.startSection;

                    // 限制课程不能跨越时段
                    final SectionTime startInfo = sections.firstWhere(
                      (SectionTime s) => s.index == targetStart,
                      orElse: () => sections.first,
                    );
                    final String segment = startInfo.segmentName;
                    final Iterable<SectionTime> segmentSections = sections
                        .where((SectionTime s) => s.segmentName == segment);

                    if (segmentSections.isNotEmpty) {
                      final int maxSegmentIndex = segmentSections
                          .map((SectionTime s) => s.index)
                          .reduce(math.max);
                      final int minSegmentIndex = segmentSections
                          .map((SectionTime s) => s.index)
                          .reduce(math.min);

                      final int sectionCount = block.session.sectionCount;

                      // 如果课程超出当前时段下界，向上回退
                      if (targetStart + sectionCount - 1 > maxSegmentIndex) {
                        targetStart = maxSegmentIndex - sectionCount + 1;
                      }

                      // 确保不超出上界
                      if (targetStart < minSegmentIndex) {
                        targetStart = minSegmentIndex;
                      }
                    }

                    _dragTargetSection = targetStart;

                    // 检查冲突
                    _hasConflict = _checkConflict(
                      _dragTargetWeekday!,
                      _dragTargetSection!,
                      block.session.sectionCount,
                      block.session,
                    );
                  });
                },
                onPanEnd: (details) {
                  if (_draggingBlock == null || _isResizing) return;
                  final draggedBlock = _draggingBlock!;
                  final targetWeekday = _dragTargetWeekday;
                  final targetSection = _dragTargetSection;
                  final hasConflict = _hasConflict;

                  setState(() {
                    _draggingBlock = null;
                    _dragOffset = Offset.zero;
                    _dragTargetWeekday = null;
                    _dragTargetSection = null;
                    _dragTargetSectionCount = null;
                    _hasConflict = false;
                  });
                  _updateEditMode();

                  if (hasConflict) return;

                  if (targetWeekday != null &&
                      targetSection != null &&
                      (targetWeekday != draggedBlock.session.weekday ||
                          targetSection != draggedBlock.session.startSection)) {
                    final result = _handleCourseMoved(
                      draggedBlock,
                      targetWeekday,
                      targetSection,
                      draggedBlock.session.sectionCount,
                    );
                    if (result != null) {
                      final (newCourse, newSession) = result;
                      setState(() {
                        _selectedBlock = _createUpdatedBlock(
                          newCourse,
                          newSession,
                        );
                      });
                    }
                  }
                },
                child: cardContent,
              ),
            ),
            buildDotHandle(true),
            buildDotHandle(false),
          ],
        ),
      );
    }

    // 非选中状态
    return Positioned(
      key: ValueKey(
        '${block.course.name}_${block.session.weekday}_${block.session.startSection}',
      ),
      left: block.columnIndex * dayWidth,
      top: startOffset,
      width: dayWidth,
      height: blockHeight,
      child: Opacity(
        opacity: isDragging ? 0.3 : 1.0,
        child: GestureDetector(
          onTap: () {
            if (_selectedBlock != null) {
              setState(() {
                _selectedBlock = null;
              });
              _updateEditMode();
            }
            if (_selectedSlot != null) {
              setState(() {
                _previousSlot = _selectedSlot;
                _selectedSlot = null;
              });
              _selectionAnimationController.forward(from: 0);
            }
            _showCourseDetails(context, block);
          },
          onLongPressStart: (details) {
            setState(() {
              _draggingBlock = block;
              _isResizing = false;
              _initialDragOffset = details.localPosition;
              _dragOffset = Offset(block.columnIndex * dayWidth, startOffset);
              _dragTargetWeekday = block.session.weekday;
              _dragTargetSection = block.session.startSection;
              _dragTargetSectionCount = block.session.sectionCount;
              _hasConflict = false;
              if (_selectedSlot != null) {
                _previousSlot = _selectedSlot;
                _selectedSlot = null;
                _selectionAnimationController.forward(from: 0);
              }
            });
            _updateEditMode();
          },
          onLongPressMoveUpdate: (details) {
            if (_draggingBlock == null) return;
            setState(() {
              final double newLeft =
                  block.columnIndex * dayWidth +
                  details.localPosition.dx -
                  _initialDragOffset.dx;
              final double newTop =
                  startOffset +
                  details.localPosition.dy -
                  _initialDragOffset.dy;

              _dragOffset = Offset(
                newLeft.clamp(0, viewportWidth - dayWidth),
                newTop.clamp(0, tableHeight - blockHeight),
              );

              // 计算目标位置
              final int targetColumn = (_dragOffset.dx / dayWidth)
                  .round()
                  .clamp(0, weekdayIndexes.length - 1);
              _dragTargetWeekday = weekdayIndexes[targetColumn];

              // 找到最近的节次
              double minDistance = double.infinity;
              int? closestSection;
              for (final entry in sectionOffsets.entries) {
                final distance = (_dragOffset.dy - entry.value).abs();
                if (distance < minDistance) {
                  minDistance = distance;
                  closestSection = entry.key;
                }
              }

              int targetStart = closestSection ?? block.session.startSection;

              // 限制课程不能跨越时段
              final SectionTime startInfo = sections.firstWhere(
                (SectionTime s) => s.index == targetStart,
                orElse: () => sections.first,
              );
              final String segment = startInfo.segmentName;
              final Iterable<SectionTime> segmentSections = sections.where(
                (SectionTime s) => s.segmentName == segment,
              );

              if (segmentSections.isNotEmpty) {
                final int maxSegmentIndex = segmentSections
                    .map((SectionTime s) => s.index)
                    .reduce(math.max);
                final int minSegmentIndex = segmentSections
                    .map((SectionTime s) => s.index)
                    .reduce(math.min);

                final int sectionCount = block.session.sectionCount;

                // 如果课程超出当前时段下界，向上回退
                if (targetStart + sectionCount - 1 > maxSegmentIndex) {
                  targetStart = maxSegmentIndex - sectionCount + 1;
                }

                // 确保不超出上界
                if (targetStart < minSegmentIndex) {
                  targetStart = minSegmentIndex;
                }
              }

              _dragTargetSection = targetStart;

              // 检查冲突
              _hasConflict = _checkConflict(
                _dragTargetWeekday!,
                _dragTargetSection!,
                block.session.sectionCount,
                block.session,
              );
            });
          },
          onLongPressEnd: (details) {
            if (_draggingBlock == null) return;
            final draggedBlock = _draggingBlock!;
            final targetWeekday = _dragTargetWeekday;
            final targetSection = _dragTargetSection;
            final hasConflict = _hasConflict;

            setState(() {
              _draggingBlock = null;
              _dragOffset = Offset.zero;
              _dragTargetWeekday = null;
              _dragTargetSection = null;
              _dragTargetSectionCount = null;
              _hasConflict = false;
              _selectedBlock = block;
            });
            _updateEditMode();

            if (hasConflict) return;

            if (targetWeekday != null &&
                targetSection != null &&
                (targetWeekday != draggedBlock.session.weekday ||
                    targetSection != draggedBlock.session.startSection)) {
              final result = _handleCourseMoved(
                draggedBlock,
                targetWeekday,
                targetSection,
                draggedBlock.session.sectionCount,
              );
              if (result != null) {
                final (newCourse, newSession) = result;
                setState(() {
                  _selectedBlock = _createUpdatedBlock(newCourse, newSession);
                });
              }
            }
          },
          child: cardContent,
        ),
      ),
    );
  }

  /// 处理调整大小的更新
  void _handleResizeUpdate(
    double totalDelta,
    Map<int, double> sectionOffsets,
    bool isTop,
  ) {
    if (_draggingBlock == null) return;

    final block = _draggingBlock!;
    // 使用原始 block 的数据作为基准
    final initialStart = block.session.startSection;
    final initialCount = block.session.sectionCount;
    final initialEnd = initialStart + initialCount - 1;

    // 计算每节课的平均高度用于估算
    final avgSectionHeight = sectionHeight;
    final sectionDelta = (totalDelta / avgSectionHeight).round();

    int newStart = initialStart;
    int newCount = initialCount;

    if (isTop) {
      // 从顶部调整：改变开始节次和节数
      newStart = (initialStart + sectionDelta).clamp(1, initialEnd);
      newCount = initialEnd - newStart + 1;
    } else {
      // 从底部调整：只改变节数
      final newEnd = (initialEnd + sectionDelta).clamp(
        initialStart,
        sections.length,
      );
      newCount = newEnd - initialStart + 1;
    }

    // 确保节数至少为1
    if (newCount < 1) return;

    // 检查冲突
    final hasConflict = _checkConflict(
      _dragTargetWeekday ?? block.session.weekday,
      newStart,
      newCount,
      block.session,
    );

    setState(() {
      _dragTargetSection = newStart;
      _dragTargetSectionCount = newCount;
      _hasConflict = hasConflict;
    });
  }

  /// 处理调整大小结束
  void _handleResizeEnd() {
    if (_draggingBlock == null) return;

    final block = _draggingBlock!;
    final targetSection = _dragTargetSection;
    final targetCount = _dragTargetSectionCount;
    final hasConflict = _hasConflict;

    setState(() {
      _draggingBlock = null;
      _isResizing = false;
      _dragOffset = Offset.zero;
      _dragTargetWeekday = null;
      _dragTargetSection = null;
      _dragTargetSectionCount = null;
      _hasConflict = false;
    });
    _updateEditMode();

    // 如果有冲突，不执行更新
    if (hasConflict) return;

    // 如果节次或节数发生变化，触发更新
    if (targetSection != null && targetCount != null) {
      // 1. 识别涉及的时间段并分组
      final originalSession = block.session;
      final originalStartInfo = sections.firstWhere(
        (s) => s.index == originalSession.startSection,
        orElse: () => sections.first,
      );
      final originalSegment = originalStartInfo.segmentName;

      final Map<String, List<int>> segmentGroups = {};
      for (int i = 0; i < targetCount; i++) {
        final int currentSec = targetSection + i;
        final info = sections.firstWhere(
          (s) => s.index == currentSec,
          orElse: () => sections.first,
        );
        segmentGroups.putIfAbsent(info.segmentName, () => []).add(currentSec);
      }

      final List<CourseSession> newSessions = [];
      CourseSession? updatedOriginalSession;

      // 2. 处理每个分组
      for (final entry in segmentGroups.entries) {
        final segmentName = entry.key;
        final indices = entry.value..sort();
        final start = indices.first;
        final count = indices.length;

        if (segmentName == originalSegment) {
          // 更新原始课程（无论长度如何都保留，除非被完全移出，但调整大小逻辑保证了锚点在原处）
          updatedOriginalSession = CourseSession(
            weekday: originalSession.weekday,
            startSection: start,
            sectionCount: count,
            location: originalSession.location,
            startWeek: originalSession.startWeek,
            endWeek: originalSession.endWeek,
            weekType: originalSession.weekType,
            customWeeks: originalSession.customWeeks,
          );
          newSessions.add(updatedOriginalSession);
        } else if (count >= 2) {
          // 只有当延伸超过2节及以上时，才创建新的课程时间
          newSessions.add(
            CourseSession(
              weekday: originalSession.weekday,
              startSection: start,
              sectionCount: count,
              location: originalSession.location,
              startWeek: originalSession.startWeek,
              endWeek: originalSession.endWeek,
              weekType: originalSession.weekType,
              customWeeks: originalSession.customWeeks,
            ),
          );
        }
      }

      // 3. 更新 Course 对象
      if (newSessions.isNotEmpty) {
        final List<CourseSession> updatedCourseSessions = List.of(
          block.course.sessions,
        );
        updatedCourseSessions.remove(originalSession);
        updatedCourseSessions.addAll(newSessions);

        final newCourse = Course(
          name: block.course.name,
          teacher: block.course.teacher,
          color: block.course.color,
          sessions: updatedCourseSessions,
        );

        widget.onCourseChanged?.call(block.course, newCourse);

        // 保持选中状态（选中原始课程对应的部分）
        if (updatedOriginalSession != null) {
          setState(() {
            _selectedBlock = _createUpdatedBlock(
              newCourse,
              updatedOriginalSession!,
            );
          });
        }
      }
    }
  }

  /// 检查是否有课程冲突
  bool _checkConflict(
    int weekday,
    int startSection,
    int sectionCount,
    CourseSession excludeSession,
  ) {
    final int endSection = startSection + sectionCount - 1;

    for (final course in courses) {
      for (final session in course.sessions) {
        // 跳过正在拖拽的课程本身
        if (session == excludeSession) continue;

        // 只检查同一天的课程
        if (session.weekday != weekday) continue;

        // 检查是否在当前周有课
        if (!session.occursInWeek(currentWeek)) continue;

        final int sessionEnd = session.startSection + session.sectionCount - 1;

        // 检查是否重叠
        if (startSection <= sessionEnd && endSection >= session.startSection) {
          return true;
        }
      }
    }
    return false;
  }

  /// 构建拖拽时的悬浮卡片
  Widget _buildDraggingOverlay(
    BuildContext context,
    double dayWidth,
    Map<int, double> sectionOffsets,
  ) {
    if (_draggingBlock == null) return const SizedBox.shrink();

    final block = _draggingBlock!;
    final bool isNonCurrent = block.isNonCurrent;

    // 使用目标节数计算高度
    final int targetStart = _dragTargetSection ?? block.session.startSection;
    final int targetCount =
        _dragTargetSectionCount ?? block.session.sectionCount;
    final int targetEnd = targetStart + targetCount - 1;

    final double targetStartOffset = sectionOffsets[targetStart] ?? 0.0;
    final double targetEndOffset =
        sectionOffsets[targetEnd] ?? targetStartOffset;
    final double targetHeight =
        targetEndOffset + sectionHeight - targetStartOffset;

    // 原始高度（用于拖拽模式）
    final double startOffset =
        sectionOffsets[block.session.startSection] ?? 0.0;
    final int endSectionIndex =
        block.session.startSection + block.session.sectionCount - 1;
    final double endOffset = sectionOffsets[endSectionIndex] ?? startOffset;
    final double blockHeight = endOffset + sectionHeight - startOffset;

    final List<Color> gradientColors = isNonCurrent
        ? <Color>[const Color(0xFFE0E0E0), const Color(0xFFF5F5F5)]
        : <Color>[
            block.course.color.withValues(alpha: 0.92),
            block.course.color.withValues(alpha: 0.78),
          ];

    // 冲突时使用红色边框
    final Color indicatorColor = _hasConflict
        ? Colors.red.withValues(alpha: 0.6)
        : Colors.blue.withValues(alpha: 0.6);
    final Color indicatorBgColor = _hasConflict
        ? Colors.red.withValues(alpha: 0.1)
        : Colors.blue.withValues(alpha: 0.1);

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

    // 目标位置指示器（调整大小模式时显示）
    Widget? targetIndicator;
    if (_isResizing &&
        _dragTargetWeekday != null &&
        _dragTargetSection != null) {
      final int targetColumn = weekdayIndexes.indexOf(_dragTargetWeekday!);
      if (targetColumn != -1) {
        targetIndicator = Positioned(
          left: targetColumn * dayWidth,
          top: targetStartOffset,
          width: dayWidth,
          height: targetHeight,
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: indicatorColor, width: 2),
              color: indicatorBgColor,
            ),
            child: _hasConflict
                ? Center(
                    child: Icon(
                      Icons.block,
                      color: Colors.red.withValues(alpha: 0.5),
                      size: 32,
                    ),
                  )
                : null,
          ),
        );
      }
    }

    // 拖拽模式时的目标位置指示器
    Widget? dragTargetIndicator;
    if (!_isResizing &&
        _dragTargetWeekday != null &&
        _dragTargetSection != null) {
      final int targetColumn = weekdayIndexes.indexOf(_dragTargetWeekday!);
      if (targetColumn != -1) {
        dragTargetIndicator = Positioned(
          left: targetColumn * dayWidth,
          top: targetStartOffset,
          width: dayWidth,
          height: targetHeight,
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: indicatorColor, width: 2),
              color: indicatorBgColor,
            ),
            child: _hasConflict
                ? Center(
                    child: Icon(
                      Icons.block,
                      color: Colors.red.withValues(alpha: 0.5),
                      size: 32,
                    ),
                  )
                : null,
          ),
        );
      }
    }

    // 构建调整手柄圆点
    Widget buildDotHandle(bool isTop) {
      return const SizedBox.shrink();
    }

    // 调整大小模式：只显示指示器
    if (_isResizing) {
      return Stack(children: [if (targetIndicator != null) targetIndicator]);
    }

    // 拖拽模式：显示悬浮卡片和手柄
    return Stack(
      children: [
        if (dragTargetIndicator != null) dragTargetIndicator,
        Positioned(
          left: _dragOffset.dx,
          top: _dragOffset.dy,
          width: dayWidth,
          height: blockHeight,
          child: Transform.scale(
            scale: 1.05,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        colors: gradientColors,
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      border: Border.all(color: Colors.white, width: 2), // 白色边框
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
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
                // 顶部圆点
                buildDotHandle(true),
                // 底部圆点
                buildDotHandle(false),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 处理课程位置移动
  (Course, CourseSession)? _handleCourseMoved(
    _CourseBlock block,
    int newWeekday,
    int newStartSection,
    int newSectionCount,
  ) {
    CourseSession? targetSession;
    // 创建新的 session 列表，更新被拖拽的 session
    final List<CourseSession> newSessions = block.course.sessions.map((s) {
      if (s == block.session) {
        targetSession = CourseSession(
          weekday: newWeekday,
          startSection: newStartSection,
          sectionCount: newSectionCount,
          location: s.location,
          startWeek: s.startWeek,
          endWeek: s.endWeek,
          weekType: s.weekType,
          customWeeks: s.customWeeks,
        );
        return targetSession!;
      }
      return s;
    }).toList();

    final Course newCourse = Course(
      name: block.course.name,
      teacher: block.course.teacher,
      color: block.course.color,
      sessions: newSessions,
    );

    widget.onCourseChanged?.call(block.course, newCourse);

    if (targetSession != null) {
      return (newCourse, targetSession!);
    }
    return null;
  }

  _CourseBlock _createUpdatedBlock(Course newCourse, CourseSession newSession) {
    final int columnIndex = weekdayIndexes.indexOf(newSession.weekday);

    final SectionTime startSection = sections.firstWhere(
      (SectionTime info) => info.index == newSession.startSection,
      orElse: () => sections.first,
    );
    final int endIndex = newSession.startSection + newSession.sectionCount - 1;
    final SectionTime endSection = sections.firstWhere(
      (SectionTime info) => info.index == endIndex,
      orElse: () => startSection,
    );

    final bool isCurrentWeek = newSession.occursInWeek(currentWeek);

    return _CourseBlock(
      course: newCourse,
      session: newSession,
      columnIndex: columnIndex,
      startTime: startSection.start,
      endTime: endSection.end,
      isNonCurrent: !isCurrentWeek,
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
      builder: (BuildContext context) => CourseDetailSheet(
        items: overlapping,
        allCourses: courses,
        maxWeek: widget.maxWeek,
      ),
    );

    if (result != null && result is Map) {
      final action = result['action'];

      if (action == 'create') {
        final newCourse = result['newCourse'] as Course;
        widget.onCourseAdded?.call(newCourse);
      } else {
        final target = result['target'] as Course;
        if (action == 'delete') {
          widget.onCourseDeleted?.call(target);
        } else if (action == 'update') {
          final newCourse = result['newCourse'] as Course;
          widget.onCourseChanged?.call(target, newCourse);
        }
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
      onTap: () {
        if (_selectedBlock != null) {
          setState(() {
            _selectedBlock = null;
          });
          _updateEditMode();
        }
        if (_selectedSlot != null) {
          setState(() {
            _previousSlot = _selectedSlot;
            _selectedSlot = null;
          });
          _selectionAnimationController.forward(from: 0);
        }
        onTimeColumnTap?.call();
      },
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
    return GestureDetector(
      onTap: () {
        if (_selectedBlock != null) {
          setState(() {
            _selectedBlock = null;
          });
          _updateEditMode();
        }
        if (_selectedSlot != null) {
          setState(() {
            _previousSlot = _selectedSlot;
            _selectedSlot = null;
          });
          _selectionAnimationController.forward(from: 0);
        }
      },
      behavior: HitTestBehavior.translucent,
      child: Container(
        height: slot.height,
        decoration: BoxDecoration(
          color: const Color(0xFFE8EBF3),
          border: Border(bottom: BorderSide(color: borderColor)),
        ),
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
