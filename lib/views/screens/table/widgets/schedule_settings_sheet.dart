import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'package:dormdevise/utils/index.dart';
import 'package:dormdevise/utils/app_toast.dart';
import 'package:dormdevise/utils/text_length_counter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/course_schedule_config.dart';
import '../../../../services/course_service.dart';
import 'expandable_item.dart';

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

/// 课程表设置页面，用于配置学期开始时间、周数、周末显示等全局设置。
class ScheduleSettingsPage extends StatefulWidget {
  final CourseScheduleConfig scheduleConfig;
  final DateTime semesterStart;
  final int currentWeek;
  final int maxWeek;
  final String tableName;
  final bool showWeekend;
  final bool showNonCurrentWeek;
  final bool isScheduleLocked;
  final ValueChanged<CourseScheduleConfig> onConfigChanged;
  final ValueChanged<DateTime> onSemesterStartChanged;
  final ValueChanged<int> onCurrentWeekChanged;
  final ValueChanged<int> onMaxWeekChanged;
  final ValueChanged<String> onTableNameChanged;
  final ValueChanged<bool> onShowWeekendChanged;
  final ValueChanged<bool> onShowNonCurrentWeekChanged;
  final ValueChanged<bool>? onScheduleLockedChanged;
  final VoidCallback onOpenSectionSettings;
  final bool isEmbedded;
  final Widget? header;
  final Future<String?> Function(String)? nameValidator;
  final bool saveNotificationImmediately;
  final String? scheduleId;

  const ScheduleSettingsPage({
    super.key,
    required this.scheduleConfig,
    required this.semesterStart,
    required this.currentWeek,
    required this.maxWeek,
    required this.tableName,
    required this.showWeekend,
    required this.showNonCurrentWeek,
    required this.isScheduleLocked,
    required this.onConfigChanged,
    required this.onSemesterStartChanged,
    required this.onCurrentWeekChanged,
    required this.onMaxWeekChanged,
    required this.onTableNameChanged,
    required this.onShowWeekendChanged,
    required this.onShowNonCurrentWeekChanged,
    this.onScheduleLockedChanged,
    required this.onOpenSectionSettings,
    this.isEmbedded = false,
    this.header,
    this.nameValidator,
    this.saveNotificationImmediately = true,
    this.scheduleId,
  });

  @override
  State<ScheduleSettingsPage> createState() => _ScheduleSettingsPageState();
}

class _ScheduleSettingsPageState extends State<ScheduleSettingsPage> {
  // 课程表名称最大长度：30 个半角单位（中文按 2 计算）。
  static const int _tableNameMaxLengthUnits = 30;

  // 展开状态
  bool _isStartDateExpanded = false;
  bool _isMaxWeekExpanded = false;
  bool _isColorAllocationExpanded = false;
  bool _isReminderTimeExpanded = false;

  // 用于实时更新的本地状态
  late DateTime _semesterStart;
  late int _currentWeek;
  late int _maxWeek;
  late bool _showWeekend;
  late bool _showNonCurrentWeek;
  late bool _isScheduleLocked;
  final bool _showInCalendar = false;
  late String _tableName;
  String? _colorAllocationAction;
  bool _isRequestingDesktopWidget = false;

  // 标记提醒设置是否有未保存的变更
  bool _hasReminderChanged = false;

  // 课程提醒相关状态
  int _reminderTime = 15;
  bool _isReminderMethodEnabled = false;
  String _reminderMethod = 'notification';
  bool _reminderVibrationEnabled = true;
  bool _enableAnimation = false;

  late FixedExtentScrollController _reminderTimeController;
  final List<int> _reminderTimeOptions = [0, 5, 10, 15, 20, 25, 30, 40, 50, 60];

  @override
  void initState() {
    super.initState();
    _semesterStart = widget.semesterStart;
    _currentWeek = widget.currentWeek;
    _maxWeek = widget.maxWeek;
    _showWeekend = widget.showWeekend;
    _showNonCurrentWeek = widget.showNonCurrentWeek;
    _isScheduleLocked = widget.isScheduleLocked;
    _tableName = widget.tableName;

    _initReminderController();

    _loadColorAllocationAction();
    _loadReminderSettings();
  }

  void _initReminderController() {
    int index = _reminderTimeOptions.indexOf(_reminderTime);
    if (index == -1) index = 3; // 默认选中 15 分钟 (0, 5, 10, 15)
    // 设置一个较大的初始偏移量，使列表处于“中间”位置，方便向上滚动
    final int initialItem = index + _reminderTimeOptions.length * 100;
    _reminderTimeController = FixedExtentScrollController(
      initialItem: initialItem,
    );
  }

