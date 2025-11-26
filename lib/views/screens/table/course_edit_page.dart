import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../models/course.dart';
import 'widgets/expandable_item.dart';

class CourseEditPage extends StatefulWidget {
  final Course? course; // If null, we are adding a new course
  final int? initialWeekday;
  final int? initialSection;
  final int maxWeek;

  const CourseEditPage({
    super.key,
    this.course,
    this.initialWeekday,
    this.initialSection,
    this.maxWeek = 20,
  });

  @override
  State<CourseEditPage> createState() => _CourseEditPageState();
}

class _CourseEditPageState extends State<CourseEditPage> {
  late TextEditingController _nameController;
  late TextEditingController _teacherController;
  late TextEditingController _classroomController;
  late Color _selectedColor;
  late List<CourseSession> _sessions;

  // Global week settings
  int _startWeek = 1;
  late int _endWeek;
  CourseWeekType _weekType = CourseWeekType.all;

  int? _expandedSessionIndex;

  final List<Color> _presetColors = [
    const Color(0xFFE57373),
    const Color(0xFFF06292),
    const Color(0xFFBA68C8),
    const Color(0xFF9575CD),
    const Color(0xFF7986CB),
    const Color(0xFF64B5F6),
    const Color(0xFF4FC3F7),
    const Color(0xFF4DD0E1),
    const Color(0xFF4DB6AC),
    const Color(0xFF81C784),
    const Color(0xFFAED581),
    const Color(0xFFFFD54F),
    const Color(0xFFFFB74D),
    const Color(0xFFFF8A65),
    const Color(0xFFA1887F),
  ];

