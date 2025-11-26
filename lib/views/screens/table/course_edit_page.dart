import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../models/course.dart';

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
    const Color(0xFF90A4AE),
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
    }
    _classroomController = TextEditingController(text: initialLocation);

    _selectedColor = widget.course?.color ?? _presetColors[0];
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
        weekType: s.weekType,
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
          weekType: CourseWeekType.all,
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

  Future<void> _pickTimeSlot(int index) async {
    final session = _sessions[index];
    final result = await showModalBottomSheet<Map<String, int>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _TimeSlotPicker(
        initialWeekday: session.weekday,
        initialStartSection: session.startSection,
        initialSectionCount: session.sectionCount,
      ),
    );

    if (result != null) {
      setState(() {
        _sessions[index] = CourseSession(
          weekday: result['weekday']!,
          startSection: result['startSection']!,
          sectionCount: result['sectionCount']!,
          location: session.location,
          startWeek: session.startWeek,
          endWeek: session.endWeek,
          weekType: session.weekType,
        );
      });
    }
  }

  Future<void> _pickWeeks() async {
    final result = await showModalBottomSheet<Map<String, int>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _WeekRangePicker(
        initialStart: _startWeek,
        initialEnd: _endWeek,
        maxWeek: widget.maxWeek,
      ),
    );

    if (result != null) {
      setState(() {
        _startWeek = result['start']!;
        _endWeek = result['end']!;
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
            value: '第 $_startWeek-$_endWeek 周',
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
            return Column(
              children: [
                InkWell(
                  onTap: () => _pickTimeSlot(index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '课程时间 ${index + 1}',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              '周${_weekdayToString(session.weekday)} 第${session.startSection}-${session.startSection + session.sectionCount - 1}节',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Color(0xFF8E8E93),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.keyboard_arrow_down,
                              size: 20,
                              color: Color(0xFFC4C4C6),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (!isLast)
                  const Divider(
                    height: 1,
                    indent: 16,
                    color: Color(0xFFE5E5EA),
                  ),
              ],
            );
          }),
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

class _TimeSlotPicker extends StatefulWidget {
  final int initialWeekday;
  final int initialStartSection;
  final int initialSectionCount;

  const _TimeSlotPicker({
    required this.initialWeekday,
    required this.initialStartSection,
    required this.initialSectionCount,
  });

  @override
  State<_TimeSlotPicker> createState() => _TimeSlotPickerState();
}

class _TimeSlotPickerState extends State<_TimeSlotPicker> {
  late int _weekday;
  late int _startSection;
  late int _sectionCount;

  @override
  void initState() {
    super.initState();
    _weekday = widget.initialWeekday;
    _startSection = widget.initialStartSection;
    _sectionCount = widget.initialSectionCount;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 350,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: CupertinoPicker(
                    itemExtent: 40,
                    scrollController: FixedExtentScrollController(
                      initialItem: _weekday - 1,
                    ),
                    onSelectedItemChanged: (index) {
                      setState(() => _weekday = index + 1);
                    },
                    children: List.generate(7, (index) {
                      return Center(
                        child: Text(
                          '周${['一', '二', '三', '四', '五', '六', '日'][index]}',
                        ),
                      );
                    }),
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    itemExtent: 40,
                    scrollController: FixedExtentScrollController(
                      initialItem: _startSection - 1,
                    ),
                    onSelectedItemChanged: (index) {
                      setState(() => _startSection = index + 1);
                    },
                    children: List.generate(12, (index) {
                      return Center(child: Text('第 ${index + 1} 节'));
                    }),
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    itemExtent: 40,
                    scrollController: FixedExtentScrollController(
                      initialItem: _sectionCount - 1,
                    ),
                    onSelectedItemChanged: (index) {
                      setState(() => _sectionCount = index + 1);
                    },
                    children: List.generate(4, (index) {
                      return Center(child: Text('持续 ${index + 1} 节'));
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          const Text(
            '选择时间',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, {
                'weekday': _weekday,
                'startSection': _startSection,
                'sectionCount': _sectionCount,
              });
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class _WeekRangePicker extends StatefulWidget {
  final int initialStart;
  final int initialEnd;
  final int maxWeek;

  const _WeekRangePicker({
    required this.initialStart,
    required this.initialEnd,
    required this.maxWeek,
  });

  @override
  State<_WeekRangePicker> createState() => _WeekRangePickerState();
}

class _WeekRangePickerState extends State<_WeekRangePicker> {
  late int _start;
  late int _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: CupertinoPicker(
                    itemExtent: 40,
                    scrollController: FixedExtentScrollController(
                      initialItem: _start - 1,
                    ),
                    onSelectedItemChanged: (index) {
                      setState(() {
                        _start = index + 1;
                        if (_end < _start) _end = _start;
                      });
                    },
                    children: List.generate(widget.maxWeek, (index) {
                      return Center(child: Text('第 ${index + 1} 周'));
                    }),
                  ),
                ),
                const Text('至'),
                Expanded(
                  child: CupertinoPicker(
                    itemExtent: 40,
                    scrollController: FixedExtentScrollController(
                      initialItem: _end - 1,
                    ),
                    onSelectedItemChanged: (index) {
                      setState(() {
                        _end = index + 1;
                        if (_start > _end) _start = _end;
                      });
                    },
                    children: List.generate(widget.maxWeek, (index) {
                      return Center(child: Text('第 ${index + 1} 周'));
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          const Text(
            '选择周数',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, {'start': _start, 'end': _end});
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
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
          const Text(
            '选择颜色',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: colors.map((color) {
              return GestureDetector(
                onTap: () => Navigator.pop(context, color),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: selectedColor == color
                        ? Border.all(color: Colors.black, width: 3)
                        : null,
                  ),
                  child: selectedColor == color
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
