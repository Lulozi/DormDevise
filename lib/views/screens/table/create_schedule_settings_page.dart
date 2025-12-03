import 'package:flutter/material.dart';
import 'package:dormdevise/utils/app_toast.dart';
import '../../../models/course_schedule_config.dart';
import '../../../services/course_service.dart';
import 'widgets/schedule_settings_sheet.dart';
import 'widgets/section_config_sheet.dart';
import 'create_schedule_courses_page.dart';

class CreateScheduleSettingsPage extends StatefulWidget {
  const CreateScheduleSettingsPage({super.key});

  @override
  State<CreateScheduleSettingsPage> createState() =>
      _CreateScheduleSettingsPageState();
}

class _CreateScheduleSettingsPageState
    extends State<CreateScheduleSettingsPage> {
  final TextEditingController _nameController = TextEditingController();

  // Initial settings
  CourseScheduleConfig _scheduleConfig = CourseScheduleConfig.njuDefaults();
  DateTime _semesterStart = DateTime(2025, 9, 1);
  int _currentWeek = 1;
  int _maxWeek = 20;
  String _tableName = '我的课表';
  bool _showWeekend = false;
  bool _showNonCurrentWeek = true;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onNext() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      AppToast.show(context, '请输入课程表名称');
      return;
    }

    // Check for duplicate name
    try {
      final schedules = await CourseService.instance.loadSchedules();
      if (schedules.any((s) => s.name == name)) {
        if (!mounted) return;
        AppToast.show(context, '课程表名称已存在');
        return;
      }
    } catch (e) {
      // Ignore error or handle it
    }

    if (!mounted) return;

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreateScheduleCoursesPage(
          scheduleName: name,
          scheduleConfig: _scheduleConfig,
          semesterStart: _semesterStart,
          currentWeek: _currentWeek,
          maxWeek: _maxWeek,
          tableName: name,
          showWeekend: _showWeekend,
          showNonCurrentWeek: _showNonCurrentWeek,
        ),
      ),
    );

    if (result == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _openSectionSettings() async {
    final CourseScheduleConfig? result =
        await showModalBottomSheet<CourseScheduleConfig>(
          context: context,
          isScrollControlled: true,
          builder: (BuildContext context) {
            return SectionConfigSheet(
              scheduleConfig: _scheduleConfig,
              onSubmit: (CourseScheduleConfig updated) {
                Navigator.of(context).pop(updated);
              },
            );
          },
        );
    if (result != null) {
      setState(() {
        _scheduleConfig = result;
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
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '取消',
            style: TextStyle(color: Colors.blue, fontSize: 16),
          ),
        ),
        leadingWidth: 80,
        title: const Text(
          '确认课程表基本信息',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _nameController.text.isNotEmpty ? _onNext : null,
            child: Text(
              '下一步',
              style: TextStyle(
                color: _nameController.text.isNotEmpty
                    ? Colors.blue
                    : Colors.grey,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: ScheduleSettingsPage(
        isEmbedded: true,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Center(
                child: Text(
                  '以下信息对计算周数、课表展示很重要，请认真填写。',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: '课程表名称 (必填)',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.grey),
                ),
                onChanged: (value) => setState(() {
                  _tableName = value;
                }),
              ),
            ),
          ],
        ),
        scheduleConfig: _scheduleConfig,
        semesterStart: _semesterStart,
        currentWeek: _currentWeek,
        maxWeek: _maxWeek,
        tableName: _tableName,
        showWeekend: _showWeekend,
        showNonCurrentWeek: _showNonCurrentWeek,
        onConfigChanged: (v) => setState(() => _scheduleConfig = v),
        onSemesterStartChanged: (v) => setState(() => _semesterStart = v),
        onCurrentWeekChanged: (v) => setState(() => _currentWeek = v),
        onMaxWeekChanged: (v) => setState(() => _maxWeek = v),
        onTableNameChanged: (v) => setState(() => _tableName = v),
        onShowWeekendChanged: (v) => setState(() => _showWeekend = v),
        onShowNonCurrentWeekChanged: (v) =>
            setState(() => _showNonCurrentWeek = v),
        onOpenSectionSettings: _openSectionSettings,
      ),
    );
  }
}
