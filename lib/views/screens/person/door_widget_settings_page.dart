import 'dart:io';

import 'package:dormdevise/models/course.dart';
import 'package:dormdevise/models/door_widget_state.dart';
import 'package:dormdevise/services/course_service.dart';
import 'package:dormdevise/services/course_widget_service.dart';
import 'package:dormdevise/utils/app_toast.dart';
import 'package:dormdevise/views/screens/table/widgets/expandable_item.dart';
import 'package:dormdevise/widgets/door_desktop_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const MethodChannel _homeWidgetChannel = MethodChannel(
  'dormdevise/home_widget',
);

class _NativePinRequestResult {
  const _NativePinRequestResult({
    required this.requestAccepted,
    required this.pinSupported,
    required this.fallbackOpened,
    required this.fallbackType,
    required this.usedCallback,
    required this.launchedHomeAfterRequest,
  });

  final bool requestAccepted;
  final bool pinSupported;
  final bool fallbackOpened;
  final String fallbackType;
  final bool usedCallback;
  final bool launchedHomeAfterRequest;

  factory _NativePinRequestResult.fromNative(dynamic value) {
    if (value is bool) {
      return _NativePinRequestResult(
        requestAccepted: value,
        pinSupported: value,
        fallbackOpened: false,
        fallbackType: 'none',
        usedCallback: true,
        launchedHomeAfterRequest: false,
      );
    }

    if (value is Map) {
      return _NativePinRequestResult(
        requestAccepted: value['requestAccepted'] == true,
        pinSupported: value['pinSupported'] == true,
        fallbackOpened: value['fallbackOpened'] == true,
        fallbackType: (value['fallbackType'] as String?) ?? 'none',
        usedCallback: value['usedCallback'] != false,
        launchedHomeAfterRequest: value['launchedHomeAfterRequest'] == true,
      );
    }

    return const _NativePinRequestResult(
      requestAccepted: false,
      pinSupported: false,
      fallbackOpened: false,
      fallbackType: 'none',
      usedCallback: false,
      launchedHomeAfterRequest: false,
    );
  }
}

Future<void> _requestPinHomeWidget(
  BuildContext context, {
  required String methodName,
  required void Function(bool requesting) onRequestingChanged,
}) async {
  if (!Platform.isAndroid) {
    return;
  }

  onRequestingChanged(true);
  try {
    final dynamic nativeResponse = await _homeWidgetChannel
        .invokeMethod<dynamic>(methodName);
    final pinResult = _NativePinRequestResult.fromNative(nativeResponse);
    if (!context.mounted) {
      return;
    }

    if (pinResult.requestAccepted) {
      if (pinResult.launchedHomeAfterRequest) {
        return;
      }
      AppToast.show(
        context,
        pinResult.usedCallback
            ? '系统添加请求已发起，请在系统弹窗中确认添加。'
            : '系统已接收添加请求，请按桌面提示完成添加。',
        variant: AppToastVariant.success,
      );
      return;
    }

    final (message, variant) = switch (pinResult.fallbackType) {
      'permission' => (
        '已打开系统权限页，请允许桌面快捷方式或桌面组件相关权限后重试。',
        AppToastVariant.warning,
      ),
      'app_details' => (
        '已打开应用信息页，请检查桌面组件相关权限或系统限制后重试。',
        AppToastVariant.warning,
      ),
      'home_screen' => (
        '当前桌面未弹出系统添加窗口，已返回桌面，请长按空白处手动添加组件。',
        AppToastVariant.info,
      ),
      _ when !pinResult.pinSupported || !pinResult.fallbackOpened => (
        '当前桌面暂不支持应用内自动添加，请长按桌面空白处手动添加组件。',
        AppToastVariant.warning,
      ),
      _ => ('当前桌面未响应系统添加请求，请长按桌面空白处手动添加组件。', AppToastVariant.warning),
    };
    AppToast.show(context, message, variant: variant);
  } on PlatformException {
    if (!context.mounted) {
      return;
    }
    AppToast.show(context, '组件添加请求失败，请稍后重试。', variant: AppToastVariant.error);
  } finally {
    onRequestingChanged(false);
  }
}

class _CourseWidgetSummary {
  const _CourseWidgetSummary({
    required this.tableName,
    required this.totalCourseCount,
    required this.todayCourseCount,
    required this.currentWeek,
    required this.isConfigured,
  });

  final String tableName;
  final int totalCourseCount;
  final int todayCourseCount;
  final int currentWeek;
  final bool isConfigured;

  String get headline => isConfigured ? '当前课表：$tableName' : '当前还没有已配置的课表';

