import 'package:flutter/material.dart';
import 'package:dormdevise/models/course.dart';
import 'package:dormdevise/models/timetable_config.dart';
import 'package:dormdevise/services/timetable_service.dart';
import 'package:dormdevise/screens/table/timetable_settings_page.dart';
import 'package:dormdevise/screens/table/course_edit_page.dart';

/// 课表页面，展示周课程表并支持添加、编辑课程
class TablePage extends StatefulWidget {
  const TablePage({super.key});

  @override
  State<TablePage> createState() => _TablePageState();
}

class _TablePageState extends State<TablePage> {
  final TimetableService _service = TimetableService();
  final ScrollController _verticalController = ScrollController();
  final ScrollController _weekColumnController = ScrollController();
  late PageController _pageController;
  
  List<Course> _courses = [];
  TimetableConfig _config = TimetableConfig.defaultConfig();
  bool _isLoading = true;
  int _currentWeekday = 1; // 当前显示的星期几

  /// 星期标签
  final List<String> _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  /// 课程格子的尺寸
  static const double _sectionHeight = 80.0;
  static const double _weekColumnWidth = 50.0;

  @override
  void initState() {
    super.initState();
    // 使用大数作为初始页，实现无限循环效果
    _pageController = PageController(initialPage: 10000);
    _loadData();
    _setupScrollSync();
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _weekColumnController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// 设置滚动同步
  void _setupScrollSync() {
    _verticalController.addListener(() {
      if (_weekColumnController.hasClients) {
        _weekColumnController.jumpTo(_verticalController.offset);
      }
    });
  }

  /// 加载课程数据和配置
  Future<void> _loadData() async {
    final courses = await _service.getCourses();
    final config = await _service.getConfig();
    setState(() {
      _courses = courses;
      _config = config;
      _isLoading = false;
    });
  }

  /// 打开课程表设置
  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const TimetableSettingsPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;
          var tween = Tween(begin: begin, end: end).chain(
            CurveTween(curve: curve),
          );
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
    _loadData();
  }

  /// 打开添加/编辑课程页面
  Future<void> _openCourseEdit({Course? course, int? weekday}) async {
    final result = await Navigator.of(context).push<Course>(
      MaterialPageRoute(
        builder: (context) => CourseEditPage(
          course: course,
          config: _config,
          presetWeekday: weekday,
        ),
      ),
    );

    if (result != null) {
      if (course == null) {
        await _service.addCourse(result);
      } else {
        await _service.updateCourse(result);
      }
      _loadData();
    }
  }

  /// 删除课程
  Future<void> _deleteCourse(Course course) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除课程'),
        content: Text('确定要删除《${course.name}》吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _service.deleteCourse(course.id);
      _loadData();
    }
  }



  /// 构建周次列
  Widget _buildWeekColumn() {
    return Container(
      width: _weekColumnWidth,
      color: Colors.grey.shade100,
      child: Column(
        children: [
          // 顶部"周"字标题
          Container(
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Text(
              '周',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          // 节次列表，与课程表同步滚动
          Expanded(
            child: ListView.builder(
              controller: _weekColumnController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _config.sectionsPerDay,
              itemBuilder: (context, index) {
                final section = index + 1;
                return GestureDetector(
                  onTap: _openSettings,
                  child: Container(
                    height: _sectionHeight,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$section',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单天的课程列
  Widget _buildDayColumn(int weekday) {
    // 获取该天的所有课程
    final dayCourses = _courses.where((course) {
      return course.weekday == weekday &&
          course.weeks.contains(_config.currentWeek);
    }).toList();

    return Column(
      children: [
          // 星期标题
          Container(
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              '周${_weekdays[weekday - 1]}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          // 课程区域
          Expanded(
            child: Stack(
              children: [
                // 背景网格
                ListView.builder(
                  controller: _verticalController,
                  itemCount: _config.sectionsPerDay,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () => _openCourseEdit(weekday: weekday),
                      child: Container(
                        height: _sectionHeight,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          color: Colors.white,
                        ),
                        child: const Center(
                          child: Icon(Icons.add, color: Colors.grey, size: 16),
                        ),
                      ),
                    );
                  },
                ),
                // 课程卡片层
                ...dayCourses.map((course) {
                  final top = (course.startSection - 1) * _sectionHeight;
                  final spanSections =
                      course.endSection - course.startSection + 1;
                  final height = _sectionHeight * spanSections;

                  return Positioned(
                    top: top,
                    left: 0,
                    right: 0,
                    height: height,
                    child: GestureDetector(
                      onTap: () => _openCourseEdit(course: course),
                      onLongPress: () => _deleteCourse(course),
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Color(course.color).withOpacity(0.8),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Text(
                              course.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (course.location != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.location_on,
                                      size: 10, color: Colors.white),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      course.location!,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.white,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (course.teacher != null && spanSections > 1) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(Icons.person,
                                      size: 10, color: Colors.white),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      course.teacher!,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.white,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('第${_config.currentWeek}周 周${_weekdays[_currentWeekday - 1]}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Row(
        children: [
          // 左侧周次列
          _buildWeekColumn(),
          // 右侧课程表，支持横向滑动切换周一到周日（无限循环）
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentWeekday = (index % 7) + 1;
                });
              },
              itemBuilder: (context, index) {
                // 使用模运算实现周一到周日的循环
                final weekday = (index % 7) + 1;
                return _buildDayColumn(weekday);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openCourseEdit(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
