import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:dormdevise/utils/app_toast.dart';
import '../../../services/theme/theme_service.dart';

import '../../../models/course.dart';
import '../../../models/course_schedule_config.dart';
import '../../../services/course_service.dart';
import '../../../services/course_schedule_transfer_service.dart';
import '../../widgets/bubble_popup.dart';
import 'widgets/course_schedule_table.dart';
import 'widgets/section_config_sheet.dart';
import 'widgets/week_select_sheet.dart';
import 'course_edit_page.dart';
import 'all_schedules_page.dart';
// import 'camera_import_schedule_page.dart';
// import 'file_import_schedule_page.dart';
import 'import_code_schedule_page.dart';
import 'scan_import_schedule_page.dart';
import 'schedule_share.dart';
import 'widgets/schedule_import_preview_dialog.dart';
import 'web_import_schedule_page.dart';

/// 展示并管理大学课程表的页面。
class TablePage extends StatefulWidget {
  const TablePage({super.key, this.initialImportRaw});

  /// 如果通过外部跳转携带了课表导入码原始文本，页面加载后会自动处理导入流程。
  final String? initialImportRaw;

  /// 创建页面状态以渲染课表内容。
  @override
  State<TablePage> createState() => _TablePageState();
}

class _TablePageState extends State<TablePage> with WidgetsBindingObserver {
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
  bool _isScheduleLocked = false;
  bool _isLoading = true;
  bool _isEditing = false;
  Object _editModeResetToken = Object();
  DateTime? _highlightDate;
  CourseTableAdaptiveLayout? _adaptiveLayoutCache;
  AdaptiveLayoutCacheKey? _adaptiveLayoutCacheKey;
  int _adaptiveLayoutGeneration = 0;