  String get detail {
    if (!isConfigured) {
      return '先在课表页创建或导入课程后，桌面组件会自动显示今日课程。';
    }
    if (currentWeek <= 0) {
      return '已同步 $tableName，目前不在学期范围内，桌面组件会显示今日无课。';
    }
    return '第$currentWeek周 · 今日 $todayCourseCount 节课程 · 共 $totalCourseCount 门课程';
  }
}

Future<_CourseWidgetSummary> _loadCourseWidgetSummary() async {
  final CourseService service = CourseService.instance;
  final String tableName = await service.loadTableName();
  final List<Course> courses = await service.loadCourses();
  final DateTime? semesterStart = await service.loadSemesterStart();
  final int maxWeek = await service.loadMaxWeek();
  final DateTime now = DateTime.now();
  int currentWeek = 0;
  if (semesterStart != null) {
    final DateTime startMonday = semesterStart.subtract(
      Duration(days: semesterStart.weekday - 1),
    );
    final DateTime todayMonday = DateTime(
      now.year,
      now.month,
      now.day - (now.weekday - 1),
    );
    final int daysDiff = todayMonday.difference(startMonday).inDays;
    currentWeek = (daysDiff ~/ 7) + 1;
    if (currentWeek < 1 || currentWeek > maxWeek) {
      currentWeek = 0;
    }
  }

  int todayCourseCount = 0;
  if (currentWeek > 0) {
    for (final Course course in courses) {
      final sessions = course.sessionsForWeek(currentWeek);
      for (final session in sessions) {
        if (session.weekday == now.weekday) {
          todayCourseCount++;
        }
      }
    }
  }

  final bool isConfigured = semesterStart != null || courses.isNotEmpty;
  return _CourseWidgetSummary(
    tableName: tableName,
    totalCourseCount: courses.length,
    todayCourseCount: todayCourseCount,
    currentWeek: currentWeek,
    isConfigured: isConfigured,
  );
}

/// 桌面微件配置页，包含开门组件和课表组件两个Tab。
class DoorWidgetSettingsPage extends StatefulWidget {
  const DoorWidgetSettingsPage({super.key});

  @override
  State<DoorWidgetSettingsPage> createState() => _DoorWidgetSettingsPageState();
}

class _DoorWidgetSettingsPageState extends State<DoorWidgetSettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('桌面组件配置'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '开门组件', icon: Icon(Icons.lock_outline_rounded)),
            Tab(text: '课表组件', icon: Icon(Icons.calendar_today_rounded)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_DoorWidgetTab(), _ScheduleWidgetTab()],
      ),
    );
  }
}

/// 开门组件配置Tab
class _DoorWidgetTab extends StatefulWidget {
  const _DoorWidgetTab();

  @override
  State<_DoorWidgetTab> createState() => _DoorWidgetTabState();
}

