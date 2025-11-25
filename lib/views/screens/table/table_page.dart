import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';

import '../../../models/course.dart';
import '../../../models/course_schedule_config.dart';
import '../../../services/course_service.dart';
import 'widgets/course_schedule_table.dart';
import 'widgets/schedule_settings_sheet.dart';
import 'widgets/section_config_sheet.dart';
import 'widgets/week_select_sheet.dart';

/// 展示并管理大学课程表的页面。
class TablePage extends StatefulWidget {
  const TablePage({super.key});

  /// 创建页面状态以渲染课表内容。
  @override
  State<TablePage> createState() => _TablePageState();
}

class _TablePageState extends State<TablePage> {
  static final DateTime _defaultSemesterStart = DateTime(2025, 9, 1); // 默认周一
  static const List<String> _weekdayLabels = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  List<Course> _courses = [];
  late List<SectionTime> _sections;
  late CourseScheduleConfig _scheduleConfig;
  late final PageController _pageController;
  late final LinkedScrollControllerGroup _scrollGroup;
  late final ScrollController _timeColumnController;
  final Map<int, ScrollController> _weekScrollControllers =
      <int, ScrollController>{};
  int _currentWeek = 1;
  int _maxWeek = 20;
  DateTime _currentSemesterStart = _defaultSemesterStart;

  // 设置状态
  String _tableName = '我的课表';
  bool _showWeekend = false;
  bool _showNonCurrentWeek = true;
  bool _isLoading = true;

  List<int> get _visibleWeekdays =>
      _showWeekend ? <int>[1, 2, 3, 4, 5, 6, 7] : <int>[1, 2, 3, 4, 5];

  /// 初始化状态并载入课程数据。
  @override
  void initState() {
    super.initState();
    _scheduleConfig = CourseScheduleConfig.njuDefaults();
    _sections = _scheduleConfig.generateSections();
    _pageController = PageController(initialPage: 0);
    _scrollGroup = LinkedScrollControllerGroup();
    _timeColumnController = _scrollGroup.addAndGet();
    _loadData();
  }

