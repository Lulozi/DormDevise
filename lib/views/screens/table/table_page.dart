import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:dormdevise/utils/app_toast.dart';
import 'package:dormdevise/utils/app_route_observer.dart';
import '../../../services/theme/theme_service.dart';

import '../../../models/course.dart';
import '../../../models/course_schedule_config.dart';
import '../../../models/course_schedule_snapshot.dart';
import '../../../services/course_service.dart';
import '../../../services/course_schedule_transfer_service.dart';
import '../../../services/course_widget_service.dart';
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
  const TablePage({
    super.key,
    this.initialImportRaw,
    this.initialFocusWeek,
    this.initialFocusWeekday,
    this.initialFocusSection,
    this.initialFocusCourseName,
    this.launchedFromWidget = false,
    this.isForegroundPage = true,
  });

  /// 如果通过外部跳转携带了课表导入码原始文本，页面加载后会自动处理导入流程。
  final String? initialImportRaw;

  /// 通过桌面组件打开时需要优先展示的周次。
  final int? initialFocusWeek;

  /// 通过桌面组件打开时需要高亮的星期，周一=1。
  final int? initialFocusWeekday;

  /// 通过桌面组件点击具体课程时需要滚动到的起始节次。
  final int? initialFocusSection;

  /// 通过桌面组件点击具体课程时需要高亮的课程名。
  final String? initialFocusCourseName;

  /// 是否由桌面组件启动。由组件启动时返回键直接回桌面，不回到应用此前页面。
  final bool launchedFromWidget;

  /// 当前是否处于底部导航的前台页面。
  final bool isForegroundPage;

  /// 创建页面状态以渲染课表内容。
  @override
  State<TablePage> createState() => TablePageState();
}

class _WidgetTableFocusRequest {
  const _WidgetTableFocusRequest({
    required this.week,
    this.weekday,
    this.startSection,
    this.courseName,
  });

  final int week;
  final int? weekday;
  final int? startSection;
  final String? courseName;
}

class _WidgetCourseHighlightTarget {
  const _WidgetCourseHighlightTarget({
    required this.week,
    required this.weekday,
    required this.startSection,
    this.courseName,
  });

  final int week;
  final int weekday;
  final int startSection;
  final String? courseName;
}