class _DoorWidgetTabState extends State<_DoorWidgetTab> {
  static const DoorWidgetState _previewState = DoorWidgetState(
    busy: false,
    lastResultSuccess: null,
    lastResultMessage: '待开门',
    lastUpdatedAt: null,
    doorLockStatus: DoorLockStatus.pending,
    deviceStatus: DeviceStatus.online,
    wifiStatus: WifiStatus.unconfigured,
    mqttConnectionStatus: MqttConnectionStatus.failed,
    mqttSubscriptionStatus: MqttSubscriptionStatus.unsubscribed,
  );

  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isRequestingPin = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _requestPinWidget(
    BuildContext context, {
    bool simple = false,
  }) async {
    if (_isRequestingPin) {
      return;
    }
    await _requestPinHomeWidget(
      context,
      methodName: simple
          ? 'requestPinDoorSimpleWidget'
          : 'requestPinDoorWidget',
      onRequestingChanged: (requesting) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isRequestingPin = requesting;
        });
      },
    );
  }

  Widget _buildPageIndicator(int index, ColorScheme colorScheme) {
    final bool isSelected = _currentPage == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: isSelected ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isSelected
            ? colorScheme.primary
            : colorScheme.outline.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // 组件预览标题
        Text(
          '组件预览',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '预览为固定示例状态：待开门、设备在线、WiFi非配置、MQTT连接失败',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),

        // 组件预览卡片 - 支持左右滑动
        Card(
          child: Column(
            children: [
              SizedBox(
                height: 256,
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() => _currentPage = index);
                  },
                  children: [
                    // 2x2 完整组件预览
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '完整版',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onPrimaryContainer,
                              ),
                              textScaler: TextScaler.noScaling,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Center(
                              child: FractionallySizedBox(
                                widthFactor: 0.62,
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: colorScheme.outlineVariant,
                                        width: 1,
                                      ),
                                    ),
                                    child: DoorLockWidget(
                                      state: _previewState,
                                      busy: false,
                                      onDoubleTap: null,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 1x1 简洁组件预览
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '简洁版',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSecondaryContainer,
                              ),
                              textScaler: TextScaler.noScaling,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Center(
                              child: FractionallySizedBox(
                                widthFactor: 0.24,
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: colorScheme.outlineVariant,
                                        width: 1,
                                      ),
                                    ),
                                    child: _SimpleDoorWidgetPreview(
                                      colorScheme: colorScheme,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 页面指示器
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildPageIndicator(0, colorScheme),
                    const SizedBox(width: 8),
                    _buildPageIndicator(1, colorScheme),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 添加到桌面按钮
        if (Platform.isAndroid)
          FilledButton.icon(
            onPressed: _isRequestingPin
                ? null
                : () => _requestPinWidget(context, simple: _currentPage == 1),
            icon: const Icon(Icons.add_to_home_screen_rounded),
            label: Text(_currentPage == 0 ? '添加完整版到桌面' : '添加简洁版到桌面'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        if (Platform.isAndroid) const SizedBox(height: 12),
        const SizedBox(height: 24),

        // 使用说明卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '使用小贴士',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                Text('1. 点击上方按钮或长按桌面空白处添加组件。'),
                Text('2. 双击门锁图标即可静默发送开门指令。'),
                Text('3. 组件每秒自动检测状态变化并更新。'),
                Text('4. 完整版显示 WiFi、MQTT 和设备状态，缩到 1x1 会自动切换紧凑样式。'),
                Text('5. 简洁版只显示门锁图标。'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SimpleDoorWidgetPreview extends StatelessWidget {
  const _SimpleDoorWidgetPreview({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.surface,
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: Icon(
              Icons.lock_outline_rounded,
              size: 19,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScheduleWidgetTab extends StatefulWidget {
  const _ScheduleWidgetTab();

  @override
  State<_ScheduleWidgetTab> createState() => _ScheduleWidgetTabState();
}

class _ScheduleWidgetTabState extends State<_ScheduleWidgetTab> {
  late Future<_CourseWidgetSummary> _summaryFuture;
  bool _isRequestingPin = false;
  bool _isHeaderFontExpanded = false;
  bool _isContentFontExpanded = false;
  bool _isReminderExpanded = false;
  int _headerFontSize = CourseWidgetDisplaySettings.defaultHeaderFontSize;
  int _contentFontSize = CourseWidgetDisplaySettings.defaultContentFontSize;
  int _reminderMinutes = CourseWidgetDisplaySettings.defaultReminderMinutes;

  @override
  void initState() {
    super.initState();
    _summaryFuture = _loadCourseWidgetSummary();
    _loadWidgetDisplaySettings();
  }

  Future<void> _loadWidgetDisplaySettings() async {
    final CourseWidgetDisplaySettings settings = await CourseWidgetService
        .instance
        .loadDisplaySettings();
    if (!mounted) {
      return;
    }
    setState(() {
      _headerFontSize = settings.headerFontSize;
      _contentFontSize = settings.contentFontSize;
      _reminderMinutes = settings.reminderMinutes;
    });
  }

  Future<void> _saveWidgetDisplaySettings({
    int? headerFontSize,
    int? contentFontSize,
    int? reminderMinutes,
  }) async {
    final CourseWidgetDisplaySettings settings = CourseWidgetDisplaySettings(
      headerFontSize: headerFontSize ?? _headerFontSize,
      contentFontSize: contentFontSize ?? _contentFontSize,
      reminderMinutes: reminderMinutes ?? _reminderMinutes,
    ).normalized();

    setState(() {
      _headerFontSize = settings.headerFontSize;
      _contentFontSize = settings.contentFontSize;
      _reminderMinutes = settings.reminderMinutes;
    });

    await CourseWidgetService.instance.saveDisplaySettings(settings);
  }

  Future<void> _reloadSummary() async {
    setState(() {
      _summaryFuture = _loadCourseWidgetSummary();
    });
    await _loadWidgetDisplaySettings();
  }

  Widget _buildGroup({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color:
            Theme.of(context).cardTheme.color ??
            Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
    );
  }

  Widget _buildNumberPicker({
    required int value,
    required int min,
    required int max,
    required int step,
    required ValueChanged<int> onChanged,
    required String Function(int value) labelBuilder,
    bool looping = true,
  }) {
    final int itemCount = ((max - min) / step).floor() + 1;
    final int baseIndex = ((value - min) / step).floor().clamp(
      0,
      itemCount - 1,
    );
    final int initialItem = looping ? baseIndex + itemCount * 100 : baseIndex;

    return Container(
      height: 150,
      color:
          Theme.of(context).cardTheme.color ??
          Theme.of(context).colorScheme.surface,
      child: CupertinoPicker(
        looping: looping,
        selectionOverlay: Container(),
        itemExtent: 44,
        scrollController: FixedExtentScrollController(initialItem: initialItem),
        onSelectedItemChanged: (int index) {
          final int normalized = index % itemCount;
          onChanged(min + normalized * step);
        },
        children: List<Widget>.generate(itemCount, (int index) {
          final int current = min + index * step;
          return Center(
            child: Text(
              labelBuilder(current),
              style: const TextStyle(fontSize: 24),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FutureBuilder<_CourseWidgetSummary>(
      future: _summaryFuture,
      builder: (context, snapshot) {
        final summary =
            snapshot.data ??
            const _CourseWidgetSummary(
              tableName: '我的课表',
              totalCourseCount: 0,
              todayCourseCount: 2,
              currentWeek: 8,
              isConfigured: false,
            );
        return RefreshIndicator(
          onRefresh: _reloadSummary,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              Text(
                '组件预览',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '预览为固定示意样式，实际桌面会显示所选日期的课程；支持左右切换日期、上下滑动查看更多，放大组件后会自动显示更多课程。',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '课表组件',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onPrimaryContainer,
                          ),
                          textScaler: TextScaler.noScaling,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _FixedWidgetPreviewFrame(
                        designWidth: 320,
                        designHeight: 188,
                        child: _CourseScheduleWidgetPreview(
                          colorScheme: colorScheme,
                          reminderMinutes: _reminderMinutes,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      summary.isConfigured
                          ? Icons.check_circle_outline_rounded
                          : Icons.info_outline_rounded,
                      size: 20,
                      color: colorScheme.secondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            summary.headline,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSecondaryContainer,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            summary.detail,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildGroup(
                children: [
                  ExpandableItem(
                    title: '顶栏字体字号',
                    value: Text(
                      '$_headerFontSize 号',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    isExpanded: _isHeaderFontExpanded,
                    onTap: () {
                      setState(() {
                        _isHeaderFontExpanded = !_isHeaderFontExpanded;
                        if (_isHeaderFontExpanded) {
                          _isContentFontExpanded = false;
                          _isReminderExpanded = false;
                        }
                      });
                    },
                    content: _buildNumberPicker(
                      value: _headerFontSize,
                      min: CourseWidgetDisplaySettings.minHeaderFontSize,
                      max: CourseWidgetDisplaySettings.maxHeaderFontSize,
                      step: 1,
                      onChanged: (int value) {
                        _saveWidgetDisplaySettings(headerFontSize: value);
                      },
                      labelBuilder: (int value) => '$value 号',
                    ),
                    showDivider: false,
                  ),
                  _buildDivider(),
                  ExpandableItem(
                    title: '卡片内容字号',
                    value: Text(
                      '$_contentFontSize 号',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    isExpanded: _isContentFontExpanded,
                    onTap: () {
                      setState(() {
                        _isContentFontExpanded = !_isContentFontExpanded;
                        if (_isContentFontExpanded) {
                          _isHeaderFontExpanded = false;
                          _isReminderExpanded = false;
                        }
                      });
                    },
                    content: _buildNumberPicker(
                      value: _contentFontSize,
                      min: CourseWidgetDisplaySettings.minContentFontSize,
                      max: CourseWidgetDisplaySettings.maxContentFontSize,
                      step: 1,
                      onChanged: (int value) {
                        _saveWidgetDisplaySettings(contentFontSize: value);
                      },
                      labelBuilder: (int value) => '$value 号',
                    ),
                    showDivider: false,
                  ),
                  _buildDivider(),
                  ExpandableItem(
                    title: '提前提醒',
                    value: Text(
                      _reminderMinutes == 0 ? '不提醒' : '$_reminderMinutes 分钟',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    isExpanded: _isReminderExpanded,
                    onTap: () {
                      setState(() {
                        _isReminderExpanded = !_isReminderExpanded;
                        if (_isReminderExpanded) {
                          _isHeaderFontExpanded = false;
                          _isContentFontExpanded = false;
                        }
                      });
                    },
                    content: _buildNumberPicker(
                      value: _reminderMinutes,
                      min: CourseWidgetDisplaySettings.minReminderMinutes,
                      max: CourseWidgetDisplaySettings.maxReminderMinutes,
                      step: CourseWidgetDisplaySettings.reminderStepMinutes,
                      onChanged: (int value) {
                        _saveWidgetDisplaySettings(reminderMinutes: value);
                      },
                      labelBuilder: (int value) =>
                          value == 0 ? '不提醒' : '$value 分钟',
                    ),
                    showDivider: false,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (Platform.isAndroid)
                FilledButton.icon(
                  onPressed: _isRequestingPin
                      ? null
                      : () => _requestPinHomeWidget(
                          context,
                          methodName: 'requestPinCourseScheduleWidget',
                          onRequestingChanged: (requesting) {
                            if (!mounted) {
                              return;
                            }
                            setState(() {
                              _isRequestingPin = requesting;
                            });
                          },
                        ),
                  icon: const Icon(Icons.add_to_home_screen_rounded),
                  label: const Text('添加课表组件到桌面'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              if (Platform.isAndroid) const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        '使用小贴士',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text('1. 课表组件会自动读取当前正在使用的课程表。'),
                      Text('2. 修改课程、周次配置或切换课表后，桌面组件会自动同步。'),
                      Text('3. 组件支持上下滑动查看全天课程，放大后会直接显示更多课程。'),
                      Text('4. 可分别调整顶栏和卡片内容字号，提升桌面可读性。'),
                      Text('5. 提前提醒支持 0-60 分钟（每 5 分钟），0 分钟表示不提醒。'),
                      Text('6. 正在上课为绿色高亮；提醒窗口内为蓝色高亮并显示分钟倒计时，1 分钟内显示“即将”。'),
                      Text('7. 轻点课表组件可直接打开应用查看完整课表。'),
                      Text('8. 若系统不支持应用内添加，可长按桌面空白处手动添加。'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FixedWidgetPreviewFrame extends StatelessWidget {
  const _FixedWidgetPreviewFrame({
    required this.child,
    required this.designWidth,
    required this.designHeight,
  });

  final Widget child;
  final double designWidth;
  final double designHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth;
        final double scale = availableWidth < designWidth
            ? availableWidth / designWidth
            : 1.0;

        return Center(
          child: SizedBox(
            width: designWidth * scale,
            height: designHeight * scale,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: designWidth,
                height: designHeight,
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.noScaling),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CourseScheduleWidgetPreview extends StatelessWidget {
  const _CourseScheduleWidgetPreview({
    required this.colorScheme,
    required this.reminderMinutes,
  });

  final ColorScheme colorScheme;
  final int reminderMinutes;

  @override
  Widget build(BuildContext context) {
    const int previewContentFontSize = 12;
    const double resolvedHeaderSize = 14;
    const double resolvedDateSize = 11;
    const double resolvedArrowSize = 12;
    final String upcomingHint = reminderMinutes == 0
        ? '3-4节'
        : (reminderMinutes <= 5 ? '3-4节 · 即将' : '3-4节 · 8分钟后');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '我的课表',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: resolvedHeaderSize,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '<',
                    style: TextStyle(
                      fontSize: resolvedArrowSize,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '周一 · 第1周',
                    style: TextStyle(
                      fontSize: resolvedDateSize,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '>',
                    style: TextStyle(
                      fontSize: resolvedArrowSize,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Column(
              children: [
                _CoursePreviewRow(
                  color: const Color(0xFFC8E6C9),
                  name: '高等数学',
                  info: '08:30-10:05 · 教一101',
                  section: '1-2节 · 进行中',
                  contentFontSize: previewContentFontSize,
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 6),
                _CoursePreviewRow(
                  color: const Color(0xFFBBDEFB),
                  name: '大学英语',
                  info: '10:35-12:10 · 教二203',
                  section: upcomingHint,
                  contentFontSize: previewContentFontSize,
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoursePreviewRow extends StatelessWidget {
  const _CoursePreviewRow({
    required this.color,
    required this.name,
    required this.info,
    required this.section,
    required this.contentFontSize,
    required this.colorScheme,
  });

  final Color color;
  final String name;
  final String info;
  final String section;
  final int contentFontSize;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final double resolvedTitleSize = contentFontSize.toDouble();
    final double resolvedDetailSize = (resolvedTitleSize - 2)
        .clamp(8, 18)
        .toDouble();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: resolvedTitleSize,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  info,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: resolvedDetailSize,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            section,
            style: TextStyle(
              fontSize: resolvedDetailSize,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
