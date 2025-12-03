import 'package:flutter/material.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';
import 'package:dormdevise/utils/app_toast.dart';
import '../../../models/course.dart';
import '../../../models/course_schedule_config.dart';
import '../../../services/course_service.dart';
import 'widgets/course_schedule_table.dart';
import 'course_edit_page.dart';

class CreateScheduleCoursesPage extends StatefulWidget {
  final String scheduleName;
  final CourseScheduleConfig scheduleConfig;
  final DateTime semesterStart;
  final int currentWeek;
  final int maxWeek;
  final String tableName;
  final bool showWeekend;
  final bool showNonCurrentWeek;

  const CreateScheduleCoursesPage({
    super.key,
    required this.scheduleName,
    required this.scheduleConfig,
    required this.semesterStart,
    required this.currentWeek,
    required this.maxWeek,
    required this.tableName,
    required this.showWeekend,
    required this.showNonCurrentWeek,
  });

  @override
  State<CreateScheduleCoursesPage> createState() =>
      _CreateScheduleCoursesPageState();
}

class _CreateScheduleCoursesPageState extends State<CreateScheduleCoursesPage> {
  final List<Course> _courses = [];
  late List<SectionTime> _sections;
  bool _isSaving = false;

  late final PageController _pageController;
  late final LinkedScrollControllerGroup _scrollGroup;
  late final ScrollController _timeColumnController;
  final Map<int, ScrollController> _weekScrollControllers = {};
  late int _currentWeek;

  DateTime get _firstWeekStart {
    return widget.semesterStart.subtract(
      Duration(days: widget.semesterStart.weekday - 1),
    );
  }

  List<DateTime> _resolveWeekDates(int week) {
    final DateTime start = _firstWeekStart.add(Duration(days: (week - 1) * 7));
    return List<DateTime>.generate(7, (int index) {
      return start.add(Duration(days: index));
    });
  }

  @override
  void initState() {
    super.initState();
    _sections = widget.scheduleConfig.generateSections();
    _currentWeek = widget.currentWeek;
    _pageController = PageController(initialPage: _currentWeek - 1);
    _scrollGroup = LinkedScrollControllerGroup();
    _timeColumnController = _scrollGroup.addAndGet();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _timeColumnController.dispose();
    for (var controller in _weekScrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onFinish() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
    });

    try {
      // 1. Create Schedule Metadata
      final id = await CourseService.instance.createSchedule(
        widget.scheduleName,
      );

      // 2. Switch to new schedule
      await CourseService.instance.switchSchedule(id);

      // 3. Save all data
      await CourseService.instance.saveConfig(widget.scheduleConfig, id);
      await CourseService.instance.saveSemesterStart(widget.semesterStart, id);
      await CourseService.instance.saveMaxWeek(widget.maxWeek, id);
      // Use schedule name as table name since we hid the table name field
      await CourseService.instance.saveTableName(widget.scheduleName, id);
      await CourseService.instance.saveShowWeekend(widget.showWeekend, id);
      await CourseService.instance.saveShowNonCurrentWeek(
        widget.showNonCurrentWeek,
        id,
      );
      await CourseService.instance.saveCourses(_courses, id);

      if (!mounted) return;

      // 4. Navigate back to AllSchedulesPage
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      final msg = e.toString().replaceAll('Exception: ', '');
      AppToast.show(context, '创建失败: $msg');
    }
  }

  void _addCourse(int weekday, int section) async {
    final Course? newCourse = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CourseEditPage(
          initialWeekday: weekday,
          initialSection: section,
          maxWeek: widget.maxWeek,
          scheduleConfig: widget.scheduleConfig,
          existingCourses: _courses,
        ),
      ),
    );

    if (newCourse != null) {
      _handleCourseAdded(newCourse);
    }
  }

  void _handleCourseAdded(Course newCourse) {
    setState(() {
      // 检查是否存在同名课程
      final existingIndex = _courses.indexWhere(
        (c) => c.name == newCourse.name,
      );
      if (existingIndex != -1) {
        final existingCourse = _courses[existingIndex];

        // 只有当颜色和教师信息都一致时才合并，否则视为不同课程（即使同名）
        final bool isSameColor =
            existingCourse.color.value == newCourse.color.value;
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F8FC),
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '上一步',
            style: TextStyle(color: Colors.blue, fontSize: 16),
          ),
        ),
        leadingWidth: 80,
        title: const Text(
          '添加课程',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _onFinish,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '完成',
                    style: TextStyle(color: Colors.blue, fontSize: 16),
                  ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double timeColumnWidth = constraints.maxWidth / 8;
          return Row(
            children: [
              SizedBox(
                width: timeColumnWidth,
                child: CourseScheduleTable(
                  courses: const [],
                  currentWeek: _currentWeek,
                  sections: _sections,
                  weekdays: const [],
                  weekdayIndexes: const [],
                  maxWeek: widget.maxWeek,
                  includeTimeColumn: true,
                  applySurface: false,
                  timeColumnWidth: timeColumnWidth,
                  scrollController: _timeColumnController,
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _currentWeek = index + 1;
                    });
                  },
                  itemCount: widget.maxWeek,
                  itemBuilder: (context, index) {
                    final int week = index + 1;
                    return CourseScheduleTable(
                      courses: _courses,
                      currentWeek: week,
                      sections: _sections,
                      maxWeek: widget.maxWeek,
                      showNonCurrentWeek: widget.showNonCurrentWeek,
                      weekDates: _resolveWeekDates(week),
                      weekdayIndexes: widget.showWeekend
                          ? const [1, 2, 3, 4, 5, 6, 7]
                          : const [1, 2, 3, 4, 5],
                      weekdays: widget.showWeekend
                          ? const ['周一', '周二', '周三', '周四', '周五', '周六', '周日']
                          : const ['周一', '周二', '周三', '周四', '周五'],
                      includeTimeColumn: false,
                      timeColumnWidth: 0,
                      scrollController: _weekScrollControllers.putIfAbsent(
                        week,
                        () => _scrollGroup.addAndGet(),
                      ),
                      onAddCourseTap: _addCourse,
                      onCourseChanged: (oldCourse, newCourse) {
                        setState(() {
                          final index = _courses.indexOf(oldCourse);
                          if (index != -1) {
                            _courses[index] = newCourse;
                          }
                        });
                      },
                      onCourseDeleted: (course) {
                        setState(() {
                          _courses.remove(course);
                        });
                      },
                      onCourseAdded: (course) {
                        _handleCourseAdded(course);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
