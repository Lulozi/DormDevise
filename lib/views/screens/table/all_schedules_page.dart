import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:dormdevise/utils/app_toast.dart';

import '../../../models/course_schedule_config.dart';
import '../../../models/schedule_metadata.dart';
import '../../../services/course_service.dart';
import 'widgets/schedule_settings_sheet.dart';
import 'create_schedule_settings_page.dart';

class AllSchedulesPage extends StatefulWidget {
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

  const AllSchedulesPage({
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
  State<AllSchedulesPage> createState() => _AllSchedulesPageState();
}

class _AllSchedulesPageState extends State<AllSchedulesPage> {
  late String _tableName;
  late CourseScheduleConfig _scheduleConfig;
  late DateTime _semesterStart;
  late int _currentWeek;
  late int _maxWeek;
  late bool _showWeekend;
  late bool _showNonCurrentWeek;

  bool _isAddMenuOpen = false;
  final GlobalKey _addBtnKey = GlobalKey();

  List<ScheduleMetadata> _schedules = [];
  String _currentScheduleId = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tableName = widget.tableName;
    _scheduleConfig = widget.scheduleConfig;
    _semesterStart = widget.semesterStart;
    _currentWeek = widget.currentWeek;
    _maxWeek = widget.maxWeek;
    _showWeekend = widget.showWeekend;
    _showNonCurrentWeek = widget.showNonCurrentWeek;
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    final service = CourseService.instance;
    final schedules = await service.loadSchedules();
    final currentId = await service.getCurrentScheduleId();
    if (mounted) {
      setState(() {
        _schedules = schedules;
        _currentScheduleId = currentId;
        _isLoading = false;
      });
    }
  }

  @override
  void didUpdateWidget(covariant AllSchedulesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tableName != widget.tableName) {
      _tableName = widget.tableName;
    }
    if (oldWidget.scheduleConfig != widget.scheduleConfig) {
      _scheduleConfig = widget.scheduleConfig;
    }
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

  Future<void> _showAddMenu(BuildContext context) async {
    final RenderBox button =
        _addBtnKey.currentContext!.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;

    final Offset buttonBottomRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final double rightOffset = overlay.size.width - buttonBottomRight.dx;
    final double topOffset = buttonBottomRight.dy;

    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, _, __) {
          return Stack(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                behavior: HitTestBehavior.translucent,
                child: Container(color: Colors.transparent),
              ),
              Positioned(
                top: topOffset + 10,
                right: rightOffset,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white,
                  child: SizedBox(
                    width: 180,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildCustomMenuItem(
                          context,
                          'web',
                          '网页导入课程表',
                          Icons.language,
                        ),
                        const Divider(height: 1, thickness: 0.5),
                        _buildCustomMenuItem(
                          context,
                          'camera',
                          '拍照导入课程表',
                          Icons.camera_alt_outlined,
                        ),
                        const Divider(height: 1, thickness: 0.5),
                        _buildCustomMenuItem(
                          context,
                          'file',
                          '文件导入课程表',
                          Icons.folder_open,
                        ),
                        const Divider(height: 1, thickness: 0.5),
                        _buildCustomMenuItem(
                          context,
                          'manual',
                          '手动创建课程表',
                          Icons.edit_outlined,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCustomMenuItem(
    BuildContext context,
    String value,
    String text,
    IconData icon,
  ) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        if (value == 'manual') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const CreateScheduleSettingsPage(),
            ),
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => Scaffold(
                appBar: AppBar(title: const Text('功能开发中')),
                body: const Center(child: Text('暂未开放')),
              ),
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.black87),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC), // Light grey background
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F8FC),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '全部课程表',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const FaIcon(
              FontAwesomeIcons.squareCheck,
              color: Colors.black87,
              size: 22,
            ),
            onPressed: () {
              AppToast.show(context, '功能开发中');
            },
          ),
          IconButton(
            key: _addBtnKey,
            icon: Icon(
              Icons.add,
              color: _isAddMenuOpen ? Colors.grey : Colors.black87,
              size: 28,
            ),
            onPressed: () async {
              setState(() {
                _isAddMenuOpen = true;
              });
              await _showAddMenu(context);
              if (mounted) {
                setState(() {
                  _isAddMenuOpen = false;
                });
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _schedules.length,
                    itemBuilder: (context, index) {
                      final schedule = _schedules[index];
                      return _buildScheduleCard(
                        context,
                        isCurrent: schedule.id == _currentScheduleId,
                        name: schedule.name,
                        id: schedule.id,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleCard(
    BuildContext context, {
    required bool isCurrent,
    required String name,
    required String id,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            if (!isCurrent) {
              await CourseService.instance.switchSchedule(id);
              if (context.mounted) {
                Navigator.of(context).pop(true);
              }
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Row(
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '当前',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Material(
                  color: const Color(0xFFF2F2F2),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      _openSettings(context, id);
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: Text(
                        '设置',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSettings(BuildContext context, String scheduleId) async {
    CourseScheduleConfig config;
    DateTime semesterStart;
    int currentWeek;
    int maxWeek;
    String tableName;
    bool showWeekend;
    bool showNonCurrentWeek;

    if (scheduleId == _currentScheduleId) {
      config = _scheduleConfig;
      semesterStart = _semesterStart;
      currentWeek = _currentWeek;
      maxWeek = _maxWeek;
      tableName = _tableName;
      showWeekend = _showWeekend;
      showNonCurrentWeek = _showNonCurrentWeek;
    } else {
      final service = CourseService.instance;
      config = await service.loadConfig(scheduleId);
      semesterStart =
          await service.loadSemesterStart(scheduleId) ?? DateTime(2025, 9, 1);
      maxWeek = await service.loadMaxWeek(scheduleId);
      tableName = await service.loadTableName(scheduleId);
      showWeekend = await service.loadShowWeekend(scheduleId);
      showNonCurrentWeek = await service.loadShowNonCurrentWeek(scheduleId);

      final DateTime now = DateTime.now();
      final DateTime firstWeekStart = semesterStart.subtract(
        Duration(days: semesterStart.weekday - 1),
      );
      final int diffDays = now.difference(firstWeekStart).inDays;
      currentWeek = (diffDays / 7).floor() + 1;
      if (currentWeek < 1) currentWeek = 1;
      if (currentWeek > maxWeek) currentWeek = maxWeek;
    }

    if (!context.mounted) return;

    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (BuildContext context) {
          return ScheduleSettingsPage(
            scheduleConfig: config,
            semesterStart: semesterStart,
            currentWeek: currentWeek,
            maxWeek: maxWeek,
            tableName: tableName,
            showWeekend: showWeekend,
            showNonCurrentWeek: showNonCurrentWeek,
            nameValidator: (name) async {
              final exists = _schedules.any(
                (s) => s.name == name && s.id != scheduleId,
              );
              if (exists) {
                return '课程表名称 "$name" 已存在';
              }
              return null;
            },
            onConfigChanged: (newConfig) async {
              if (scheduleId == _currentScheduleId) {
                widget.onConfigChanged(newConfig);
                setState(() => _scheduleConfig = newConfig);
              }
              await CourseService.instance.saveConfig(newConfig, scheduleId);
              config = newConfig; // Update local variable
            },
            onSemesterStartChanged: (date) async {
              if (scheduleId == _currentScheduleId) {
                widget.onSemesterStartChanged(date);
                setState(() => _semesterStart = date);
              }
              await CourseService.instance.saveSemesterStart(date, scheduleId);
              semesterStart = date; // Update local variable
            },
            onCurrentWeekChanged: (week) {
              if (scheduleId == _currentScheduleId) {
                widget.onCurrentWeekChanged(week);
                setState(() => _currentWeek = week);
              }
              currentWeek = week; // Update local variable
            },
            onMaxWeekChanged: (max) async {
              if (scheduleId == _currentScheduleId) {
                widget.onMaxWeekChanged(max);
                setState(() => _maxWeek = max);
              }
              await CourseService.instance.saveMaxWeek(max, scheduleId);
              maxWeek = max; // Update local variable
            },
            onTableNameChanged: (newName) async {
              if (scheduleId == _currentScheduleId) {
                widget.onTableNameChanged(newName);
                setState(() {
                  _tableName = newName;
                });
              }

              final index = _schedules.indexWhere((s) => s.id == scheduleId);
              if (index != -1) {
                setState(() {
                  _schedules[index] = ScheduleMetadata(
                    id: scheduleId,
                    name: newName,
                  );
                });
              }

              await CourseService.instance.saveTableName(newName, scheduleId);
              tableName = newName; // Update local variable
            },
            onShowWeekendChanged: (show) async {
              if (scheduleId == _currentScheduleId) {
                widget.onShowWeekendChanged(show);
                setState(() => _showWeekend = show);
              }
              await CourseService.instance.saveShowWeekend(show, scheduleId);
              showWeekend = show; // Update local variable
            },
            onShowNonCurrentWeekChanged: (show) async {
              if (scheduleId == _currentScheduleId) {
                widget.onShowNonCurrentWeekChanged(show);
                setState(() => _showNonCurrentWeek = show);
              }
              await CourseService.instance.saveShowNonCurrentWeek(
                show,
                scheduleId,
              );
              showNonCurrentWeek = show; // Update local variable
            },
            onOpenSectionSettings: () {
              if (scheduleId == _currentScheduleId) {
                widget.onOpenSectionSettings();
              } else {
                AppToast.show(context, '请切换到该课程表后再设置课程时间');
              }
            },
          );
        },
      ),
    );

    // Reload schedules to reflect any name changes
    _loadSchedules();
  }
}
