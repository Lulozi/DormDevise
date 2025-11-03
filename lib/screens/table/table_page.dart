import 'package:flutter/material.dart';

import '../../models/course.dart';
import '../../models/course_schedule_config.dart';
import 'widgets/course_schedule_table.dart';
import 'widgets/section_config_sheet.dart';

/// 展示并管理大学课程表的页面。
class TablePage extends StatefulWidget {
  const TablePage({super.key});

  /// 创建页面状态以渲染课表内容。
  @override
  State<TablePage> createState() => _TablePageState();
}

class _TablePageState extends State<TablePage> {
  static const int _maxWeek = 18;
  static final DateTime _semesterStart = DateTime(2025, 9, 6);
  static const List<String> _weekdayLabels = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];
  static const List<int> _visibleWeekdays = <int>[1, 2, 3, 4, 5];

  late final List<Course> _courses;
  late List<SectionTime> _sections;
  late CourseScheduleConfig _scheduleConfig;
  late final PageController _pageController;
  int _currentWeek = 1;

  /// 初始化状态并载入课程数据。
  @override
  void initState() {
    super.initState();
    _courses = _loadCourses();
    _scheduleConfig = _buildScheduleConfig();
    _sections = _scheduleConfig.generateSections();
    _pageController = PageController(initialPage: _currentWeek - 1);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 构建课表页面主体。
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 12),
              _buildToolbar(context),
              const SizedBox(height: 16),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _maxWeek,
                  onPageChanged: (int index) {
                    setState(() {
                      _currentWeek = index + 1;
                    });
                  },
                  itemBuilder: (BuildContext context, int index) {
                    final int targetWeek = index + 1;
                    final List<DateTime> targetDates = _resolveWeekDates(
                      targetWeek,
                    );
                    return CourseScheduleTable(
                      courses: _courses,
                      currentWeek: targetWeek,
                      sections: _sections,
                      weekdays: _visibleWeekdays
                          .map((int day) => _weekdayLabels[day - 1])
                          .toList(),
                      weekdayIndexes: _visibleWeekdays,
                      weekDates: _visibleWeekdays
                          .map((int day) => targetDates[day - 1])
                          .toList(),
                      maxWeek: _maxWeek,
                      onWeekChanged: _updateWeek,
                      onSectionTap: _handleSectionTap,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建顶部工具栏，包含返回与菜单操作。
  Widget _buildToolbar(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle titleStyle = theme.textTheme.headlineSmall!.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 0.4,
    );
    final TextStyle subtitleStyle = theme.textTheme.bodySmall!.copyWith(
      color: Colors.black54,
      letterSpacing: 0.2,
    );

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('我的课表', style: titleStyle),
              const SizedBox(height: 4),
              Text(
                '第 $_currentWeek 周 | ${_formatSemesterRange()}',
                style: subtitleStyle,
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _ToolbarIconButton(
          icon: Icons.calendar_today_outlined,
          tooltip: '跳转日期',
          onPressed: () => _pickDate(context),
        ),
        const SizedBox(width: 10),
        _ToolbarIconButton(
          icon: Icons.settings_outlined,
          tooltip: '节次设置',
          onPressed: () => _openSectionSheet(),
        ),
      ],
    );
  }

  /// 格式化学期日期范围便于展示。
  String _formatSemesterRange() {
    final int startYear = _semesterStart.year;
    final DateTime endDate = _semesterStart.add(
      Duration(days: (_maxWeek - 1) * 7),
    );
    final int endYear = endDate.year;
    if (startYear == endYear) {
      return '$startYear 学年';
    }
    return '$startYear-$endYear 学年';
  }

  /// 打开日期选择器并跳转到对应周次。
  Future<void> _pickDate(BuildContext context) async {
    final DateTime initialDate = _semesterStart.add(
      Duration(days: (_currentWeek - 1) * 7),
    );
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: _semesterStart,
      lastDate: _semesterStart.add(Duration(days: (_maxWeek - 1) * 7 + 6)),
      helpText: '选择要跳转的日期',
    );
    if (picked == null) {
      return;
    }
    final int days = picked.difference(_semesterStart).inDays;
    final int computedWeek = (days ~/ 7) + 1;
    if (computedWeek >= 1 && computedWeek <= _maxWeek) {
      _updateWeek(computedWeek);
    }
  }

  /// 构建课节配置，支持全局与分时段自定义。
  CourseScheduleConfig _buildScheduleConfig() {
    return CourseScheduleConfig(
      defaultClassDuration: const Duration(minutes: 45),
      defaultBreakDuration: const Duration(minutes: 10),
      segments: <ScheduleSegmentConfig>[
        ScheduleSegmentConfig(
          name: '上午',
          startTime: TimeOfDay(hour: 8, minute: 0),
          classCount: 4,
          perClassDurations: <Duration>[
            Duration(minutes: 45),
            Duration(minutes: 45),
            Duration(minutes: 45),
            Duration(minutes: 45),
          ],
          perBreakDurations: <Duration>[
            Duration(minutes: 10),
            Duration(minutes: 10),
            Duration(minutes: 15),
          ],
        ),
        ScheduleSegmentConfig(
          name: '下午',
          startTime: TimeOfDay(hour: 13, minute: 30),
          classCount: 4,
          perClassDurations: <Duration>[
            Duration(minutes: 45),
            Duration(minutes: 45),
            Duration(minutes: 45),
            Duration(minutes: 45),
          ],
          perBreakDurations: <Duration>[
            Duration(minutes: 10),
            Duration(minutes: 10),
            Duration(minutes: 10),
          ],
        ),
        ScheduleSegmentConfig(
          name: '晚上',
          startTime: TimeOfDay(hour: 18, minute: 30),
          classCount: 3,
          perClassDurations: <Duration>[
            Duration(minutes: 50),
            Duration(minutes: 50),
            Duration(minutes: 45),
          ],
          perBreakDurations: <Duration>[
            Duration(minutes: 10),
            Duration(minutes: 10),
          ],
        ),
      ],
      useSegmentBreakDurations: false,
    );
  }

  /// 响应节次点击，弹出配置编辑弹窗。
  Future<void> _handleSectionTap(SectionTime section) async {
    final int segmentIndex = _scheduleConfig.segmentIndexForSection(
      section.index,
    );
    if (segmentIndex < 0) {
      return;
    }
    await _openSectionSheet(initialSectionIndex: section.index);
  }

  /// 打开节次配置弹窗，可选聚焦到指定节次。
  Future<void> _openSectionSheet({int? initialSectionIndex}) async {
    final CourseScheduleConfig? result =
        await showModalBottomSheet<CourseScheduleConfig>(
          context: context,
          isScrollControlled: true,
          builder: (BuildContext context) {
            return SectionConfigSheet(
              scheduleConfig: _scheduleConfig,
              initialSectionIndex: initialSectionIndex,
              onSubmit: (CourseScheduleConfig updated) {
                Navigator.of(context).pop(updated);
              },
            );
          },
        );
    if (result != null) {
      setState(() {
        _scheduleConfig = result;
        _sections = _scheduleConfig.generateSections();
      });
    }
  }

  /// 计算给定周次对应的完整日期列表。
  List<DateTime> _resolveWeekDates(int week) {
    final DateTime start = _semesterStart.add(Duration(days: (week - 1) * 7));
    return List<DateTime>.generate(_weekdayLabels.length, (int index) {
      return start.add(Duration(days: index));
    });
  }

  /// 更新当前周次并触发界面刷新。
  void _updateWeek(int newWeek) {
    if (newWeek == _currentWeek || newWeek < 1 || newWeek > _maxWeek) {
      return;
    }
    setState(() {
      _currentWeek = newWeek;
    });
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        newWeek - 1,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// 加载课程数据，后续接入真实数据源。
  List<Course> _loadCourses() {
    return <Course>[];
  }
}

/// 顶部工具栏中使用的圆角图标按钮。
class _ToolbarIconButton extends StatelessWidget {
  /// 按钮展示的图标。
  final IconData icon;

  /// 长按时显示的提示文字。
  final String tooltip;

  /// 按钮点击回调。
  final VoidCallback? onPressed;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  /// 渲染带阴影的圆角图标按钮。
  @override
  Widget build(BuildContext context) {
    final bool isEnabled = onPressed != null;
    final Color iconColor = isEnabled ? Colors.black87 : Colors.black26;

    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, color: iconColor, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}
