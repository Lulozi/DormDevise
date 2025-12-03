import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:dormdevise/utils/app_toast.dart';

import '../../../models/course_schedule_config.dart';
import 'widgets/schedule_settings_sheet.dart';

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

  @override
  void initState() {
    super.initState();
    _tableName = widget.tableName;
  }

  @override
  void didUpdateWidget(covariant AllSchedulesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tableName != widget.tableName) {
      _tableName = widget.tableName;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // Light grey background
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F5),
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
            icon: const Icon(Icons.add, color: Colors.black87, size: 28),
            onPressed: () {
              AppToast.show(context, '功能开发中');
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
            child: Text(
              '点击课程表卡片可切换当前查看课程',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildScheduleCard(context, isCurrent: true),
                // Placeholder for another schedule to match the image look (optional, but let's stick to one for now or mock a second one)
                // _buildScheduleCard(context, isCurrent: false, name: "课程表"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleCard(
    BuildContext context, {
    required bool isCurrent,
    String? name,
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
          onTap: () {
            if (!isCurrent) {
              AppToast.show(context, '切换功能开发中');
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Row(
              children: [
                Text(
                  name ?? _tableName,
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
                      _openSettings(context);
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

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (BuildContext context) {
          return ScheduleSettingsPage(
            scheduleConfig: widget.scheduleConfig,
            semesterStart: widget.semesterStart,
            currentWeek: widget.currentWeek,
            maxWeek: widget.maxWeek,
            tableName: _tableName,
            showWeekend: widget.showWeekend,
            showNonCurrentWeek: widget.showNonCurrentWeek,
            onConfigChanged: widget.onConfigChanged,
            onSemesterStartChanged: widget.onSemesterStartChanged,
            onCurrentWeekChanged: widget.onCurrentWeekChanged,
            onMaxWeekChanged: widget.onMaxWeekChanged,
            onTableNameChanged: (newName) {
              widget.onTableNameChanged(newName);
              setState(() {
                _tableName = newName;
              });
            },
            onShowWeekendChanged: widget.onShowWeekendChanged,
            onShowNonCurrentWeekChanged: widget.onShowNonCurrentWeekChanged,
            onOpenSectionSettings: widget.onOpenSectionSettings,
          );
        },
      ),
    );
  }
}
