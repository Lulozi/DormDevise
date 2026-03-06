import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:dormdevise/utils/app_toast.dart';
import '../../../services/theme/theme_service.dart';

import '../../../models/course.dart';
import '../../../models/course_schedule_config.dart';
import '../../../services/course_service.dart';
import '../../widgets/bubble_popup.dart';
import 'widgets/course_schedule_table.dart';
import 'widgets/section_config_sheet.dart';
import 'widgets/week_select_sheet.dart';
import 'course_edit_page.dart';
import 'all_schedules_page.dart';
import 'camera_import_schedule_page.dart';
import 'file_import_schedule_page.dart';
import 'scan_import_schedule_page.dart';
import 'schedule_share.dart';
import 'web_import_schedule_page.dart';

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

  // 返回学期第一周的起始日期（本周的星期一）
  DateTime get _firstWeekStart {
    // DateTime.weekday：周一 = 1，周日 = 7
    return _currentSemesterStart.subtract(
      Duration(days: _currentSemesterStart.weekday - 1),
    );
  }

  // 设置状态
  String _tableName = '我的课表';
  bool _showWeekend = false;
  bool _showNonCurrentWeek = true;
  bool _isLoading = true;
  bool _isEditing = false;
  Object _editModeResetToken = Object();
  DateTime? _highlightDate;

  final GlobalKey _importBtnKey = GlobalKey();
  final GlobalKey _shareBtnKey = GlobalKey();
  BubblePopupController? _toolbarBubbleController;
  bool _isToolbarBubbleOpen = false;

  List<int> get _visibleWeekdays =>
      _showWeekend ? <int>[1, 2, 3, 4, 5, 6, 7] : <int>[1, 2, 3, 4, 5];

  void _exitEditMode() {
    setState(() {
      _editModeResetToken = Object();
      _isEditing = false;
    });
  }

  /// 关闭工具栏气泡（若存在）。
  Future<void> _dismissToolbarBubble() async {
    if (!_isToolbarBubbleOpen) return;
    await _toolbarBubbleController?.dismiss();
    if (!mounted) return;
    setState(() {
      _isToolbarBubbleOpen = false;
      _toolbarBubbleController = null;
    });
  }

  /// 导入菜单条目构造器，重用 AllSchedulesPage 中的样式。
  Widget _buildImportMenuItem(
    String value,
    String text,
    IconData icon,
    BubblePopupController controller,
  ) {
    return InkWell(
      onTap: () async {
        await controller.dismiss();
        if (!mounted) return;
        // 每种导入方式独立成页，后续方便分别扩展。
        final Widget page = switch (value) {
          'web' => const WebImportSchedulePage(),
          'camera' => const CameraImportSchedulePage(),
          'scan' => const ScanImportSchedulePage(),
          'file' => const FileImportSchedulePage(),
          _ => const WebImportSchedulePage(),
        };
        final bool? result = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(builder: (BuildContext context) => page),
        );
        // 课表创建成功后刷新课表数据
        if (result == true && mounted) {
          _loadData();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (value != 'web') const SizedBox(width: 2),
            Icon(
              icon,
              size: value == 'web' ? 24 : 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示分享菜单
  Future<void> _showShareMenu() async {
    await _dismissToolbarBubble();
    if (!mounted) return;

    final BubblePopupController controller = BubblePopupController();
    setState(() {
      _toolbarBubbleController = controller;
      _isToolbarBubbleOpen = true;
    });

    await ScheduleShare.show(
      context: context,
      anchorKey: _shareBtnKey,
      controller: controller,
      tableName: _tableName,
      semesterRange: _formatSemesterRange(),
      currentWeek: _currentWeek,
    );

    if (!mounted) return;
    if (identical(_toolbarBubbleController, controller)) {
      setState(() {
        _toolbarBubbleController = null;
        _isToolbarBubbleOpen = false;
      });
    }
  }

  /// 显示导入方法菜单，去掉手动选项。
  Future<void> _showImportMenu() async {
    await _dismissToolbarBubble();
    if (!mounted) return;

    final controller = BubblePopupController();
    if (mounted) {
      setState(() {
        _toolbarBubbleController = controller;
        _isToolbarBubbleOpen = true;
      });
    }

    await showBubblePopup(
      context: context,
      anchorKey: _importBtnKey,
      controller: controller,
      content: SizedBox(
        width: 160,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildImportMenuItem('web', '网页导入课表', Icons.language, controller),
            const Divider(height: 1, thickness: 0.5),
            _buildImportMenuItem(
              'camera',
              '拍照导入课表',
              FontAwesomeIcons.camera,
              controller,
            ),
            const Divider(height: 1, thickness: 0.5),
            _buildImportMenuItem(
              'scan',
              '扫码导入课表',
              FontAwesomeIcons.qrcode,
              controller,
            ),
            const Divider(height: 1, thickness: 0.5),
            _buildImportMenuItem(
              'file',
              '文件导入课表',
              FontAwesomeIcons.folderOpen,
              controller,
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;
    if (identical(_toolbarBubbleController, controller)) {
      setState(() {
        _toolbarBubbleController = null;
        _isToolbarBubbleOpen = false;
      });
    }
  }

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
      final int diffDays = DateTime.now().difference(_firstWeekStart).inDays;
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
    _toolbarBubbleController?.dismiss();
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
      return PopScope(
        canPop: !_isToolbarBubbleOpen,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _dismissToolbarBubble();
        },
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return PopScope(
      canPop: !_isToolbarBubbleOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _dismissToolbarBubble();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
      ),
    );
  }

  /// 构建顶部工具栏，包含返回与菜单操作。
  Widget _buildToolbar(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final TextStyle titleStyle = theme.textTheme.headlineSmall!.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 0.4,
    );
    final TextStyle subtitleStyle = theme.textTheme.bodySmall!.copyWith(
      color: colorScheme.onSurfaceVariant,
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
              Text(_formatSemesterRange(), style: subtitleStyle),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _ToolbarIconButton(
          key: _importBtnKey,
          icon: FontAwesomeIcons.calendarPlus,
          tooltip: '导入课表',
          onPressed: () async {
            _exitEditMode();
            await _showImportMenu();
          },
          useFaIcon: true,
          iconSize: 18,
        ),
        const SizedBox(width: 8),
        _ToolbarIconButton(
          key: _shareBtnKey,
          icon: FontAwesomeIcons.shareFromSquare,
          tooltip: '分享课表',
          onPressed: () async {
            _exitEditMode();
            await _showShareMenu();
          },
          useFaIcon: true,
          iconSize: 18,
        ),
        const SizedBox(width: 8),
        _ToolbarIconButton(
          icon: FontAwesomeIcons.listUl,
          tooltip: '课程表设置',
          onPressed: () {
            _exitEditMode();
            _openScheduleSettings();
          },
          useFaIcon: true,
          iconSize: 18,
        ),
      ],
    );
  }

  /// 格式化学期日期范围便于展示，含学期序号。
  String _formatSemesterRange() {
    final int year = _currentSemesterStart.year;
    final int month = _currentSemesterStart.month;
    // 一般高校秋季学期从8-9月开始，属于当前年份至下一年份的学年
    // 春季学期从2-3月开始，属于上一年份至当前年份的学年
    if (month >= 8) {
      return '$year-${year + 1} 学年 第 1 学期';
    } else {
      return '${year - 1}-$year 学年 第 2 学期';
    }
  }

  /// 打开日期选择器并跳转到对应周次。
  Future<void> _pickDate(BuildContext context) async {
    final DateTime initialDate = _firstWeekStart.add(
      Duration(days: (_currentWeek - 1) * 7),
    );
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool isWhite = ThemeService.instance.isWhiteMode;
    final bool isDark = theme.brightness == Brightness.dark;
    // 选中色与开关预览保持一致：洁白/乌黑用 grey.shade700，彩色用 primary
    final Color pickerPrimary = isWhite
        ? Colors.grey.shade700
        : colorScheme.primary;
    // 乌黑模式下选中日期圆圈为白色，其上文字应为黑色
    final Color pickerOnPrimary = (isDark && isWhite)
        ? Colors.black
        : Colors.white;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: _firstWeekStart,
      lastDate: _firstWeekStart.add(Duration(days: (_maxWeek - 1) * 7 + 6)),
      helpText: '选择要跳转的日期',
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: theme.copyWith(
            colorScheme: colorScheme.copyWith(
              surface: colorScheme.surface,
              onSurface: colorScheme.onSurface,
              primary: pickerPrimary,
              onPrimary: pickerOnPrimary,
              secondaryContainer: pickerPrimary.withValues(alpha: 0.15),
              onSecondaryContainer: pickerPrimary,
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: colorScheme.surface,
              surfaceTintColor: Colors.transparent,
              headerBackgroundColor: colorScheme.surfaceContainerLow,
              headerForegroundColor: colorScheme.onSurface,
              dividerColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              headerHeadlineStyle: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
                letterSpacing: -0.5,
              ),
              headerHelpStyle: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
              weekdayStyle: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              dayStyle: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              yearStyle: TextStyle(color: colorScheme.onSurface),
              todayBorder: BorderSide(color: pickerPrimary, width: 1.5),
              todayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  // 深色模式下选中文字采用黑色
                  return isDark ? Colors.black : pickerOnPrimary;
                }
                return pickerPrimary;
              }),
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return isDark ? Colors.black : pickerOnPrimary;
                }
                return colorScheme.onSurface;
              }),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.primary,
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) {
      return;
    }
    final int days = picked.difference(_firstWeekStart).inDays;
    final int computedWeek = (days ~/ 7) + 1;
    if (computedWeek >= 1 && computedWeek <= _maxWeek) {
      setState(() {
        _highlightDate = picked;
      });
      _updateWeek(computedWeek);

      // 2秒后清除高亮状态
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && _highlightDate == picked) {
          setState(() {
            _highlightDate = null;
          });
        }
      });
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
    final DateTime start = _firstWeekStart.add(Duration(days: (week - 1) * 7));
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
              DateTime.now().difference(_firstWeekStart).inDays ~/ 7 +
              1, // 近似计算当前周
          selectedWeek: _currentWeek,
          maxWeek: _maxWeek,
          onWeekSelected: _updateWeek,
        );
      },
    );
  }

  Future<void> _handleCourseAdded(Course newCourse) async {
    setState(() {
      // 查找是否存在同名课程
      final int existingIndex = _courses.indexWhere(
        (c) => c.name == newCourse.name,
      );

      if (existingIndex != -1) {
        final Course existingCourse = _courses[existingIndex];

        // 只有当颜色和教师信息都一致时才合并，否则视为不同课程（即使同名）
        final bool isSameColor =
            existingCourse.color.toARGB32() == newCourse.color.toARGB32();
        final bool isSameTeacher = existingCourse.teacher == newCourse.teacher;

        if (isSameColor && isSameTeacher) {
          // 如果存在且信息一致，合并课程时间
          final List<CourseSession> mergedSessions = [
            ...existingCourse.sessions,
            ...newCourse.sessions,
          ];

          // 创建更新后的课程对象
          final Course updatedCourse = Course(
            name: existingCourse.name,
            teacher: existingCourse.teacher,
            color: existingCourse.color,
            sessions: mergedSessions,
          );

          _courses[existingIndex] = updatedCourse;

          AppToast.show(context, '已合并到现有课程 "${newCourse.name}"');
        } else {
          // 信息不一致，作为新课程添加
          _courses.add(newCourse);
        }
      } else {
        _courses.add(newCourse);
      }
    });
    await CourseService.instance.saveCourses(_courses);
  }

  /// 添加新课程。
  Future<void> _addCourse({int? weekday, int? section}) async {
    final Course? newCourse = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CourseEditPage(
          initialWeekday: weekday,
          initialSection: section,
          maxWeek: _maxWeek,
          existingCourses: _courses,
        ),
      ),
    );
    if (newCourse != null) {
      await _handleCourseAdded(newCourse);
    }
  }

  /// 打开课程表设置页面。
  Future<void> _openScheduleSettings() async {
    final result = await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (BuildContext context) {
          return AllSchedulesPage(
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
                // 更新当前周，基于新的第一周起始日期
                final int diffDays = DateTime.now()
                    .difference(_firstWeekStart)
                    .inDays;
                int newCurrent = (diffDays / 7).floor() + 1;
                if (newCurrent < 1) newCurrent = 1;
                if (newCurrent > _maxWeek) newCurrent = _maxWeek;
                _currentWeek = newCurrent;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_pageController.hasClients) {
                  _pageController.animateToPage(
                    _currentWeek - 1,
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                  );
                }
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
    if (result == true) {
      _loadData();
    } else {
      // 即使没有返回 true，也重新加载数据，以防是从创建页面直接返回（popUntil）
      // 或者在设置页面切换了课表但没有通过正常返回传递结果
      _loadData();
    }
  }

  /// 构建带有固定左列的分页课表视图。
  Widget _buildPagedTable(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 计算时间列宽度：
        // 紧凑布局，时间列尽量窄以留更多空间给课程卡片
        final double timeColumnWidth = constraints.maxWidth / 9.5;

        // 计算课程区域的列宽
        final double gridWidth = constraints.maxWidth - timeColumnWidth;
        final double dayWidth = gridWidth / _visibleWeekdays.length;

        // 统一计算节高：基于字号和课程内容动态决定，
        // 保证左侧时间列和右侧课程表使用相同节高。
        final double effectiveSectionHeight =
            CourseScheduleTable.resolveEffectiveSectionHeight(
          context: context,
          dayWidth: dayWidth,
          courses: _courses,
          sections: _sections,
          currentWeek: _currentWeek,
          showNonCurrentWeek: _showNonCurrentWeek,
          weekdayIndexes: _visibleWeekdays,
          maxWeek: _maxWeek,
          adaptiveDayCount: _visibleWeekdays.length,
        );

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
                adaptiveDayCount: _visibleWeekdays.length,
                sectionHeight: effectiveSectionHeight,
                maxWeek: _maxWeek,
                onWeekChanged: _updateWeek,
                onWeekHeaderTap: () {
                  _exitEditMode();
                  _openWeekSelectSheet();
                },
                onTimeColumnTap: () {
                  _exitEditMode();
                  _openSectionSheet();
                },
                includeTimeColumn: true,
                applySurface: false,
                timeColumnWidth: timeColumnWidth,
                scrollController: _timeColumnController,
                editModeResetToken: _editModeResetToken,
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                // 周视图按页裁剪，避免跨页溢出的角标在滑动时被相邻页覆盖
                clipBehavior: Clip.hardEdge,
                physics: _isEditing
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
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
                    adaptiveDayCount: _visibleWeekdays.length,
                    sectionHeight: effectiveSectionHeight,
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
                    onHeaderDateTap: () {
                      _exitEditMode();
                      _pickDate(context);
                    },
                    highlightDate: _highlightDate,
                    includeTimeColumn: false,
                    timeColumnWidth: timeColumnWidth,
                    leadingInset: 0,
                    scrollController: _scrollControllerForWeek(index),
                    showNonCurrentWeek: _showNonCurrentWeek,
                    applySurface: false,
                    editModeResetToken: _editModeResetToken,
                    onEditModeChanged: (isEditing) {
                      if (_isEditing != isEditing) {
                        setState(() {
                          _isEditing = isEditing;
                        });
                      }
                    },
                    onAddCourseTap: (weekday, section) =>
                        _addCourse(weekday: weekday, section: section),
                    onCourseChanged: (oldCourse, newCourse) async {
                      setState(() {
                        final index = _courses.indexOf(oldCourse);
                        if (index != -1) {
                          _courses[index] = newCourse;
                        }
                      });
                      await CourseService.instance.saveCourses(_courses);
                    },
                    onCourseDeleted: (course) async {
                      setState(() {
                        _courses.remove(course);
                      });
                      await CourseService.instance.saveCourses(_courses);
                    },
                    onCourseAdded: _handleCourseAdded,
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

  /// 是否使用 FontAwesome 图标。
  final bool useFaIcon;

  /// 图标大小。
  final double? iconSize;

  const _ToolbarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.useFaIcon = false,
    this.iconSize,
  });

  /// 渲染带阴影的圆角图标按钮。
  @override
  Widget build(BuildContext context) {
    final bool isEnabled = onPressed != null;
    final colorScheme = Theme.of(context).colorScheme;
    final Color iconColor = isEnabled
        ? colorScheme.primary
        : colorScheme.onSurface.withValues(alpha: 0.26);
    final double size = iconSize ?? (useFaIcon ? 20 : 24);

    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? colorScheme.surface,
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
              child: Center(
                child: useFaIcon
                    ? FaIcon(icon, color: iconColor, size: size)
                    : Icon(icon, color: iconColor, size: size),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