  @override
  void initState() {
    super.initState();
    _endWeek = widget.maxWeek;
    _nameController = TextEditingController(text: widget.course?.name ?? '');
    _teacherController = TextEditingController(
      text: widget.course?.teacher ?? '',
    );

    // Initialize classroom from the first session if available, or empty
    String initialLocation = '';
    if (widget.course != null && widget.course!.sessions.isNotEmpty) {
      initialLocation = widget.course!.sessions.first.location;
      _startWeek = widget.course!.sessions.first.startWeek;
      _endWeek = widget.course!.sessions.first.endWeek;
      _weekType = widget.course!.sessions.first.weekType;
    }
    _classroomController = TextEditingController(text: initialLocation);

    _selectedColor =
        widget.course?.color ??
        _presetColors[Random().nextInt(_presetColors.length)];
    _sessions = widget.course?.sessions.toList() ?? [];

    if (widget.course == null) {
      if (widget.initialWeekday != null && widget.initialSection != null) {
        _sessions.add(
          CourseSession(
            weekday: widget.initialWeekday!,
            startSection: widget.initialSection!,
            sectionCount: 2,
            location: '',
            startWeek: 1,
            endWeek: widget.maxWeek,
            weekType: CourseWeekType.all,
          ),
        );
      } else if (_sessions.isEmpty) {
        // Add a default session if none exists
        _sessions.add(
          CourseSession(
            weekday: 1,
            startSection: 1,
            sectionCount: 2,
            location: '',
            startWeek: 1,
            endWeek: widget.maxWeek,
            weekType: CourseWeekType.all,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _teacherController.dispose();
    _classroomController.dispose();
    super.dispose();
  }

  void _save() {
    if (_nameController.text.isEmpty) {
      // Show error or just return
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入课程名称')));
      return;
    }

    // Apply global settings to all sessions
    final updatedSessions = _sessions.map((s) {
      return CourseSession(
        weekday: s.weekday,
        startSection: s.startSection,
        sectionCount: s.sectionCount,
        location: _classroomController.text, // Apply global location
        startWeek: _startWeek, // Apply global start week
        endWeek: _endWeek, // Apply global end week
        weekType: _weekType, // Apply global week type
      );
    }).toList();

    final newCourse = Course(
      name: _nameController.text,
      teacher: _teacherController.text,
      color: _selectedColor,
      sessions: updatedSessions,
    );
    Navigator.of(context).pop(newCourse);
  }

  void _incrementSessions() {
    setState(() {
      _sessions.add(
        CourseSession(
          weekday: 1,
          startSection: 1,
          sectionCount: 2,
          location: _classroomController.text,
          startWeek: _startWeek,
          endWeek: _endWeek,
          weekType: _weekType,
        ),
      );
    });
  }

  void _decrementSessions() {
    if (_sessions.isNotEmpty) {
      setState(() {
        _sessions.removeLast();
      });
    }
  }

  Future<void> _pickWeeks() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _WeekRangePicker(
        initialStart: _startWeek,
        initialEnd: _endWeek,
        initialType: _weekType,
        maxWeek: widget.maxWeek,
      ),
    );

    if (result != null) {
      setState(() {
        _startWeek = result['start'] as int;
        _endWeek = result['end'] as int;
        _weekType = result['type'] as CourseWeekType;
      });
    }
  }

  Future<void> _pickColor() async {
    final result = await showModalBottomSheet<Color>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _ColorPickerSheet(
        selectedColor: _selectedColor,
        colors: _presetColors,
      ),
    );

    if (result != null) {
      setState(() {
        _selectedColor = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String weekText = '第 $_startWeek-$_endWeek 周';
    if (_weekType == CourseWeekType.single) {
      weekText += ' 单周';
    } else if (_weekType == CourseWeekType.double) {
      weekText += ' 双周';
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F8FC),
        elevation: 0,
        centerTitle: true,
        title: Text(
          widget.course == null ? '新建课程' : '编辑课程',
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
        ),
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '取消',
            style: TextStyle(fontSize: 16, color: Colors.blue),
          ),
        ),
        leadingWidth: 70,
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              '完成',
              style: TextStyle(
                fontSize: 16,
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildInputGroup(
            label: '课程名',
            controller: _nameController,
            placeholder: '必填',
            isLast: false,
          ),
          const SizedBox(height: 12),
          _buildInputGroup(
            label: '教室',
            controller: _classroomController,
            placeholder: '非必填',
            isLast: false,
          ),
          const SizedBox(height: 12),
          _buildInputGroup(
            label: '备注（如老师）',
            controller: _teacherController,
            placeholder: '非必填',
            isLast: true,
          ),
          const SizedBox(height: 24),
          _buildTimeSlotsSection(),
          const SizedBox(height: 24),
          _buildSelectionItem(
            label: '上课周数',
            value: weekText,
            onTap: _pickWeeks,
          ),
          const SizedBox(height: 12),
          _buildColorItem(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildInputGroup({
    required String label,
    required TextEditingController controller,
    required String placeholder,
    required bool isLast,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              textAlign: TextAlign.left,
              decoration: InputDecoration(
                hintText: placeholder,
                hintStyle: const TextStyle(color: Color(0xFFC4C4C6)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              style: const TextStyle(fontSize: 16, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSlotsSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '时段',
                  style: TextStyle(fontSize: 16, color: Colors.black87),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildCounterButton(
                        icon: Icons.remove,
                        onTap: _decrementSessions,
                      ),
                      SizedBox(
                        width: 30,
                        child: Text(
                          '${_sessions.length}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      _buildCounterButton(
                        icon: Icons.add,
                        onTap: _incrementSessions,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_sessions.isNotEmpty)
            const Divider(height: 1, indent: 16, color: Color(0xFFE5E5EA)),
          ..._sessions.asMap().entries.map((entry) {
            final index = entry.key;
            final session = entry.value;
            final isLast = index == _sessions.length - 1;
            final isExpanded = _expandedSessionIndex == index;

            String timeText = '周${_weekdayToString(session.weekday)} ';
            if (session.sectionCount == 1) {
              timeText += '第 ${session.startSection} 节';
            } else {
              timeText +=
                  '第 ${session.startSection}-${session.startSection + session.sectionCount - 1} 节';
            }
            return ExpandableItem(
              title: '课程时间 ${index + 1}',
              value: Text(
                timeText,
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
              isExpanded: isExpanded,
              onTap: () {
                setState(() {
                  if (_expandedSessionIndex == index) {
                    _expandedSessionIndex = null;
                  } else {
                    _expandedSessionIndex = index;
                  }
                });
              },
              content: _buildInlineTimePicker(index),
              showDivider: !isLast,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInlineTimePicker(int index) {
    final session = _sessions[index];
    final endSection = session.startSection + session.sectionCount - 1;

    return Container(
      height: 150,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: CupertinoPicker(
              selectionOverlay: Container(),
              itemExtent: 32,
              scrollController: FixedExtentScrollController(
                initialItem: session.weekday - 1,
              ),
              onSelectedItemChanged: (newIndex) {
                setState(() {
                  _sessions[index] = CourseSession(
                    weekday: newIndex + 1,
                    startSection: session.startSection,
                    sectionCount: session.sectionCount,
                    location: session.location,
                    startWeek: session.startWeek,
                    endWeek: session.endWeek,
                    weekType: session.weekType,
                  );
                });
              },
              children: List.generate(
                7,
                (i) => Center(child: Text('周${_weekdayToString(i + 1)}')),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: CupertinoPicker(
              selectionOverlay: Container(),
              itemExtent: 32,
              scrollController: FixedExtentScrollController(
                initialItem: session.startSection - 1,
              ),
              onSelectedItemChanged: (newIndex) {
                final newStart = newIndex + 1;
                setState(() {
                  _sessions[index] = CourseSession(
                    weekday: session.weekday,
                    startSection: newStart,
                    sectionCount: session.sectionCount,
                    location: session.location,
                    startWeek: session.startWeek,
                    endWeek: session.endWeek,
                    weekType: session.weekType,
                  );
                });
              },
              children: List.generate(
                12,
                (i) => Center(child: Text('${i + 1}')),
              ),
            ),
          ),
          const Text('到'),
          Expanded(
            flex: 2,
            child: CupertinoPicker(
              selectionOverlay: Container(),
              itemExtent: 32,
              scrollController: FixedExtentScrollController(
                initialItem: endSection - 1,
              ),
              onSelectedItemChanged: (newIndex) {
                final newEnd = newIndex + 1;
                int newStart = session.startSection;
                int newCount;

                if (newEnd < newStart) {
                  newStart = newEnd;
                  newCount = 1;
                } else {
                  newCount = newEnd - newStart + 1;
                }

                setState(() {
                  _sessions[index] = CourseSession(
                    weekday: session.weekday,
                    startSection: newStart,
                    sectionCount: newCount,
                    location: session.location,
                    startWeek: session.startWeek,
                    endWeek: session.endWeek,
                    weekType: session.weekType,
                  );
                });
              },
              children: List.generate(
                12,
                (i) => Center(child: Text('${i + 1}')),
              ),
            ),
          ),
          const Text('节'),
        ],
      ),
    );
  }

  Widget _buildCounterButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        color: Colors.transparent,
        child: Icon(icon, size: 18, color: Colors.black54),
      ),
    );
  }

  Widget _buildSelectionItem({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
            Row(
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF8E8E93),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Color(0xFFC4C4C6),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorItem() {
    return GestureDetector(
      onTap: _pickColor,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '课程背景色',
              style: TextStyle(fontSize: 16, color: Colors.black87),
            ),
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _selectedColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Color(0xFFC4C4C6),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _weekdayToString(int weekday) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    if (weekday >= 1 && weekday <= 7) return weekdays[weekday - 1];
    return '';
  }
}

class _WeekRangePicker extends StatefulWidget {
  final int initialStart;
  final int initialEnd;
  final CourseWeekType initialType;
  final int maxWeek;

  const _WeekRangePicker({
    required this.initialStart,
    required this.initialEnd,
    required this.initialType,
    required this.maxWeek,
  });

  @override
  State<_WeekRangePicker> createState() => _WeekRangePickerState();
}

class _WeekRangePickerState extends State<_WeekRangePicker> {
  late Set<int> _selectedWeeks;
  late CourseWeekType _currentType;

  @override
  void initState() {
    super.initState();
    _currentType = widget.initialType;
    _selectedWeeks = {};

    // Initialize selection based on range and type
    for (int i = widget.initialStart; i <= widget.initialEnd; i++) {
      if (widget.initialType == CourseWeekType.all) {
        _selectedWeeks.add(i);
      } else if (widget.initialType == CourseWeekType.single) {
        if (i % 2 != 0) _selectedWeeks.add(i);
      } else if (widget.initialType == CourseWeekType.double) {
        if (i % 2 == 0) _selectedWeeks.add(i);
      }
    }
  }

  void _updateSelectionByType(CourseWeekType type) {
    setState(() {
      _currentType = type;
      _selectedWeeks.clear();
      for (int i = 1; i <= widget.maxWeek; i++) {
        if (type == CourseWeekType.all) {
          _selectedWeeks.add(i);
        } else if (type == CourseWeekType.single) {
          if (i % 2 != 0) _selectedWeeks.add(i);
        } else if (type == CourseWeekType.double) {
          if (i % 2 == 0) _selectedWeeks.add(i);
        }
      }
    });
  }

  void _toggleWeek(int week) {
    setState(() {
      if (_selectedWeeks.contains(week)) {
        _selectedWeeks.remove(week);
      } else {
        _selectedWeeks.add(week);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            _buildTypeSelector(),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.2,
                ),
                itemCount: widget.maxWeek,
                itemBuilder: (context, index) {
                  final week = index + 1;
                  final isSelected = _selectedWeeks.contains(week);
                  return GestureDetector(
                    onTap: () => _toggleWeek(week),
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildCheckbox(isSelected),
                        const SizedBox(width: 6),
                        Text(
                          '$week',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 30, top: 10),
              child: GestureDetector(
                onTap: _confirm,
                child: const Text(
                  '确定',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Align(
            alignment: Alignment.center,
            child: Text(
              '上课周数',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.black87),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: [
          _buildTypeOption('全部', CourseWeekType.all),
          const SizedBox(width: 24),
          _buildTypeOption('单周', CourseWeekType.single),
          const SizedBox(width: 24),
          _buildTypeOption('双周', CourseWeekType.double),
        ],
      ),
    );
  }

  Widget _buildTypeOption(String label, CourseWeekType type) {
    final isSelected = _currentType == type;
    return GestureDetector(
      onTap: () => _updateSelectionByType(type),
      child: Row(
        children: [
          Icon(
            isSelected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: isSelected ? Colors.blue : const Color(0xFFE0E0E0),
            size: 22,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 15, color: Color(0xFF333333)),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckbox(bool isSelected) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: isSelected
            ? null
            : Border.all(color: const Color(0xFFC4C4C6), width: 1.5),
      ),
      child: isSelected
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }

  void _confirm() {
    if (_selectedWeeks.isEmpty) {
      Navigator.pop(context);
      return;
    }

    final sortedWeeks = _selectedWeeks.toList()..sort();
    final start = sortedWeeks.first;
    final end = sortedWeeks.last;

    // Determine type based on selection
    CourseWeekType type = CourseWeekType.all;
    bool isAllOdd = true;
    bool isAllEven = true;

    for (final week in sortedWeeks) {
      if (week % 2 == 0) isAllOdd = false;
      if (week % 2 != 0) isAllEven = false;
    }

    if (isAllOdd) {
      type = CourseWeekType.single;
    } else if (isAllEven) {
      type = CourseWeekType.double;
    } else {
      type = CourseWeekType.all;
    }

    Navigator.pop(context, {'start': start, 'end': end, 'type': type});
  }
}

class _ColorPickerSheet extends StatelessWidget {
  final Color selectedColor;
  final List<Color> colors;

  const _ColorPickerSheet({required this.selectedColor, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              const Align(
                alignment: Alignment.center,
                child: Text(
                  '课程背景色',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: colors.length + 1,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                if (index == colors.length) {
                  return GestureDetector(
                    onTap: () async {
                      final Color? customColor = await showDialog<Color>(
                        context: context,
                        builder: (context) => _CustomColorPickerDialog(
                          initialColor: selectedColor,
                        ),
                      );
                      if (customColor != null && context.mounted) {
                        Navigator.pop(context, customColor);
                      }
                    },
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFF2F2F7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, color: Colors.black54),
                    ),
                  );
                }
                final color = colors[index];
                return GestureDetector(
                  onTap: () => Navigator.pop(context, color),
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    child: selectedColor == color
                        ? const Icon(
                            Icons.check,
                            color: Colors.black54,
                            size: 24,
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _CustomColorPickerDialog extends StatefulWidget {
  final Color initialColor;

  const _CustomColorPickerDialog({required this.initialColor});

  @override
  State<_CustomColorPickerDialog> createState() =>
      _CustomColorPickerDialogState();
}

class _CustomColorPickerDialogState extends State<_CustomColorPickerDialog> {
  late double _r;
  late double _g;
  late double _b;

  @override
  void initState() {
    super.initState();
    _r = widget.initialColor.red.toDouble();
    _g = widget.initialColor.green.toDouble();
    _b = widget.initialColor.blue.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = Color.fromARGB(
      255,
      _r.toInt(),
      _g.toInt(),
      _b.toInt(),
    );
    return AlertDialog(
      title: const Text('自定义颜色'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 50,
            width: double.infinity,
            decoration: BoxDecoration(
              color: currentColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
          ),
          const SizedBox(height: 16),
          _buildSlider('R', _r, Colors.red, (v) => setState(() => _r = v)),
          _buildSlider('G', _g, Colors.green, (v) => setState(() => _g = v)),
          _buildSlider('B', _b, Colors.blue, (v) => setState(() => _b = v)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, currentColor),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    Color color,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            activeColor: color,
            onChanged: onChanged,
          ),
        ),
        Text('${value.toInt()}'),
      ],
    );
  }
}
