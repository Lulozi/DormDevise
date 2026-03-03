import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'package:dormdevise/utils/index.dart';
import 'package:dormdevise/utils/app_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/course_schedule_config.dart';
import '../../../../services/course_service.dart';
import 'expandable_item.dart';

/// 课程表设置页面，用于配置学期开始时间、周数、周末显示等全局设置。
class ScheduleSettingsPage extends StatefulWidget {
  final CourseScheduleConfig scheduleConfig;
  final DateTime semesterStart;
  final int currentWeek;
  final int maxWeek;
  final String tableName;
  final bool showWeekend;
  final bool showNonCurrentWeek;
  final ValueChanged<CourseScheduleConfig> onConfigChanged;
  final ValueChanged<DateTime> onSemesterStartChanged;
  final ValueChanged<int> onCurrentWeekChanged;
  final ValueChanged<int> onMaxWeekChanged;
  final ValueChanged<String> onTableNameChanged;
  final ValueChanged<bool> onShowWeekendChanged;
  final ValueChanged<bool> onShowNonCurrentWeekChanged;
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
    required this.onConfigChanged,
    required this.onSemesterStartChanged,
    required this.onCurrentWeekChanged,
    required this.onMaxWeekChanged,
    required this.onTableNameChanged,
    required this.onShowWeekendChanged,
    required this.onShowNonCurrentWeekChanged,
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
  late String _tableName;
  String? _colorAllocationAction;

  // 标记提醒设置是否有未保存的变更
  bool _hasReminderChanged = false;

  // 课程提醒相关状态
  int _reminderTime = 15;
  bool _isReminderMethodEnabled = false;
  String _reminderMethod = 'notification';
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
    if (mounted) {
      setState(() {
        _isReminderMethodEnabled = enabled;
        _reminderTime = time;
        _reminderMethod = method;

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
    if (oldWidget.tableName != widget.tableName) {
      _tableName = widget.tableName;
    }
  }

  Future<void> _saveNotificationSettings() async {
    await CourseService.instance.saveAllReminderSettings(
      enabled: _isReminderMethodEnabled,
      time: _reminderTime,
      method: _reminderMethod,
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
              _buildTile(
                title: '课程表名称',
                trailing: _buildTrailingText(_tableName),
                onTap: () => _showEditNameDialog(context),
              ),
              _buildDivider(),
            ],
            ExpandableItem(
              title: '学期开始时间',
              value: Text(
                DateFormat('yyyy年M月d日 EEEE', 'zh_CN').format(_semesterStart),
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
                  value: _isReminderMethodEnabled,
                  onChanged: (bool value) async {
                    setState(() {
                      _isReminderMethodEnabled = value;
                      if (!value) {
                        _isReminderTimeExpanded = false;
                      }
                      if (!widget.saveNotificationImmediately) {
                        _hasReminderChanged = true;
                      }
                    });
                    if (widget.saveNotificationImmediately) {
                      await CourseService.instance.saveReminderEnabled(
                        value,
                        widget.scheduleId,
                      );
                    }
                  },
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
              title: '在日历和组件中显示',
              subtitle: '课程将以日程形式在日历及组件中显示',
              value: false,
              onChanged: (v) {},
            ),
          ],
        ),
        const SizedBox(height: 40),
      ],
    );

    if (widget.isEmbedded) {
      return content;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          return;
        }
        if (!widget.saveNotificationImmediately && _hasReminderChanged) {
          await _saveNotificationSettings();
          _hasReminderChanged = false;
        }
        if (context.mounted) {
          Navigator.of(context).pop(result);
        }
      },
      child: Scaffold(
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
              if (!widget.saveNotificationImmediately && _hasReminderChanged) {
                await _saveNotificationSettings();
                _hasReminderChanged = false;
              }
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
          actions: [
            if (!widget.saveNotificationImmediately)
              TextButton(
                onPressed: () async {
                  await _saveNotificationSettings();
                  _hasReminderChanged = false;
                  if (context.mounted) {
                    Navigator.pop(context);
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
      ),
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

  /// 构建列表行尾部的文本和箭头
  Widget _buildTrailingText(String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: colorScheme.onSurface.withValues(alpha: 0.26),
        ),
      ],
    );
  }

  /// 构建带有开关的设置项
  Widget _buildSwitchTile({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
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
          Switch(value: value, onChanged: onChanged),
        ],
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
  void _showEditNameDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController(
      text: _tableName,
    );
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final bool isEnabled = controller.text.trim().isNotEmpty;
            return AlertDialog(
              backgroundColor:
                  Theme.of(context).cardTheme.color ??
                  Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              title: const Text('', style: TextStyle(fontSize: 10)),
              content: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(fontSize: 16),
                  onChanged: (value) {
                    setDialogState(() {});
                  },
                  decoration: InputDecoration(
                    labelText: '课程表名称',
                    prefixIcon: const Icon(Icons.edit_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: Theme.of(context).primaryColor,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('取消'),
                  onPressed: () => Navigator.pop(context),
                ),
                TextButton(
                  onPressed: isEnabled
                      ? () async {
                          final name = controller.text.trim();
                          if (widget.nameValidator != null) {
                            final error = await widget.nameValidator!(name);
                            if (error != null) {
                              if (context.mounted) {
                                AppToast.show(context, error);
                              }
                              return;
                            }
                          }
                          widget.onTableNameChanged(name);
                          setState(() {
                            _tableName = name;
                          });
                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        }
                      : null,
                  child: Text(
                    '确定',
                    style: TextStyle(
                      color: isEnabled
                          ? Theme.of(context).primaryColor
                          : Colors.grey,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
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
                          (m) => Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _getMonthString(m),
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
                          (d) => Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '$d日',
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