class TablePageState extends State<TablePage>
    with WidgetsBindingObserver, RouteAware {
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
  bool _blockPopAfterEditExit = false;
  Object _editModeResetToken = Object();
  DateTime? _highlightDate;
  CourseTableAdaptiveLayout? _adaptiveLayoutCache;
  AdaptiveLayoutCacheKey? _adaptiveLayoutCacheKey;
  int _adaptiveLayoutGeneration = 0;
  double _lastResolvedSectionHeight = 76;
  _WidgetTableFocusRequest? _pendingWidgetFocus;
  _WidgetCourseHighlightTarget? _highlightedCourseTarget;
  Timer? _widgetCourseHighlightTimer;

  final GlobalKey _importBtnKey = GlobalKey();
  final GlobalKey _shareBtnKey = GlobalKey();
  BubblePopupController? _toolbarBubbleController;
  bool _isToolbarBubbleOpen = false;
  Timer? _midnightRefreshTimer;
  DateTime _lastObservedDate = _dateOnly(DateTime.now());
  bool _isRouteVisible = true;
  bool _isAppInForeground = true;
  bool _shouldRefreshForCurrentDateWhenActive = false;
  bool _isRouteObserverSubscribed = false;
  bool _hasLoadedDataOnce = false;
  bool _pendingDataReload = false;
  bool _pendingJumpToCurrentWeekReload = false;
  bool _pendingResetWidgetDisplayDateToToday = false;
  bool _pendingWidgetSyncAfterLoad = false;
  Future<void>? _activeDataLoadFuture;
  StreamSubscription<CourseDataChangeEvent>? _courseDataChangeSubscription;
  String _activeScheduleId = '';

  List<int> get _visibleWeekdays =>
      _showWeekend ? <int>[1, 2, 3, 4, 5, 6, 7] : <int>[1, 2, 3, 4, 5];

  bool get _isPageActive =>
      widget.isForegroundPage && _isRouteVisible && _isAppInForeground;

  /// 处理来自外层容器的返回/退出请求。
  ///
  /// 返回 `true` 表示本页已消费事件（例如退出编辑模式），
  /// 外层不应继续执行真正的返回或退到桌面。
  bool handleBackOrExitAction() {
    if (_isEditing) {
      _exitEditMode(blockPopThisFrame: true);
      return true;
    }
    if (_blockPopAfterEditExit) {
      // 编辑模式刚由返回动作退出的同一帧，拦截外层继续处理。
      return true;
    }
    if (_isToolbarBubbleOpen) {
      unawaited(_dismissToolbarBubble());
      return true;
    }
    return false;
  }

  void _exitEditMode({bool blockPopThisFrame = false}) {
    setState(() {
      _editModeResetToken = Object();
      _isEditing = false;
      if (blockPopThisFrame) {
        // 防止同一次返回手势同时触发路由退出。
        _blockPopAfterEditExit = true;
      }
    });
    if (blockPopThisFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_blockPopAfterEditExit) {
          return;
        }
        setState(() {
          _blockPopAfterEditExit = false;
        });
      });
    }
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
    if (widget.initialFocusWeek != null) {
      _pendingWidgetFocus = _WidgetTableFocusRequest(
        week: widget.initialFocusWeek!,
        weekday: widget.initialFocusWeekday,
        startSection: widget.initialFocusSection,
        courseName: widget.initialFocusCourseName,
      );
    }
    _pageController = PageController(initialPage: 0);
    _scrollGroup = LinkedScrollControllerGroup();
    _timeColumnController = _scrollGroup.addAndGet();
    final Future<void> initialLoad = _loadData(
      jumpToCurrentWeek: _pendingWidgetFocus == null,
    );
    _courseDataChangeSubscription = CourseService.instance.changes.listen(
      _handleCourseDataChanged,
    );
    if (widget.isForegroundPage &&
        widget.initialImportRaw != null &&
        widget.initialImportRaw!.trim().isNotEmpty) {
      initialLoad.then((_) {
        if (!mounted) {
          return;
        }
        _handleInitialImport(widget.initialImportRaw!);
      });
    }
    _handleActivityStateChanged();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (!_isRouteObserverSubscribed && route is PageRoute<dynamic>) {
      appRouteObserver.subscribe(this, route as PageRoute<void>);
      _isRouteObserverSubscribed = true;
    }
  }

  @override
  void didPush() {
    _isRouteVisible = true;
    _handleActivityStateChanged();
  }

  @override
  void didPopNext() {
    _isRouteVisible = true;
    _handleActivityStateChanged();
  }

  @override
  void didPushNext() {
    _isRouteVisible = false;
    _midnightRefreshTimer?.cancel();
  }

  @override
  void didUpdateWidget(covariant TablePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isForegroundPage != widget.isForegroundPage) {
      _handleActivityStateChanged();
    }
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
      await CourseWidgetService.instance.syncWidget(
        resetDisplayDateToToday: true,
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

  void _handleActivityStateChanged() {
    if (!_isPageActive) {
      _midnightRefreshTimer?.cancel();
      return;
    }
    if (_pendingDataReload) {
      unawaited(_flushPendingDataReload());
      return;
    }
    if (!_hasLoadedDataOnce) {
      return;
    }
    final DateTime today = _dateOnly(DateTime.now());
    if (_shouldRefreshForCurrentDateWhenActive || today != _lastObservedDate) {
      _shouldRefreshForCurrentDateWhenActive = false;
      _refreshForCurrentDate();
      return;
    }
    _scheduleMidnightRefresh();
  }

  Future<void> _flushPendingDataReload() {
    if (_activeDataLoadFuture != null) {
      return _activeDataLoadFuture!;
    }
    if (!_pendingDataReload || !_isPageActive) {
      return Future<void>.value();
    }
    final bool jumpToCurrentWeek = _pendingJumpToCurrentWeekReload;
    final bool resetWidgetDisplayDateToToday =
        _pendingResetWidgetDisplayDateToToday;
    final bool syncWidgetAfterLoad = _pendingWidgetSyncAfterLoad;
    _pendingDataReload = false;
    _pendingJumpToCurrentWeekReload = false;
    _pendingResetWidgetDisplayDateToToday = false;
    _pendingWidgetSyncAfterLoad = false;
    final Future<void> loadFuture = _performLoadData(
      jumpToCurrentWeek: jumpToCurrentWeek,
      resetWidgetDisplayDateToToday: resetWidgetDisplayDateToToday,
      syncWidgetAfterLoad: syncWidgetAfterLoad,
    );
    _activeDataLoadFuture = loadFuture;
    loadFuture.whenComplete(() {
      if (identical(_activeDataLoadFuture, loadFuture)) {
        _activeDataLoadFuture = null;
      }
      if (_pendingDataReload && _isPageActive) {
        unawaited(_flushPendingDataReload());
      }
    });
    return loadFuture;
  }

  void _handleCourseDataChanged(CourseDataChangeEvent event) {
    if (!mounted) {
      return;
    }
    // 仅在事件明确属于其他课表且不是全局切换/列表变更时跳过刷新。
    final bool isGlobalEvent =
        event.scope == 'schedules' ||
        event.scope == 'current_schedule' ||
        event.scope == 'delete_schedules' ||
        event.scheduleId == null;
    if (!isGlobalEvent &&
        _activeScheduleId.isNotEmpty &&
        event.scheduleId != _activeScheduleId) {
      return;
    }

    unawaited(_loadData());
  }

  int _clampDisplayedWeek(int week, {int? maxWeek}) {
    final int effectiveMaxWeek = maxWeek ?? _maxWeek;
    return week.clamp(1, effectiveMaxWeek);
  }

  void _refreshForCurrentDate({bool jumpToCurrentWeek = false}) {
    if (!_isPageActive) {
      _shouldRefreshForCurrentDateWhenActive = true;
      _midnightRefreshTimer?.cancel();
      return;
    }
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
    _scheduleMidnightRefresh();
  }

  void _scheduleMidnightRefresh() {
    _midnightRefreshTimer?.cancel();
    if (!_isPageActive) {
      return;
    }
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

  DateTime? _resolveDateForWeekday(int week, int? weekday) {
    if (weekday == null || weekday < 1 || weekday > 7) {
      return null;
    }
    final List<DateTime> dates = _resolveWeekDates(week);
    return dates[weekday - 1];
  }

  void _applyPendingWidgetFocusIfNeeded({bool animate = false}) {
    final _WidgetTableFocusRequest? request = _pendingWidgetFocus;
    if (request == null) {
      return;
    }
    _pendingWidgetFocus = null;
    _focusWidgetTarget(request, animate: animate);
  }

  void _focusWidgetTarget(
    _WidgetTableFocusRequest request, {
    bool animate = false,
  }) {
    final int targetWeek = _clampDisplayedWeek(request.week);
    final DateTime? targetDate = _resolveDateForWeekday(
      targetWeek,
      request.weekday,
    );
    final bool shouldSyncPage = targetWeek != _currentWeek;
    setState(() {
      _currentWeek = targetWeek;
      _highlightDate = targetDate;
      _lastObservedDate = _dateOnly(DateTime.now());
      _highlightedCourseTarget =
          request.weekday != null && request.startSection != null
          ? _WidgetCourseHighlightTarget(
              week: targetWeek,
              weekday: request.weekday!,
              startSection: request.startSection!,
              courseName: request.courseName,
            )
          : null;
    });
    if (_highlightedCourseTarget != null) {
      _widgetCourseHighlightTimer?.cancel();
      _widgetCourseHighlightTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) {
          return;
        }
        setState(() {
          _highlightedCourseTarget = null;
        });
      });
    }
    if (shouldSyncPage) {
      _syncPageToCurrentWeek(animate: animate);
    }
    if (request.startSection != null) {
      _scheduleScrollToSection(
        week: targetWeek,
        startSection: request.startSection!,
      );
    }
  }

  void _scheduleScrollToSection({
    required int week,
    required int startSection,
    int attempt = 0,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final int targetPage = (week - 1).clamp(0, _maxWeek - 1);
      if (_pageController.hasClients) {
        final int currentPage =
            (_pageController.page ?? _pageController.initialPage).round();
        if (currentPage != targetPage) {
          if (attempt >= 20) {
            return;
          }
          Future<void>.delayed(const Duration(milliseconds: 64), () {
            if (!mounted) {
              return;
            }
            _scheduleScrollToSection(
              week: week,
              startSection: startSection,
              attempt: attempt + 1,
            );
          });
          return;
        }
      }
      final ScrollController controller = _scrollControllerForWeek(week - 1);
      if (!controller.hasClients) {
        if (attempt >= 20) {
          return;
        }
        Future<void>.delayed(const Duration(milliseconds: 64), () {
          if (!mounted) {
            return;
          }
          _scheduleScrollToSection(
            week: week,
            startSection: startSection,
            attempt: attempt + 1,
          );
        });
        return;
      }

      final double targetOffset = (_resolveSectionScrollOffset(
        startSection,
      )).clamp(0.0, controller.position.maxScrollExtent).toDouble();
      if ((controller.offset - targetOffset).abs() < 1) {
        return;
      }
      controller.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  double _resolveSectionScrollOffset(int startSection) {
    final double effectiveSectionHeight = _lastResolvedSectionHeight >= 48
        ? _lastResolvedSectionHeight
        : 48.0;
    double offset = 0;
    for (int index = 0; index < _sections.length; index++) {
      final SectionTime section = _sections[index];
      if (section.index == startSection) {
        return offset;
      }
      offset += effectiveSectionHeight;
      final bool hasNext = index < _sections.length - 1;
      if (hasNext && _sections[index + 1].segmentName != section.segmentName) {
        offset += 24;
      }
    }
    return offset;
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
    if (state == AppLifecycleState.resumed) {
      _isAppInForeground = true;
      if (mounted) {
        final DateTime today = _dateOnly(DateTime.now());
        if (today != _lastObservedDate) {
          _shouldRefreshForCurrentDateWhenActive = true;
        }
        _handleActivityStateChanged();
      }
      return;
    }
    _isAppInForeground = false;
    _midnightRefreshTimer?.cancel();
  }

  Future<void> _loadData({
    bool jumpToCurrentWeek = false,
    bool resetWidgetDisplayDateToToday = false,
    bool syncWidgetAfterLoad = false,
  }) {
    _pendingDataReload = true;
    _pendingJumpToCurrentWeekReload =
        _pendingJumpToCurrentWeekReload || jumpToCurrentWeek;
    _pendingResetWidgetDisplayDateToToday =
        _pendingResetWidgetDisplayDateToToday || resetWidgetDisplayDateToToday;
    _pendingWidgetSyncAfterLoad =
        _pendingWidgetSyncAfterLoad || syncWidgetAfterLoad;
    return _flushPendingDataReload();
  }

  Future<void> _performLoadData({
    required bool jumpToCurrentWeek,
    required bool resetWidgetDisplayDateToToday,
    required bool syncWidgetAfterLoad,
  }) async {
    final service = CourseService.instance;
    final snapshot = await service.loadScheduleSnapshot();
    final courses = snapshot.courses;
    final config = snapshot.config;
    final semesterStart = snapshot.semesterStart;
    final maxWeek = snapshot.maxWeek;
    final tableName = snapshot.tableName;
    final showWeekend = snapshot.showWeekend;
    final showNonCurrentWeek = snapshot.showNonCurrentWeek;
    final isScheduleLocked = snapshot.isScheduleLocked;
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

    if (!mounted) {
      return;
    }
    if (!_isPageActive) {
      _pendingDataReload = true;
      _pendingJumpToCurrentWeekReload =
          _pendingJumpToCurrentWeekReload || jumpToCurrentWeek;
      _pendingResetWidgetDisplayDateToToday =
          _pendingResetWidgetDisplayDateToToday ||
          resetWidgetDisplayDateToToday;
      _pendingWidgetSyncAfterLoad =
          _pendingWidgetSyncAfterLoad || syncWidgetAfterLoad;
      return;
    }

    setState(() {
      _courses = CourseScheduleSnapshot.cloneCourses(courses).toList();
      _activeScheduleId = snapshot.scheduleId;
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

      _hasLoadedDataOnce = true;
      _isLoading = false;
    });
    if (syncWidgetAfterLoad) {
      unawaited(
        CourseWidgetService.instance.syncWidget(
          resetDisplayDateToToday: resetWidgetDisplayDateToToday,
        ),
      );
    }

    if (shouldSyncPage) {
      _syncPageToCurrentWeek();
    }
    _applyPendingWidgetFocusIfNeeded();
    _scheduleMidnightRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isRouteObserverSubscribed) {
      appRouteObserver.unsubscribe(this);
    }
    _courseDataChangeSubscription?.cancel();
    _midnightRefreshTimer?.cancel();
    _widgetCourseHighlightTimer?.cancel();
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
        canPop: !widget.launchedFromWidget && !_isToolbarBubbleOpen,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_isToolbarBubbleOpen) {
            _dismissToolbarBubble();
            return;
          }
          if (widget.launchedFromWidget) {
            _moveTaskToBack();
          }
        },
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          resizeToAvoidBottomInset: false,
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return PopScope(
      canPop:
          !widget.launchedFromWidget &&
          !_isToolbarBubbleOpen &&
          !_isEditing &&
          !_blockPopAfterEditExit,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (handleBackOrExitAction()) {
          return;
        }
        if (widget.launchedFromWidget) {
          _moveTaskToBack();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: GestureDetector(
            onTap: _isEditing ? _exitEditMode : null,
            behavior: HitTestBehavior.translucent,
            child: MediaQuery.removeViewInsets(
              context: context,
              removeBottom: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildToolbar(context),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: RepaintBoundary(child: _buildPagedTable(context)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建顶部工具栏，包含返回与菜单操作。
  Widget _buildToolbar(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final TextStyle baseTitleStyle = theme.textTheme.headlineSmall!.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 0.4,
    );
    final String toolbarTitleText = _isEditing ? '编辑模式' : _tableName;
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
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder:
                    (Widget? currentChild, List<Widget> previousChildren) {
                      return Stack(
                        alignment: Alignment.centerLeft,
                        children: <Widget>[
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      );
                    },
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.1),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: LayoutBuilder(
                  key: ValueKey<bool>(_isEditing),
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final bool allowWrap = !_isEditing;
                    final int charCount = toolbarTitleText.trim().runes.length;
                    double titleFontSize = baseTitleStyle.fontSize ?? 24;
                    if (allowWrap &&
                        (constraints.maxWidth < 240 || charCount > 10)) {
                      titleFontSize = 18;
                    }
                    if (allowWrap &&
                        (constraints.maxWidth < 200 || charCount > 16)) {
                      titleFontSize = 16;
                    }
                    if (allowWrap &&
                        (constraints.maxWidth < 165 || charCount > 22)) {
                      titleFontSize = 14;
                    }

                    return Text(
                      toolbarTitleText,
                      // 课表页标题支持窄屏自适应缩小并换行，尽量完整展示课程表名。
                      style: baseTitleStyle.copyWith(
                        fontSize: titleFontSize,
                        height: allowWrap ? 1.2 : baseTitleStyle.height,
                        letterSpacing: allowWrap
                            ? 0.1
                            : baseTitleStyle.letterSpacing,
                      ),
                      maxLines: allowWrap ? null : 1,
                      softWrap: allowWrap,
                      overflow: allowWrap
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                    );
                  },
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1.0,
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: _isEditing
                    ? const SizedBox.shrink(key: ValueKey<bool>(true))
                    : Padding(
                        key: const ValueKey<bool>(false),
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          _formatSemesterRange(),
                          style: subtitleStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _ToolbarIconButton(
          key: _importBtnKey,
          icon: FontAwesomeIcons.calendarPlus,
          tooltip: '导入课表',
          onPressed: () async {
            if (_isEditing) {
              _exitEditMode();
              return;
            }
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
            if (_isEditing) {
              _exitEditMode();
              return;
            }
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
            if (_isEditing) {
              _exitEditMode();
              return;
            }
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
    if (_isEditing) {
      _exitEditMode();
      return;
    }
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
      await CourseWidgetService.instance.syncWidget(
        resetDisplayDateToToday: true,
      );
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
    await CourseWidgetService.instance.syncWidget(
      resetDisplayDateToToday: true,
    );
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
          );
        },
      ),
    );
    final bool shouldJumpToCurrentWeek = result == 'jump_to_current_week';
    final bool shouldRefresh =
        shouldJumpToCurrentWeek || result == 'refresh_only';
    if (!shouldRefresh) {
      return;
    }
    _loadData(
      jumpToCurrentWeek: shouldJumpToCurrentWeek,
      resetWidgetDisplayDateToToday: shouldJumpToCurrentWeek,
      syncWidgetAfterLoad: true,
    );
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
        _lastResolvedSectionHeight = effectiveSectionHeight;

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
                  if (_isEditing) {
                    _exitEditMode();
                    return;
                  }
                  _openWeekSelectSheet();
                },
                onTimeColumnTap: () {
                  if (_isEditing) {
                    _exitEditMode();
                    return;
                  }
                  _openSectionSheet();
                },
                includeTimeColumn: true,
                applySurface: false,
                timeColumnWidth: timeColumnWidth,
                scrollController: _timeColumnController,
                editModeResetToken: _editModeResetToken,
                isScheduleLocked: _isScheduleLocked,
                contentGeneration: _adaptiveLayoutGeneration,
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
                      if (_isEditing) {
                        _exitEditMode();
                        return;
                      }
                      _pickDate(context);
                    },
                    highlightDate: _highlightDate,
                    highlightedCourseTarget:
                        _highlightedCourseTarget != null &&
                            _highlightedCourseTarget!.week == targetWeek
                        ? CourseTableHighlightTarget(
                            weekday: _highlightedCourseTarget!.weekday,
                            startSection:
                                _highlightedCourseTarget!.startSection,
                            courseName: _highlightedCourseTarget!.courseName,
                          )
                        : null,
                    includeTimeColumn: false,
                    timeColumnWidth: timeColumnWidth,
                    leadingInset: 0,
                    scrollController: _scrollControllerForWeek(index),
                    showNonCurrentWeek: _showNonCurrentWeek,
                    applySurface: false,
                    editModeResetToken: _editModeResetToken,
                    isScheduleLocked: _isScheduleLocked,
                    contentGeneration: _adaptiveLayoutGeneration,
                    onEditModeChanged: (isEditing) {
                      if (_isEditing != isEditing) {
                        setState(() {
                          _isEditing = isEditing;
                        });
                      }
                    },
                    onAddCourseTap: _isScheduleLocked
                        ? null
                        : (weekday, section) {
                            if (_isEditing) {
                              _exitEditMode();
                              return;
                            }
                            _addCourse(weekday: weekday, section: section);
                          },
                    onCourseChanged: (oldCourse, newCourse) async {
                      setState(() {
                        _invalidateAdaptiveLayoutCache();
                        final index = _courses.indexOf(oldCourse);
                        if (index != -1) {
                          _courses[index] = newCourse;
                        }
                      });
                      await CourseService.instance.saveCourses(_courses);
                      await CourseWidgetService.instance.syncWidget(
                        resetDisplayDateToToday: true,
                      );
                    },
                    onCourseDeleted: (course) async {
                      setState(() {
                        _invalidateAdaptiveLayoutCache();
                        _courses.remove(course);
                      });
                      await CourseService.instance.saveCourses(_courses);
                      await CourseWidgetService.instance.syncWidget(
                        resetDisplayDateToToday: true,
                      );
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

  Future<void> _moveTaskToBack() async {
    try {
      const MethodChannel channel = MethodChannel('dormdevise/home_widget');
      await channel.invokeMethod<void>('returnToHomeScreen');
    } catch (_) {
      // 静默忽略失败，避免影响页面返回体验。
    }
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
