import 'package:flutter/material.dart';
import 'package:dormdevise/models/course.dart';
import 'package:dormdevise/models/timetable_config.dart';
import 'package:uuid/uuid.dart';

/// 课程编辑页面，用于添加或编辑课程
class CourseEditPage extends StatefulWidget {
  /// 要编辑的课程，为null时表示添加新课程
  final Course? course;

  /// 课程表配置
  final TimetableConfig config;

  /// 预设的星期几
  final int? presetWeekday;

  const CourseEditPage({
    super.key,
    this.course,
    required this.config,
    this.presetWeekday,
  });

  @override
  State<CourseEditPage> createState() => _CourseEditPageState();
}

class _CourseEditPageState extends State<CourseEditPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _locationController;
  late TextEditingController _teacherController;
  late int _weekday;
  late int _startSection;
  late int _endSection;
  late Set<int> _selectedWeeks;
  late int _color;

  /// 可选的课程颜色
  final List<Color> _colors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.red,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.course?.name ?? '');
    _locationController =
        TextEditingController(text: widget.course?.location ?? '');
    _teacherController =
        TextEditingController(text: widget.course?.teacher ?? '');
    _weekday = widget.course?.weekday ?? widget.presetWeekday ?? 1;
    _startSection = widget.course?.startSection ?? 1;
    _endSection = widget.course?.endSection ?? 2;
    _selectedWeeks = widget.course?.weeks.toSet() ?? {1};
    _color = widget.course?.color ?? Colors.blue.value;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _teacherController.dispose();
    super.dispose();
  }

  /// 保存课程
  void _saveCourse() {
    if (_formKey.currentState!.validate()) {
      final course = Course(
        id: widget.course?.id ?? const Uuid().v4(),
        name: _nameController.text,
        location: _locationController.text.isEmpty
            ? null
            : _locationController.text,
        teacher:
            _teacherController.text.isEmpty ? null : _teacherController.text,
        weekday: _weekday,
        startSection: _startSection,
        endSection: _endSection,
        weeks: _selectedWeeks.toList()..sort(),
        color: _color,
      );
      Navigator.of(context).pop(course);
    }
  }

  /// 选择周次对话框
  Future<void> _selectWeeks() async {
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (context) {
        final tempSelected = Set<int>.from(_selectedWeeks);
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('选择周次'),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    childAspectRatio: 1.5,
                  ),
                  itemCount: widget.config.totalWeeks,
                  itemBuilder: (context, index) {
                    final week = index + 1;
                    final isSelected = tempSelected.contains(week);
                    return Padding(
                      padding: const EdgeInsets.all(4),
                      child: FilterChip(
                        label: Text('$week'),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              tempSelected.add(week);
                            } else {
                              tempSelected.remove(week);
                            }
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(tempSelected),
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        _selectedWeeks = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course == null ? '添加课程' : '编辑课程'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saveCourse,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 课程名称
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '课程名称',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入课程名称';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 上课地点
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: '上课地点（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // 任课教师
            TextFormField(
              controller: _teacherController,
              decoration: const InputDecoration(
                labelText: '任课教师（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // 星期几
            DropdownButtonFormField<int>(
              value: _weekday,
              decoration: const InputDecoration(
                labelText: '星期',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 1, child: Text('周一')),
                DropdownMenuItem(value: 2, child: Text('周二')),
                DropdownMenuItem(value: 3, child: Text('周三')),
                DropdownMenuItem(value: 4, child: Text('周四')),
                DropdownMenuItem(value: 5, child: Text('周五')),
                DropdownMenuItem(value: 6, child: Text('周六')),
                DropdownMenuItem(value: 7, child: Text('周日')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _weekday = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),

            // 开始节次
            DropdownButtonFormField<int>(
              value: _startSection,
              decoration: const InputDecoration(
                labelText: '开始节次',
                border: OutlineInputBorder(),
              ),
              items: List.generate(
                widget.config.sectionsPerDay,
                (index) => DropdownMenuItem(
                  value: index + 1,
                  child: Text('第${index + 1}节'),
                ),
              ),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _startSection = value;
                    if (_endSection < value) {
                      _endSection = value;
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 16),

            // 结束节次
            DropdownButtonFormField<int>(
              value: _endSection,
              decoration: const InputDecoration(
                labelText: '结束节次',
                border: OutlineInputBorder(),
              ),
              items: List.generate(
                widget.config.sectionsPerDay,
                (index) => DropdownMenuItem(
                  value: index + 1,
                  child: Text('第${index + 1}节'),
                ),
              ).where((item) => item.value! >= _startSection).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _endSection = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),

            // 选择周次
            ListTile(
              title: const Text('上课周次'),
              subtitle: Text(_selectedWeeks.isEmpty
                  ? '未选择'
                  : '第${_selectedWeeks.join(', ')}周'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _selectWeeks,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: BorderSide(color: Colors.grey.shade400),
              ),
            ),
            const SizedBox(height: 16),

            // 选择颜色
            const Text('课程颜色'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _colors.map((color) {
                final isSelected = color.value == _color;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _color = color.value;
                    });
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: Colors.black, width: 3)
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