  Future<void> _loadData() async {
    final service = CourseService.instance;
    final courses = await service.loadCourses();
    final config = await service.loadConfig();
    final semesterStart = await service.loadSemesterStart();
    final maxWeek = await service.loadMaxWeek();
    final tableName = await service.loadTableName();
    final showWeekend = await service.loadShowWeekend();
    final showNonCurrentWeek = await service.loadShowNonCurrentWeek();

    if (!mounted) return;

    setState(() {
      _courses = courses;
      _scheduleConfig = config;
      _sections = _scheduleConfig.generateSections();
      _currentSemesterStart = semesterStart ?? _defaultSemesterStart;
      _maxWeek = maxWeek;
      _tableName = tableName;
      _showWeekend = showWeekend;
      _showNonCurrentWeek = showNonCurrentWeek;

      // 计算当前周
      final int diffDays = DateTime.now()
          .difference(_currentSemesterStart)
          .inDays;
      _currentWeek = (diffDays / 7).floor() + 1;
      if (_currentWeek < 1) _currentWeek = 1;
      if (_currentWeek > _maxWeek) _currentWeek = _maxWeek;

      _isLoading = false;
    });

    // 跳转到当前周
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentWeek - 1);
      }
    });
  }

  @override
  void dispose() {
    _timeColumnController.dispose();
    for (final ScrollController controller in _weekScrollControllers.values) {
      controller.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  /// 构建课表页面主体。
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF7F8FC),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildToolbar(context),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildPagedTable(context)),
          ],
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
              Text(_tableName, style: titleStyle),
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
          tooltip: '课程表设置',
          onPressed: () => _openScheduleSettings(),
        ),
      ],
    );
  }

  /// 格式化学期日期范围便于展示。
  String _formatSemesterRange() {
    final int startYear = _currentSemesterStart.year;
    final DateTime endDate = _currentSemesterStart.add(
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
    final DateTime initialDate = _currentSemesterStart.add(
      Duration(days: (_currentWeek - 1) * 7),
    );
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: _currentSemesterStart,
      lastDate: _currentSemesterStart.add(
        Duration(days: (_maxWeek - 1) * 7 + 6),
      ),
      helpText: '选择要跳转的日期',
    );
    if (picked == null) {
      return;
    }
    final int days = picked.difference(_currentSemesterStart).inDays;
    final int computedWeek = (days ~/ 7) + 1;
    if (computedWeek >= 1 && computedWeek <= _maxWeek) {
      _updateWeek(computedWeek);
    }
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
      await CourseService.instance.saveConfig(result);
      setState(() {
        _scheduleConfig = result;
        _sections = _scheduleConfig.generateSections();
      });
    }
  }

  /// 计算给定周次对应的完整日期列表。
  List<DateTime> _resolveWeekDates(int week) {
    final DateTime start = _currentSemesterStart.add(
      Duration(days: (week - 1) * 7),
    );
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

  /// 打开周次选择弹窗。
  void _openWeekSelectSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return WeekSelectSheet(
          currentWeek:
              DateTime.now().difference(_currentSemesterStart).inDays ~/ 7 +
              1, // 近似计算当前周
          selectedWeek: _currentWeek,
          maxWeek: _maxWeek,
          onWeekSelected: _updateWeek,
        );
      },
    );
  }

  /// 打开课程表设置页面。
  void _openScheduleSettings() {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (BuildContext context) {
          return ScheduleSettingsPage(
            scheduleConfig: _scheduleConfig,
            semesterStart: _currentSemesterStart,
            currentWeek: _currentWeek,
            maxWeek: _maxWeek,
            tableName: _tableName,
            showWeekend: _showWeekend,
            showNonCurrentWeek: _showNonCurrentWeek,
            onConfigChanged: (CourseScheduleConfig config) async {
              await CourseService.instance.saveConfig(config);
              setState(() {
                _scheduleConfig = config;
                _sections = _scheduleConfig.generateSections();
              });
            },
            onSemesterStartChanged: (DateTime date) async {
              await CourseService.instance.saveSemesterStart(date);
              setState(() {
                _currentSemesterStart = date;
              });
            },
            onCurrentWeekChanged: (int week) {
              _updateWeek(week);
            },
            onMaxWeekChanged: (int max) async {
              await CourseService.instance.saveMaxWeek(max);
              setState(() {
                _maxWeek = max;
              });
            },
            onTableNameChanged: (String name) async {
              await CourseService.instance.saveTableName(name);
              setState(() {
                _tableName = name;
              });
            },
            onShowWeekendChanged: (bool show) async {
              await CourseService.instance.saveShowWeekend(show);
              setState(() {
                _showWeekend = show;
              });
            },
            onShowNonCurrentWeekChanged: (bool show) async {
              await CourseService.instance.saveShowNonCurrentWeek(show);
              setState(() {
                _showNonCurrentWeek = show;
              });
            },
            onOpenSectionSettings: () {
              _openSectionSheet();
            },
          );
        },
      ),
    );
  }

  /// 构建带有固定左列的分页课表视图。
  Widget _buildPagedTable(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 计算时间列宽度：
        // 1. 保持与周末有课模式（7天）下的列宽一致
        // 2. 布局结构为：时间列 + 7个课程列
        // 3. 因此总宽度 = 8 * 列宽
        final double timeColumnWidth = constraints.maxWidth / 8;

        return Row(
          children: <Widget>[
            SizedBox(
              width: timeColumnWidth,
              child: CourseScheduleTable(
                courses: const <Course>[],
                currentWeek: _currentWeek,
                sections: _sections,
                weekdays: const <String>[],
                weekdayIndexes: const <int>[],
                maxWeek: _maxWeek,
                onWeekChanged: _updateWeek,
                onWeekHeaderTap: _openWeekSelectSheet,
                onTimeColumnTap: () => _openSectionSheet(),
                includeTimeColumn: true,
                applySurface: false,
                timeColumnWidth: timeColumnWidth,
                scrollController: _timeColumnController,
              ),
            ),
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
                    includeTimeColumn: false,
                    timeColumnWidth: timeColumnWidth,
                    leadingInset: 0,
                    scrollController: _scrollControllerForWeek(index),
                    showNonCurrentWeek: _showNonCurrentWeek,
                    applySurface: false,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// 获取指定周次对应的垂直滚动控制器。
  ScrollController _scrollControllerForWeek(int index) {
    return _weekScrollControllers.putIfAbsent(
      index,
      () => _scrollGroup.addAndGet(),
    );
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
