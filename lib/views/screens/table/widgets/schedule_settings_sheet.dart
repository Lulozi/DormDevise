import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'package:dormdevise/utils/index.dart';
import 'package:dormdevise/utils/app_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/course_schedule_config.dart';
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
  });

  @override
  State<ScheduleSettingsPage> createState() => _ScheduleSettingsPageState();
}

class _ScheduleSettingsPageState extends State<ScheduleSettingsPage> {
  // 展开状态
  bool _isStartDateExpanded = false;
  bool _isMaxWeekExpanded = false;
  bool _isColorAllocationExpanded = false;

  // 用于实时更新的本地状态
  late DateTime _semesterStart;
  late int _currentWeek;
  late int _maxWeek;
  late bool _showWeekend;
  late bool _showNonCurrentWeek;
  late String _tableName;
  String? _colorAllocationAction;

  @override
  void initState() {
    super.initState();
    _semesterStart = widget.semesterStart;
    _currentWeek = widget.currentWeek;
    _maxWeek = widget.maxWeek;
    _showWeekend = widget.showWeekend;
    _showNonCurrentWeek = widget.showNonCurrentWeek;
    _tableName = widget.tableName;
    _loadColorAllocationAction();
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
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
              isExpanded: _isStartDateExpanded,
              onTap: () {
                setState(() {
                  _isStartDateExpanded = !_isStartDateExpanded;
                  _isMaxWeekExpanded = false;
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
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
              isExpanded: _isMaxWeekExpanded,
              onTap: () {
                setState(() {
                  _isMaxWeekExpanded = !_isMaxWeekExpanded;
                  _isStartDateExpanded = false;
                });
              },
              content: _buildNumberPicker(
                value: _maxWeek,
                min: 1,
                max: 30,
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
            _buildTile(
              title: '课程提醒时间',
              trailing: _buildTrailingText('15分钟前'),
              onTap: () {},
            ),
            _buildDivider(),
            _buildTile(
              title: '课程提醒方式',
              trailing: _buildTrailingText('通知提醒'),
              onTap: () {},
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

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: const Text(
          '课程表设置',
          style: TextStyle(
            color: Colors.black,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: const Color(0xFFF7F8FC),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.black,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: content,
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
        style: const TextStyle(fontSize: 14, color: Colors.black54),
      ),
      isExpanded: _isColorAllocationExpanded,
      onTap: () {
        setState(() {
          _isColorAllocationExpanded = !_isColorAllocationExpanded;
          if (_isColorAllocationExpanded) {
            _isStartDateExpanded = false;
            _isMaxWeekExpanded = false;
          }
        });
      },
      content: _buildColorAllocationSelector(),
      showDivider: false,
    );
  }

  Widget _buildColorAllocationSelector() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(12),
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
                    height: 32,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white,
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
              color: Colors.black,
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
        color: Colors.white,
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
    return const Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: Color(0xFFF0F0F0),
    );
  }

  /// 构建通用的设置项列表行
  Widget _buildTile({
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
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
                    style: const TextStyle(fontSize: 16, color: Colors.black87),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else
              const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.black26,
              ),
          ],
        ),
      ),
    );
  }

  /// 构建列表行尾部的文本和箭头
  Widget _buildTrailingText(String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: const TextStyle(fontSize: 14, color: Colors.black54)),
        const SizedBox(width: 8),
        const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.black26),
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
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: Theme.of(context).primaryColor,
          ),
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
  }) {
    return Container(
      height: 150,
      color: Colors.white,
      child: CupertinoPicker(
        selectionOverlay: Container(),
        itemExtent: 44,
        scrollController: FixedExtentScrollController(initialItem: value - min),
        onSelectedItemChanged: (index) => onChanged(min + index),
        children: List.generate(max - min + 1, (index) {
          return Center(
            child: Text(
              '${min + index} $unit',
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
              backgroundColor: Colors.white,
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
    final int minYear = DateTime.now().year - 5;
    final int maxYear = DateTime.now().year + 5;
    final List<int> years = List.generate(
      maxYear - minYear + 1,
      (i) => minYear + i,
    );
    final List<int> months = List.generate(12, (i) => i + 1);

    int daysInMonth = DateTime(initialDate.year, initialDate.month + 1, 0).day;
    final List<int> days = List.generate(daysInMonth, (i) => i + 1);

    return Container(
      height: 200,
      color: Colors.white,
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
                    scrollController: FixedExtentScrollController(
                      initialItem: (() {
                        final idx = years.indexWhere(
                          (y) => y == initialDate.year,
                        );
                        return idx != -1 ? idx : 0;
                      })(),
                    ),
                    onSelectedItemChanged: (index) {
                      final newYear = years[index];
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
                    scrollController: FixedExtentScrollController(
                      initialItem: initialDate.month - 1,
                    ),
                    onSelectedItemChanged: (index) {
                      final newMonth = index + 1;
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
                    scrollController: FixedExtentScrollController(
                      initialItem: initialDate.day - 1,
                    ),
                    onSelectedItemChanged: (index) {
                      onChanged(
                        DateTime(
                          initialDate.year,
                          initialDate.month,
                          index + 1,
                        ),
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
