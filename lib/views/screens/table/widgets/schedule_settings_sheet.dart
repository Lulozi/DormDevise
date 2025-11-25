import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../models/course_schedule_config.dart';

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
  });

  @override
  State<ScheduleSettingsPage> createState() => _ScheduleSettingsPageState();
}

class _ScheduleSettingsPageState extends State<ScheduleSettingsPage> {
  // 展开状态
  bool _isStartDateExpanded = false;
  bool _isMaxWeekExpanded = false;

  // 用于实时更新的本地状态
  late DateTime _semesterStart;
  late int _currentWeek;
  late int _maxWeek;
  late bool _showWeekend;
  late bool _showNonCurrentWeek;

  @override
  void initState() {
    super.initState();
    _semesterStart = widget.semesterStart;
    _currentWeek = widget.currentWeek;
    _maxWeek = widget.maxWeek;
    _showWeekend = widget.showWeekend;
    _showNonCurrentWeek = widget.showNonCurrentWeek;
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7), // iOS 分组背景色
      appBar: AppBar(
        title: const Text(
          '课程表设置',
          style: TextStyle(
            color: Colors.black,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.white,
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildGroup(
            children: [
              _buildTile(
                title: '课程表名称',
                trailing: _buildTrailingText(widget.tableName),
                onTap: () => _showEditNameDialog(context),
              ),
              _buildDivider(),
              _buildExpandablePickerTile(
                title: '学期开始时间',
                valueText: DateFormat(
                  'yyyy年M月d日 EEEE',
                  'zh_CN',
                ).format(_semesterStart),
                isExpanded: _isStartDateExpanded,
                onTap: () {
                  setState(() {
                    _isStartDateExpanded = !_isStartDateExpanded;
                    _isMaxWeekExpanded = false;
                  });
                },
                picker: Container(
                  height: 200,
                  color: Colors.white,
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: _semesterStart,
                    onDateTimeChanged: (DateTime date) {
                      setState(() {
                        _semesterStart = date;
                      });
                      widget.onSemesterStartChanged(date);
                    },
                    use24hFormat: true,
                    dateOrder: DatePickerDateOrder.ymd,
                  ),
                ),
              ),
              _buildDivider(),
              _buildExpandablePickerTile(
                title: '学期总周数',
                subtitle: '请选择学期共多少周',
                valueText: '$_maxWeek 周',
                isExpanded: _isMaxWeekExpanded,
                onTap: () {
                  setState(() {
                    _isMaxWeekExpanded = !_isMaxWeekExpanded;
                    _isStartDateExpanded = false;
                  });
                },
                picker: _buildNumberPicker(
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
      ),
    );
  }

  Widget _buildGroup({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: Color(0xFFF0F0F0),
    );
  }

  Widget _buildTile({
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
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

  Widget _buildExpandablePickerTile({
    required String title,
    String? subtitle,
    required String valueText,
    required bool isExpanded,
    required VoidCallback onTap,
    required Widget picker,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
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
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                        ),
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
                Text(
                  valueText,
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(width: 8),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                  color: Colors.black26,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: Container(),
          secondChild: picker,
          crossFadeState: isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 300),
        ),
      ],
    );
  }

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
        itemExtent: 32,
        scrollController: FixedExtentScrollController(initialItem: value - min),
        onSelectedItemChanged: (index) => onChanged(min + index),
        children: List.generate(max - min + 1, (index) {
          return Center(
            child: Text(
              '${min + index} $unit',
              style: const TextStyle(fontSize: 16),
            ),
          );
        }),
      ),
    );
  }

  void _showEditNameDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController(
      text: widget.tableName,
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFFEEEFF5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: const Text('修改课程表名称', style: TextStyle(fontSize: 20)),
          content: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                labelText: '课程表名称',
                prefixIcon: const Icon(Icons.edit_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Theme.of(context).primaryColor),
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
              child: const Text('确定'),
              onPressed: () {
                widget.onTableNameChanged(controller.text);
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }
}