  @override
  void dispose() {
    _reminderTimeController.dispose();
    super.dispose();
  }

  Future<void> _loadReminderSettings() async {
    final enabled = await CourseService.instance.loadReminderEnabled(
      widget.scheduleId,
    );
    final time = await CourseService.instance.loadReminderTime(
      widget.scheduleId,
    );
    final method = await CourseService.instance.loadReminderMethod(
      widget.scheduleId,
    );
    final vibrationEnabled = await CourseService.instance.loadReminderVibration(
      widget.scheduleId,
    );
    if (mounted) {
      setState(() {
        _isReminderMethodEnabled = enabled;
        _reminderTime = time;
        _reminderMethod = method;
        _reminderVibrationEnabled = vibrationEnabled;

        // 更新控制器位置
        _reminderTimeController.dispose();
        int index = _reminderTimeOptions.indexOf(_reminderTime);
        if (index == -1) index = 3;
        final int initialItem = index + _reminderTimeOptions.length * 100;
        _reminderTimeController = FixedExtentScrollController(
          initialItem: initialItem,
        );

        // 清除脏标记，确保首次加载不触发保存
        _hasReminderChanged = false;
      });

      // 延迟启用动画，避免进入页面时的展开动画
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _enableAnimation = true;
          });
        }
      });
    }
  }

  Future<void> _requestCourseWidgetPin() async {
    if (!Platform.isAndroid || _isRequestingDesktopWidget) {
      return;
    }

    setState(() {
      _isRequestingDesktopWidget = true;
    });

    try {
      final dynamic nativeResponse = await _homeWidgetChannel
          .invokeMethod<dynamic>('requestPinCourseScheduleWidget');
      final pinResult = _NativePinRequestResult.fromNative(nativeResponse);
      if (!mounted) {
        return;
      }

      if (pinResult.requestAccepted) {
        if (!pinResult.launchedHomeAfterRequest) {
          AppToast.show(
            context,
            pinResult.usedCallback
                ? '系统添加请求已发起，请在系统弹窗中确认添加课表组件。'
                : '系统已接收添加请求，请按桌面提示完成课表组件添加。',
            variant: AppToastVariant.success,
          );
        }
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
          '当前桌面未弹出系统添加窗口，已返回桌面，请长按空白处手动添加课表组件。',
          AppToastVariant.info,
        ),
        _ when !pinResult.pinSupported || !pinResult.fallbackOpened => (
          '当前桌面暂不支持应用内自动添加，请长按桌面空白处手动添加课表组件。',
          AppToastVariant.warning,
        ),
        _ => ('当前桌面未响应系统添加请求，请长按桌面空白处手动添加课表组件。', AppToastVariant.warning),
      };
      AppToast.show(context, message, variant: variant);
    } on PlatformException {
      if (!mounted) {
        return;
      }
      AppToast.show(
        context,
        '课表组件添加请求失败，请稍后重试。',
        variant: AppToastVariant.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRequestingDesktopWidget = false;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant ScheduleSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.semesterStart != widget.semesterStart) {
      _semesterStart = widget.semesterStart;
    }
    if (oldWidget.currentWeek != widget.currentWeek) {
      _currentWeek = widget.currentWeek;
    }
    if (oldWidget.maxWeek != widget.maxWeek) {
      _maxWeek = widget.maxWeek;
    }
    if (oldWidget.showWeekend != widget.showWeekend) {
      _showWeekend = widget.showWeekend;
    }
    if (oldWidget.showNonCurrentWeek != widget.showNonCurrentWeek) {
      _showNonCurrentWeek = widget.showNonCurrentWeek;
    }
    if (oldWidget.isScheduleLocked != widget.isScheduleLocked) {
      _isScheduleLocked = widget.isScheduleLocked;
    }
    if (oldWidget.tableName != widget.tableName) {
      _tableName = widget.tableName;
    }
  }

  Future<void> _saveNotificationSettings() async {
    await CourseService.instance.saveAllReminderSettings(
      enabled: _isReminderMethodEnabled,
      time: _reminderTime,
      method: _reminderMethod,
      vibrationEnabled: _reminderVibrationEnabled,
      scheduleId: widget.scheduleId,
    );
  }

  Future<void> _loadColorAllocationAction() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _colorAllocationAction = prefs.getString(
          'course_color_exhausted_action',
        );
      });
    }
  }

  Future<void> _saveColorAllocationAction(String? action) async {
    final prefs = await SharedPreferences.getInstance();
    if (action == null) {
      await prefs.remove('course_color_exhausted_action');
    } else {
      await prefs.setString('course_color_exhausted_action', action);
    }
    if (mounted) {
      setState(() {
        _colorAllocationAction = action;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.header != null) ...[
          widget.header!,
          const SizedBox(height: 16),
        ],
        _buildGroup(
          children: [
            if (!widget.isEmbedded) ...[
              _buildTableNameTile(context),
              _buildDivider(),
            ],
            ExpandableItem(
              title: '学期开始时间',
              value: Text(
                DateFormat('yyyy年M月d日 EEEE', 'zh_CN').format(_semesterStart),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              isExpanded: _isStartDateExpanded,
              onTap: () {
                setState(() {
                  _isStartDateExpanded = !_isStartDateExpanded;
                  if (_isStartDateExpanded) {
                    _isMaxWeekExpanded = false;
                    _isColorAllocationExpanded = false;
                    _isReminderTimeExpanded = false;
                  }
                });
              },
              content: _buildCustomDatePicker(
                initialDate: _semesterStart,
                onChanged: (DateTime date) {
                  setState(() {
                    _semesterStart = date;
                  });
                  widget.onSemesterStartChanged(date);
                },
              ),
              showDivider: false,
            ),
            _buildDivider(),
            ExpandableItem(
              title: '学期总周数',
              value: Text(
                '$_maxWeek 周',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              isExpanded: _isMaxWeekExpanded,
              onTap: () {
                setState(() {
                  _isMaxWeekExpanded = !_isMaxWeekExpanded;
                  if (_isMaxWeekExpanded) {
                    _isStartDateExpanded = false;
                    _isColorAllocationExpanded = false;
                    _isReminderTimeExpanded = false;
                  }
                });
              },
              content: _buildNumberPicker(
                value: _maxWeek,
                min: 1,
                max: 30,
                looping: true,
                onChanged: (int value) {
                  setState(() {
                    _maxWeek = value;
                    if (_currentWeek > _maxWeek) {
                      _currentWeek = _maxWeek;
                      widget.onCurrentWeekChanged(_currentWeek);
                    }
                  });
                  widget.onMaxWeekChanged(value);
                },
                unit: '周',
              ),
              showDivider: false,
            ),
            _buildDivider(),
            _buildSwitchTile(
              title: '周末有课',
              value: _showWeekend,
              onChanged: (bool value) {
                setState(() {
                  _showWeekend = value;
                });
                widget.onShowWeekendChanged(value);
              },
            ),
            _buildDivider(),
            _buildTile(
              title: '课程时间设置',
              subtitle: '设置课程节数，调整每节课时间',
              onTap: widget.onOpenSectionSettings,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildGroup(
          children: [
            _buildSwitchTile(
              title: '显示非本周课程',
              value: _showNonCurrentWeek,
              onChanged: (bool value) {
                setState(() {
                  _showNonCurrentWeek = value;
                });
                widget.onShowNonCurrentWeekChanged(value);
              },
            ),
            _buildDivider(),
            _buildColorAllocationItem(),
          ],
        ),
        const SizedBox(height: 20),
        _buildGroup(
          children: [
            Column(
              children: [
                _buildSwitchTile(
                  title: '课程提醒',
                  subtitle: '暂时停用功能，等待后续版本修复',
                  value: _isReminderMethodEnabled,
                  // 已注释：暂时禁用课程提醒开关回调，界面仅展示灰色开关样式
                  // onChanged: (bool value) async {
                  //   setState(() {
                  //     _isReminderMethodEnabled = value;
                  //     if (!value) {
                  //       _isReminderTimeExpanded = false;
                  //     }
                  //     if (!widget.saveNotificationImmediately) {
                  //       _hasReminderChanged = true;
                  //     }
                  //   });
                  //   if (widget.saveNotificationImmediately) {
                  //     await CourseService.instance.saveReminderEnabled(
                  //       value,
                  //       widget.scheduleId,
                  //     );
                  //   }
                  // },
                  onChanged: null,
                ),
                AnimatedCrossFade(
                  firstChild: Container(),
                  secondChild: Column(
                    children: [
                      _buildReminderMethodSelector(),
                      _buildDivider(),
                      ExpandableItem(
                        title: '课程提醒时间',
                        value: Text(
                          _reminderTime == 0 ? '准时' : '$_reminderTime分钟前',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        isExpanded: _isReminderTimeExpanded,
                        onTap: () {
                          setState(() {
                            _isReminderTimeExpanded = !_isReminderTimeExpanded;
                            if (_isReminderTimeExpanded) {
                              _isStartDateExpanded = false;
                              _isMaxWeekExpanded = false;
                              _isColorAllocationExpanded = false;

                              // 每次展开时重置控制器位置，确保与当前值同步
                              int index = _reminderTimeOptions.indexOf(
                                _reminderTime,
                              );
                              if (index == -1) index = 3;
                              final int initialItem =
                                  index + _reminderTimeOptions.length * 100;
                              _reminderTimeController.dispose();
                              _reminderTimeController =
                                  FixedExtentScrollController(
                                    initialItem: initialItem,
                                  );
                            }
                          });
                        },
                        content: _buildReminderTimePicker(),
                        showDivider: false,
                      ),
                      if (_reminderMethod == 'notification') ...<Widget>[
                        _buildDivider(),
                        _buildSwitchTile(
                          title: '振动提醒',
                          subtitle: '通知提醒时配合横幅通知振动提醒',
                          value: _reminderVibrationEnabled,
                          onChanged: (bool value) async {
                            setState(() {
                              _reminderVibrationEnabled = value;
                              if (!widget.saveNotificationImmediately) {
                                _hasReminderChanged = true;
                              }
                            });
                            if (widget.saveNotificationImmediately) {
                              await CourseService.instance
                                  .saveReminderVibration(
                                    value,
                                    widget.scheduleId,
                                  );
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                  crossFadeState: _isReminderMethodEnabled
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: _enableAnimation
                      ? const Duration(milliseconds: 300)
                      : Duration.zero,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildGroup(
          children: [
            _buildSwitchTile(
              title: '启用日历显示',
              subtitle: '暂未接入功能，等待后续版本更新',
              value: _showInCalendar,
              // 禁用交互，展示为灰色
              onChanged: null,
            ),
            _buildDivider(),
            _buildTile(
              title: '添加桌面组件',
              subtitle: Platform.isAndroid
                  ? '点击后拉起系统添加课表组件弹窗'
                  : '仅支持 Android 桌面组件',
              onTap: Platform.isAndroid ? _requestCourseWidgetPin : null,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildGroup(
          children: [
            _buildSwitchTile(
              title: '锁定课程表',
              subtitle: '开启后课表卡片在课表页不允许拖动调整',
              value: _isScheduleLocked,
              onChanged: (bool value) {
                setState(() {
                  _isScheduleLocked = value;
                });
                widget.onScheduleLockedChanged?.call(value);
              },
            ),
          ],
        ),
        const SizedBox(height: 40),
      ],
    );

    if (widget.isEmbedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          '课程表设置',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: colorScheme.onSurface,
            size: 20,
          ),
          onPressed: () async {
            if (context.mounted) {
              // 返回按钮仅关闭页面，不提交当前设置。
              Navigator.pop(context, false);
            }
          },
        ),
        actions: [
          if (!widget.saveNotificationImmediately)
            TextButton(
              onPressed: () async {
                if (_hasReminderChanged) {
                  await _saveNotificationSettings();
                }
                _hasReminderChanged = false;
                if (context.mounted) {
                  // 仅在点击“完成”时提交设置并返回成功结果。
                  Navigator.pop(context, true);
                }
              },
              child: Text(
                '完成',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
          if (!widget.saveNotificationImmediately) const SizedBox(width: 8),
        ],
      ),
      body: content,
    );
  }

  Widget _buildReminderMethodSelector() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: Theme.of(context).cardTheme.color ?? colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          // 与课程颜色分配策略的轨道底色保持一致
          color: Theme.of(context).brightness == Brightness.dark
              ? colorScheme.surfaceContainer
              : colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double totalWidth = constraints.maxWidth;
            final double indicatorWidth = (totalWidth - 4) / 2;

            Alignment alignment = Alignment.centerLeft;
            if (_reminderMethod == 'alarm') {
              alignment = Alignment.centerRight;
            }

            return Stack(
              children: [
                AnimatedAlign(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.fastOutSlowIn,
                  alignment: alignment,
                  child: Container(
                    width: indicatorWidth,
                    height: 36,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      // 与课程颜色分配策略的滑块颜色保持一致
                      color: Theme.of(context).brightness == Brightness.dark
                          ? colorScheme.surfaceContainerHigh
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 1,
                          offset: const Offset(0, 1),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          setState(() => _reminderMethod = 'notification');
                          if (!widget.saveNotificationImmediately) {
                            _hasReminderChanged = true;
                          }
                          if (widget.saveNotificationImmediately) {
                            await CourseService.instance.saveReminderMethod(
                              'notification',
                              widget.scheduleId,
                            );
                          }
                        },
                        child: Center(
                          child: Text(
                            '通知提醒',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _reminderMethod == 'notification'
                                  ? colorScheme.onSurface
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          setState(() => _reminderMethod = 'alarm');
                          if (!widget.saveNotificationImmediately) {
                            _hasReminderChanged = true;
                          }
                          if (widget.saveNotificationImmediately) {
                            await CourseService.instance.saveReminderMethod(
                              'alarm',
                              widget.scheduleId,
                            );
                          }
                        },
                        child: Center(
                          child: Text(
                            '闹钟提醒',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _reminderMethod == 'alarm'
                                  ? colorScheme.onSurface
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildReminderTimePicker() {
    return Container(
      height: 150,
      color:
          Theme.of(context).cardTheme.color ??
          Theme.of(context).colorScheme.surface,
      child: CupertinoPicker(
        // 添加 Key 以强制重建，确保 initialItem 生效
        key: ValueKey(_reminderTimeController),
        scrollController: _reminderTimeController,
        selectionOverlay: Container(),
        itemExtent: 44,
        looping: true,
        onSelectedItemChanged: (index) async {
          final value =
              _reminderTimeOptions[index % _reminderTimeOptions.length];
          setState(() {
            _reminderTime = value;
            if (!widget.saveNotificationImmediately) {
              _hasReminderChanged = true;
            }
          });
          if (widget.saveNotificationImmediately) {
            await CourseService.instance.saveReminderTime(
              value,
              widget.scheduleId,
            );
          }
        },
        children: _reminderTimeOptions.map((e) {
          return Center(
            child: Text(
              e == 0 ? '准时' : '$e 分钟',
              style: const TextStyle(fontSize: 24),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildColorAllocationItem() {
    String valueText = '每次询问';
    if (_colorAllocationAction == 'reuse') valueText = '智能复用';
    if (_colorAllocationAction == 'new') valueText = '自动新增';

    return ExpandableItem(
      title: '课程颜色分配策略',
      value: Text(
        valueText,
        style: TextStyle(
          fontSize: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      isExpanded: _isColorAllocationExpanded,
      onTap: () {
        setState(() {
          _isColorAllocationExpanded = !_isColorAllocationExpanded;
          if (_isColorAllocationExpanded) {
            _isStartDateExpanded = false;
            _isMaxWeekExpanded = false;
            _isReminderTimeExpanded = false;
          }
        });
      },
      content: _buildColorAllocationSelector(),
      showDivider: false,
    );
  }

  Widget _buildColorAllocationSelector() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: Theme.of(context).cardTheme.color ?? colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          // 轨道底色：白天更白，夜间比 card 略深以形成对比
          color: Theme.of(context).brightness == Brightness.dark
              ? colorScheme.surfaceContainer
              : colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          // 添加边框以增强在暗色模式下的辨识度
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double totalWidth = constraints.maxWidth;
            final double indicatorWidth = (totalWidth - 4) / 3;

            Alignment alignment = Alignment.center;
            if (_colorAllocationAction == 'reuse') {
              alignment = Alignment.centerLeft;
            } else if (_colorAllocationAction == 'new') {
              alignment = Alignment.centerRight;
            }

            return Stack(
              children: [
                AnimatedAlign(
                  alignment: alignment,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.fastOutSlowIn,
                  child: Container(
                    width: indicatorWidth,
                    height: 36,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      // 白天白色，夜间用 card 底色（surfaceContainerHigh）
                      color: Theme.of(context).brightness == Brightness.dark
                          ? colorScheme.surfaceContainerHigh
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 1,
                          offset: const Offset(0, 1),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    _buildSelectorOption('智能复用', 'reuse'),
                    _buildSelectorOption('每次询问', null),
                    _buildSelectorOption('自动新增', 'new'),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSelectorOption(String label, String? value) {
    final bool isSelected = _colorAllocationAction == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _saveColorAllocationAction(value),
        behavior: HitTestBehavior.translucent,
        child: Container(
          alignment: Alignment.center,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }

  /// 构建设置项分组容器
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

  /// 构建分组内的分割线
  Widget _buildDivider() {
    return Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
    );
  }

  /// 构建通用的设置项列表行
  Widget _buildTile({
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: colorScheme.onSurface.withValues(alpha: 0.26),
              ),
          ],
        ),
      ),
    );
  }

  /// 将连续英文/数字长串插入零宽断点，避免无法自然换行。
  String _injectSoftBreakForAlphaNumeric(String text) {
    return text.replaceAllMapped(RegExp(r'[A-Za-z0-9_]{8,}'), (Match match) {
      final String token = match.group(0)!;
      return token.split('').join('\u200B');
    });
  }

  /// 按可用宽度和字符长度动态缩小字号，保证右侧课程表名尽量完整显示。
  double _resolveAdaptiveNameFontSize({
    required int charCount,
    required double maxWidth,
  }) {
    double size = 14;
    if (maxWidth < 220 || charCount > 12) {
      size = 13;
    }
    if (maxWidth < 180 || charCount > 18) {
      size = 12;
    }
    if (maxWidth < 150 || charCount > 24) {
      size = 11;
    }
    return size;
  }

  /// 专用课程表名称行：左侧标签不换行，右侧名称自适应换行与字号。
  Widget _buildTableNameTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final String rawText = _tableName.trim().isEmpty
        ? '课程表名称'
        : _tableName.trim();
    final String displayText = _injectSoftBreakForAlphaNumeric(rawText);
    final int nameChars = rawText.runes.length;

    return GestureDetector(
      onTap: () => _showEditNameDialog(context),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 88,
              child: Text(
                '课程表名称',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                            final double fontSize =
                                _resolveAdaptiveNameFontSize(
                                  charCount: nameChars,
                                  maxWidth: constraints.maxWidth,
                                );
                            return Text(
                              displayText,
                              textAlign: TextAlign.right,
                              softWrap: true,
                              overflow: TextOverflow.visible,
                              style: TextStyle(
                                fontSize: fontSize,
                                height: 1.2,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            );
                          },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: colorScheme.onSurface.withValues(alpha: 0.26),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建带有开关的设置项
  Widget _buildSwitchTile({
    required String title,
    String? subtitle,
    required bool value,
    ValueChanged<bool>? onChanged,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool disabled = onChanged == null && onTap == null;
    final ValueChanged<bool>? switchHandler =
        onChanged ?? (onTap != null ? (_) => onTap() : null);
    final VoidCallback? tileHandler =
        onTap ?? (onChanged != null ? () => onChanged(!value) : null);
    return GestureDetector(
      onTap: tileHandler,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      color: disabled
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: disabled
                            ? colorScheme.onSurfaceVariant
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Switch(value: value, onChanged: switchHandler),
          ],
        ),
      ),
    );
  }

  /// 构建数字选择器（用于选择周数）
  Widget _buildNumberPicker({
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
    String unit = '',
    bool looping = false,
    int step = 1,
  }) {
    final int itemCount = ((max - min) / step).floor() + 1;
    return Container(
      height: 150,
      color:
          Theme.of(context).cardTheme.color ??
          Theme.of(context).colorScheme.surface,
      child: CupertinoPicker(
        looping: looping,
        selectionOverlay: Container(),
        itemExtent: 44,
        scrollController: FixedExtentScrollController(
          initialItem: (() {
            final int baseIndex = ((value - min) / step).floor();
            if (looping) {
              // 将初始位置设置到中央偏移，避免用户滑到起始边界
              final int centerOffset = itemCount * 100;
              return centerOffset + baseIndex;
            }
            return baseIndex;
          })(),
        ),
        onSelectedItemChanged: (index) =>
            onChanged(min + (index % itemCount) * step),
        children: List.generate(itemCount, (index) {
          return Center(
            child: Text(
              '${min + index * step} $unit',
              style: const TextStyle(fontSize: 24),
            ),
          );
        }),
      ),
    );
  }

  /// 显示修改课程表名称的对话框
  Future<void> _showEditNameDialog(BuildContext context) async {
    // 保留原名称为可编辑初始值，便于直接增删改。
    final String? name = await showDialog<String>(
      context: context,
      builder: (_) {
        return _ScheduleTableNameEditorDialog(
          initialValue: _tableName,
          hintText: _tableName.trim().isEmpty ? '课程表名称' : _tableName,
          maxLengthUnits: _tableNameMaxLengthUnits,
          duplicateValue: _tableName,
          nameValidator: widget.nameValidator,
        );
      },
    );
    if (name == null) {
      return;
    }
    widget.onTableNameChanged(name);
    if (!mounted) {
      return;
    }
    setState(() {
      _tableName = name;
    });
  }

  /// 构建自定义的日期选择器（年/月/日）
  Widget _buildCustomDatePicker({
    required DateTime initialDate,
    required ValueChanged<DateTime> onChanged,
  }) {
    final int currentYear = DateTime.now().year;
    final int minYear = currentYear - 5;
    final int maxYear = currentYear + 5;
    final List<int> years = List.generate(
      maxYear - minYear + 1,
      (i) => minYear + i,
    );
    final List<int> months = List.generate(12, (i) => i + 1);

    int daysInMonth = DateTime(initialDate.year, initialDate.month + 1, 0).day;
    final List<int> days = List.generate(daysInMonth, (i) => i + 1);

    return Container(
      height: 200,
      color:
          Theme.of(context).cardTheme.color ??
          Theme.of(context).colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 以月份居中，左右间隔固定，且保证文字完整显示
          final double gap = 0.0; // 列间间距

          final double minYearWidth = kMinYearWidth; // 年份最小宽度
          final double minMonthWidth = kMinMonthWidth; // 月份最小宽度
          final double minDayWidth = kMinDayWidth; // 日期最小宽度

          final double totalMin = minYearWidth + minMonthWidth + minDayWidth;
          double yearWidth = minYearWidth;
          double monthWidth = minMonthWidth;
          double dayWidth = minDayWidth;

          // 如果屏幕过窄，按比例缩放
          if (constraints.maxWidth < totalMin) {
            final double scale = constraints.maxWidth / totalMin;
            yearWidth = max(24.0, minYearWidth * scale);
            monthWidth = max(24.0, minMonthWidth * scale);
            dayWidth = max(24.0, minDayWidth * scale);
          }

          // 计算左边距，使 Month 列的中心对齐屏幕中心
          // 屏幕中心 = 左边距 + 年宽 + 间距 + 月宽 / 2
          double leftPadding =
              (constraints.maxWidth / 2) - yearWidth - gap - (monthWidth / 2);
          if (leftPadding < 0) leftPadding = 0;

          final double innerGap = gap / 2;
          // 构建行布局
          return Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(width: leftPadding),
              // 给每列内部也加左右 padding，使文字不贴边
              SizedBox(
                width: yearWidth,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: innerGap),
                  child: CupertinoPicker(
                    selectionOverlay: Container(),
                    itemExtent: kPickerItemExtent,
                    looping: true,
                    scrollController: FixedExtentScrollController(
                      initialItem: (() {
                        final idx = years.indexWhere(
                          (y) => y == initialDate.year,
                        );
                        return idx != -1 ? idx : 0;
                      })(),
                    ),
                    onSelectedItemChanged: (index) {
                      final newYear = years[index % years.length];
                      final daysInNewMonth = DateTime(
                        newYear,
                        initialDate.month + 1,
                        0,
                      ).day;
                      final newDay = initialDate.day > daysInNewMonth
                          ? daysInNewMonth
                          : initialDate.day;
                      onChanged(DateTime(newYear, initialDate.month, newDay));
                    },
                    children: years
                        .map(
                          (y) => Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '$y年',
                                style: const TextStyle(
                                  fontSize: kPickerFontSizeDefault,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              SizedBox(width: gap),
              SizedBox(
                width: monthWidth,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: innerGap),
                  child: CupertinoPicker(
                    selectionOverlay: Container(),
                    itemExtent: kPickerItemExtent,
                    looping: true,
                    scrollController: FixedExtentScrollController(
                      initialItem: initialDate.month - 1,
                    ),
                    onSelectedItemChanged: (index) {
                      final newMonth = (index % 12) + 1;
                      final daysInNewMonth = DateTime(
                        initialDate.year,
                        newMonth + 1,
                        0,
                      ).day;
                      final newDay = initialDate.day > daysInNewMonth
                          ? daysInNewMonth
                          : initialDate.day;
                      onChanged(DateTime(initialDate.year, newMonth, newDay));
                    },
                    children: months
                        .map(
                          (m) => SizedBox(
                            width: double.infinity,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _getMonthString(m),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: kPickerFontSizeDefault,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              SizedBox(width: gap),
              SizedBox(
                width: dayWidth,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: innerGap),
                  child: CupertinoPicker(
                    selectionOverlay: Container(),
                    itemExtent: kPickerItemExtent,
                    looping: true,
                    scrollController: FixedExtentScrollController(
                      initialItem: initialDate.day - 1,
                    ),
                    onSelectedItemChanged: (index) {
                      final newDay = (index % daysInMonth) + 1;
                      onChanged(
                        DateTime(initialDate.year, initialDate.month, newDay),
                      );
                    },
                    children: days
                        .map(
                          (d) => SizedBox(
                            width: double.infinity,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '$d日',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: kPickerFontSizeDefault,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 获取月份的中文显示字符串
  String _getMonthString(int month) {
    const months = [
      '1月',
      '2月',
      '3月',
      '4月',
      '5月',
      '6月',
      '7月',
      '8月',
      '9月',
      '10月',
      '11月',
      '12月',
    ];
    return months[month - 1];
  }
}

/// 课程表名称编辑弹窗。
///
/// 交互对齐“修改昵称”：空输入提示、超限计数提示、校验失败文字抖动与震动反馈。
class _ScheduleTableNameEditorDialog extends StatefulWidget {
  const _ScheduleTableNameEditorDialog({
    required this.initialValue,
    required this.hintText,
    required this.maxLengthUnits,
    required this.duplicateValue,
    this.nameValidator,
  });

  final String initialValue;
  final String hintText;
  final int maxLengthUnits;
  final String duplicateValue;
  final Future<String?> Function(String)? nameValidator;

  @override
  State<_ScheduleTableNameEditorDialog> createState() =>
      _ScheduleTableNameEditorDialogState();
}

class _ScheduleTableNameEditorDialogState
    extends State<_ScheduleTableNameEditorDialog>
    with TickerProviderStateMixin {
  late final TextEditingController _controller;
  late final AnimationController _errorShakeController;
  late final Animation<double> _errorShakeOffset;

  String? _errorText;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _errorShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _errorShakeOffset = _buildShakeOffset(_errorShakeController);
  }

  @override
  void dispose() {
    _errorShakeController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _buildShakeOffset(AnimationController controller) {
    return TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0, end: -7),
        weight: 1,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: -7, end: 7),
        weight: 1,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 7, end: -5),
        weight: 1,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: -5, end: 5),
        weight: 1,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 5, end: 0),
        weight: 1,
      ),
    ]).animate(CurvedAnimation(parent: controller, curve: Curves.easeOut));
  }

  int _currentLengthUnits() {
    return TextLengthCounter.computeHalfWidthUnits(_controller.text);
  }

  bool _isLengthExceeded() {
    return _currentLengthUnits() > widget.maxLengthUnits;
  }

  String _counterText() {
    return '${_currentLengthUnits()}/${widget.maxLengthUnits}';
  }

  Widget _buildCounter(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color counterColor = _isLengthExceeded()
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Text(
      _counterText(),
      style: theme.textTheme.bodySmall?.copyWith(color: counterColor),
    );
  }

  Widget? _buildAnimatedErrorText(BuildContext context) {
    if (_errorText == null) {
      return null;
    }
    final Color errorColor = Theme.of(context).colorScheme.error;
    return AnimatedBuilder(
      animation: _errorShakeController,
      builder: (_, Widget? child) {
        return Transform.translate(
          offset: Offset(_errorShakeOffset.value, 0),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          _errorText!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: errorColor),
        ),
      ),
    );
  }

  Future<void> _playValidationErrorFeedback({bool withHaptic = true}) async {
    // 空值/重名/重名校验失败时抖动错误文本并震动。
    if (withHaptic) {
      await HapticFeedback.mediumImpact();
    }
    if (!mounted) {
      return;
    }
    _errorShakeController.forward(from: 0);
  }

  Future<void> _onSubmit() async {
    if (_isSaving) {
      return;
    }
    final String value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() {
        _errorText = '课程表名称不能为空！';
      });
      await _playValidationErrorFeedback();
      return;
    }
    if (value.toLowerCase() == widget.duplicateValue.trim().toLowerCase()) {
      setState(() {
        _errorText = '与原课程表名称相同！';
      });
      await _playValidationErrorFeedback();
      return;
    }
    if (_isLengthExceeded()) {
      setState(() {
        _errorText = '课程表名称超出字数限制！';
      });
      // 超限错误与重名错误一致：错误文案抖动 + 手机震动。
      await _playValidationErrorFeedback();
      return;
    }
    if (widget.nameValidator != null) {
      setState(() {
        _isSaving = true;
      });
      final String? error = await widget.nameValidator!(value);
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
      });
      if (error != null) {
        setState(() {
          _errorText = error;
        });
        await _playValidationErrorFeedback();
        return;
      }
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget? animatedErrorText = _buildAnimatedErrorText(context);
    return AlertDialog(
      backgroundColor: theme.cardTheme.color ?? theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: const Text('修改课程表名称'),
      content: SizedBox(
        // 放宽输入区宽度，减少中文课程名在小屏设备的换行概率。
        width: min(MediaQuery.sizeOf(context).width * 0.82, 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 1,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _onSubmit(),
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() {
                    _errorText = null;
                  });
                } else {
                  setState(() {});
                }
              },
              decoration: InputDecoration(
                // 输入框为空时显示旧课程表名，便于用户参考后修改。
                hintText: widget.hintText,
                hintMaxLines: 1,
                hintStyle: const TextStyle(color: Color(0xFF8A8E99)),
                counterText: '',
                counter: _buildCounter(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: theme.primaryColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: theme.primaryColor, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
            ),
            if (animatedErrorText != null) animatedErrorText,
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _onSubmit,
          child: Text(_isSaving ? '校验中...' : '保存'),
        ),
      ],
    );
  }
}