  final GlobalKey _importBtnKey = GlobalKey();
  final GlobalKey _shareBtnKey = GlobalKey();
  BubblePopupController? _toolbarBubbleController;
  bool _isToolbarBubbleOpen = false;
  Timer? _midnightRefreshTimer;
  DateTime _lastObservedDate = _dateOnly(DateTime.now());

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
          'code' => const ImportCodeSchedulePage(),
          'scan' => const ScanImportSchedulePage(),
          // 'camera' => const CameraImportSchedulePage(),
          // 'file' => const FileImportSchedulePage(),
          _ => const WebImportSchedulePage(),
        };
        final bool? result = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(builder: (BuildContext context) => page),
        );
        // 课表创建成功后刷新课表数据
        if (result == true && mounted) {
          _loadData(jumpToCurrentWeek: true);
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
      bundle: CourseScheduleTransferBundle(
        tableName: _tableName,
        semesterStart: _currentSemesterStart,
        maxWeek: _maxWeek,
        showWeekend: _showWeekend,
        showNonCurrentWeek: _showNonCurrentWeek,
        isScheduleLocked: _isScheduleLocked,
        scheduleConfig: _scheduleConfig,
        courses: _courses,
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

  /// 显示导入方法菜单，当前保留网页、扫码和导入码入口。
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
        width: 184,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildImportMenuItem('web', '网页导入课表', Icons.language, controller),
            const Divider(height: 1, thickness: 0.5),
            _buildImportMenuItem(
              'scan',
              '扫码导入课表',
              FontAwesomeIcons.qrcode,
              controller,
            ),
            const Divider(height: 1, thickness: 0.5),
            _buildImportMenuItem(
              'code',
              '导入码导入课表',
              Icons.content_paste_rounded,
              controller,
            ),
            // const Divider(height: 1, thickness: 0.5),
            // _buildImportMenuItem(
            //   'camera',
            //   '拍照导入课表',
            //   FontAwesomeIcons.camera,
            //   controller,
            // ),
            // const Divider(height: 1, thickness: 0.5),
            // _buildImportMenuItem(
            //   'file',
            //   '文件导入课表',
            //   FontAwesomeIcons.folderOpen,
            //   controller,
            // ),
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
    WidgetsBinding.instance.addObserver(this);
    _scheduleConfig = CourseScheduleConfig.njuDefaults();
    _sections = _scheduleConfig.generateSections();
    _pageController = PageController(initialPage: 0);
    _scrollGroup = LinkedScrollControllerGroup();
    _timeColumnController = _scrollGroup.addAndGet();
    // 加载数据后，如存在外部传入的导入码则在加载完成后处理导入流程
    _loadData(jumpToCurrentWeek: true).then((_) {
      if (widget.initialImportRaw != null &&
          widget.initialImportRaw!.trim().isNotEmpty) {
        _handleInitialImport(widget.initialImportRaw!);
      }
    });
    _scheduleMidnightRefresh();
  }

  Future<void> _handleInitialImport(String raw) async {
    try {
      final CourseScheduleTransferBundle bundle =
          CourseScheduleTransferService.decodeBundle(raw);
      if (!mounted) return;

      final bool confirmed = await ScheduleImportPreviewDialog.show(
        context,
        bundle,
      );
      if (!mounted) return;
      if (!confirmed) return;

      await CourseService.instance.createImportedSchedule(
        desiredName: bundle.tableName,
        courses: bundle.courses,
        config: bundle.scheduleConfig,
        semesterStart: bundle.semesterStart,
        maxWeek: bundle.maxWeek,
        showWeekend: bundle.showWeekend,
        showNonCurrentWeek: bundle.showNonCurrentWeek,
        isScheduleLocked: bundle.isScheduleLocked,
      );
      if (!mounted) return;
      AppToast.show(context, '课表已导入');
      // 刷新页面数据以展示新导入的课表
      await _loadData(jumpToCurrentWeek: true);
    } on FormatException catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        _resolveImportErrorMessage(raw, error),
        variant: AppToastVariant.warning,
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.show(context, '导入失败：$error', variant: AppToastVariant.error);
    }
  }

  String _resolveImportErrorMessage(String raw, FormatException error) {
    if (CourseScheduleTransferService.isLegacyShareLink(raw)) {
      return '这是旧版分享链接，不含完整课表数据，请重新生成新版分享二维码';
    }
    return error.message;
  }

  void _invalidateAdaptiveLayoutCache() {
    _adaptiveLayoutCache = null;
    _adaptiveLayoutCacheKey = null;
    _adaptiveLayoutGeneration++;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  int _clampDisplayedWeek(int week, {int? maxWeek}) {
    final int effectiveMaxWeek = maxWeek ?? _maxWeek;
    return week.clamp(1, effectiveMaxWeek);
  }

  void _refreshForCurrentDate({bool jumpToCurrentWeek = false}) {
    final int resolvedWeek = _resolveCurrentWeekFromNow();
    final int nextWeek = jumpToCurrentWeek
        ? resolvedWeek
        : _clampDisplayedWeek(_currentWeek);
    final bool shouldSyncPage = nextWeek != _currentWeek;
    setState(() {
      _currentWeek = nextWeek;
      _highlightDate = null;
      _lastObservedDate = _dateOnly(DateTime.now());
      _invalidateAdaptiveLayoutCache();
    });
    if (shouldSyncPage) {
      _syncPageToCurrentWeek();
    }
  }

  void _scheduleMidnightRefresh() {
    _midnightRefreshTimer?.cancel();
    final DateTime now = DateTime.now();
    final DateTime nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightRefreshTimer = Timer(nextMidnight.difference(now), () {
      if (!mounted) {
        return;
      }
      _refreshForCurrentDate();
      _scheduleMidnightRefresh();
    });
  }

  int _resolveCurrentWeekFromNow() {
    return _resolveWeekForDate(
      now: DateTime.now(),
      semesterStart: _currentSemesterStart,
      maxWeek: _maxWeek,
    );
  }

  int _resolveWeekForDate({
    required DateTime now,
    required DateTime semesterStart,
    required int maxWeek,
  }) {
    final DateTime firstWeekStart = semesterStart.subtract(
      Duration(days: semesterStart.weekday - 1),
    );
    final int diffDays = now.difference(firstWeekStart).inDays;
    int resolvedWeek = (diffDays / 7).floor() + 1;
    if (resolvedWeek < 1) {
      resolvedWeek = 1;
    }
    if (resolvedWeek > maxWeek) {
      resolvedWeek = maxWeek;
    }
    return resolvedWeek;
  }

  void _syncPageToCurrentWeek({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) {
        return;
      }
      final int targetPage = (_currentWeek - 1).clamp(0, _maxWeek - 1);
      final int currentPage =
          (_pageController.page ?? _pageController.initialPage).round();
      if (currentPage == targetPage) {
        return;
      }
      if (animate) {
        _pageController.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
        return;
      }
      _pageController.jumpToPage(targetPage);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      final DateTime today = _dateOnly(DateTime.now());
      if (today != _lastObservedDate) {
        _refreshForCurrentDate();
      }
      _scheduleMidnightRefresh();
      return;
    }
    _midnightRefreshTimer?.cancel();
  }

  Future<void> _loadData({bool jumpToCurrentWeek = false}) async {
    final service = CourseService.instance;
    final courses = await service.loadCourses();
    final config = await service.loadConfig();
    final semesterStart = await service.loadSemesterStart();
    final maxWeek = await service.loadMaxWeek();
    final tableName = await service.loadTableName();
    final showWeekend = await service.loadShowWeekend();
    final showNonCurrentWeek = await service.loadShowNonCurrentWeek();
    final isScheduleLocked = await service.loadScheduleLocked();
    final DateTime resolvedSemesterStart =
        semesterStart ?? _defaultSemesterStart;
    final int resolvedWeek = _resolveWeekForDate(
      now: DateTime.now(),
      semesterStart: resolvedSemesterStart,
      maxWeek: maxWeek,
    );
    final int nextWeek = jumpToCurrentWeek
        ? resolvedWeek
        : _clampDisplayedWeek(_currentWeek, maxWeek: maxWeek);
    final bool shouldSyncPage = nextWeek != _currentWeek;

    if (!mounted) return;

    setState(() {
      _courses = courses;
      _scheduleConfig = config;
      _sections = _scheduleConfig.generateSections();
      _currentSemesterStart = resolvedSemesterStart;
      _maxWeek = maxWeek;
      _tableName = tableName;
      _showWeekend = showWeekend;
      _showNonCurrentWeek = showNonCurrentWeek;
      _isScheduleLocked = isScheduleLocked;
      _currentWeek = nextWeek;
      _lastObservedDate = _dateOnly(DateTime.now());
      _invalidateAdaptiveLayoutCache();

      _isLoading = false;
    });

    if (shouldSyncPage) {
      _syncPageToCurrentWeek();
    }
    _scheduleMidnightRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightRefreshTimer?.cancel();
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
        _invalidateAdaptiveLayoutCache();
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
          currentWeek: _resolveCurrentWeekFromNow(),
          selectedWeek: _currentWeek,
          maxWeek: _maxWeek,
          onWeekSelected: _updateWeek,
        );
      },
    );
  }

  Future<void> _handleCourseAdded(Course newCourse) async {
    setState(() {
      _invalidateAdaptiveLayoutCache();
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
    final Object? result = await Navigator.of(context).push(
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
            isScheduleLocked: _isScheduleLocked,
            onConfigChanged: (CourseScheduleConfig config) async {
              await CourseService.instance.saveConfig(config);
              setState(() {
                _scheduleConfig = config;
                _sections = _scheduleConfig.generateSections();
                _invalidateAdaptiveLayoutCache();
              });
            },
            onSemesterStartChanged: (DateTime date) async {
              await CourseService.instance.saveSemesterStart(date);
              final int nextWeek = _clampDisplayedWeek(_currentWeek);
              final bool shouldSyncPage = nextWeek != _currentWeek;
              setState(() {
                _currentSemesterStart = date;
                _currentWeek = nextWeek;
                _lastObservedDate = _dateOnly(DateTime.now());
                _invalidateAdaptiveLayoutCache();
              });
              if (shouldSyncPage) {
                _syncPageToCurrentWeek(animate: true);
              }
            },
            onCurrentWeekChanged: (int week) {
              _updateWeek(week);
            },
            onMaxWeekChanged: (int max) async {
              await CourseService.instance.saveMaxWeek(max);
              final int nextWeek = _clampDisplayedWeek(
                _currentWeek,
                maxWeek: max,
              );
              final bool shouldSyncPage = nextWeek != _currentWeek;
              setState(() {
                _maxWeek = max;
                _currentWeek = nextWeek;
                _invalidateAdaptiveLayoutCache();
              });
              if (shouldSyncPage) {
                _syncPageToCurrentWeek();
              }
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
                _invalidateAdaptiveLayoutCache();
              });
            },
            onShowNonCurrentWeekChanged: (bool show) async {
              await CourseService.instance.saveShowNonCurrentWeek(show);
              setState(() {
                _showNonCurrentWeek = show;
                _invalidateAdaptiveLayoutCache();
              });
            },
            onScheduleLockedChanged: (bool locked) async {
              await CourseService.instance.saveScheduleLocked(locked);
              setState(() {
                _isScheduleLocked = locked;
              });
            },
            onOpenSectionSettings: () {
              _openSectionSheet();
            },
          );
        },
      ),
    );
    final bool shouldJumpToCurrentWeek = result == 'jump_to_current_week';
    _loadData(jumpToCurrentWeek: shouldJumpToCurrentWeek);
  }

  /// 构建带有固定左列的分页课表视图。
  Widget _buildPagedTable(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final MediaQueryData mediaQuery = MediaQuery.of(context);
        final double textScale = mediaQuery.textScaler.scale(14) / 14;
        // 计算时间列宽度：
        // 紧凑布局，时间列尽量窄以留更多空间给课程卡片
        final double timeColumnWidth = constraints.maxWidth / 9.5;

        // 计算课程区域的列宽
        final double gridWidth = constraints.maxWidth - timeColumnWidth;
        final double dayWidth = gridWidth / _visibleWeekdays.length;

        final AdaptiveLayoutCacheKey layoutCacheKey = AdaptiveLayoutCacheKey(
          logicalWidth: constraints.maxWidth,
          logicalHeight: constraints.maxHeight,
          dayWidth: dayWidth,
          devicePixelRatio: mediaQuery.devicePixelRatio,
          textScale: textScale,
          visibleDayCount: _visibleWeekdays.length,
          generation: _adaptiveLayoutGeneration,
        );

        if (_adaptiveLayoutCache == null ||
            _adaptiveLayoutCacheKey != layoutCacheKey) {
          _adaptiveLayoutCache = CourseScheduleTable.resolveAdaptiveLayout(
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
          _adaptiveLayoutCacheKey = layoutCacheKey;
        }

        final CourseTableAdaptiveLayout adaptiveLayout = _adaptiveLayoutCache!;
        final double effectiveSectionHeight = adaptiveLayout.sectionHeight;

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
                adaptiveLayout: adaptiveLayout,
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
                isScheduleLocked: _isScheduleLocked,
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
                    adaptiveLayout: adaptiveLayout,
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
                    isScheduleLocked: _isScheduleLocked,
                    onEditModeChanged: (isEditing) {
                      if (_isEditing != isEditing) {
                        setState(() {
                          _isEditing = isEditing;
                        });
                      }
                    },
                    onAddCourseTap: _isScheduleLocked
                        ? null
                        : (weekday, section) =>
                              _addCourse(weekday: weekday, section: section),
                    onCourseChanged: (oldCourse, newCourse) async {
                      setState(() {
                        _invalidateAdaptiveLayoutCache();
                        final index = _courses.indexOf(oldCourse);
                        if (index != -1) {
                          _courses[index] = newCourse;
                        }
                      });
                      await CourseService.instance.saveCourses(_courses);
                    },
                    onCourseDeleted: (course) async {
                      setState(() {
                        _invalidateAdaptiveLayoutCache();
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
