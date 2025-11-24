import 'package:flutter/material.dart';
import 'package:dormdevise/models/timetable_config.dart';
import 'package:dormdevise/services/timetable_service.dart';

/// 课程表设置页面，从右侧滑入显示
class TimetableSettingsPage extends StatefulWidget {
  const TimetableSettingsPage({super.key});

  @override
  State<TimetableSettingsPage> createState() => _TimetableSettingsPageState();
}

class _TimetableSettingsPageState extends State<TimetableSettingsPage> {
  final TimetableService _service = TimetableService();
  late TimetableConfig _config;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  /// 加载课程表配置
  Future<void> _loadConfig() async {
    final config = await _service.getConfig();
    setState(() {
      _config = config;
      _isLoading = false;
    });
  }

  /// 保存配置
  Future<void> _saveConfig() async {
    await _service.saveConfig(_config);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存')),
      );
      Navigator.of(context).pop();
    }
  }

  /// 构建时间段编辑项
  Widget _buildTimeSectionItem(TimeSection section) {
    return ListTile(
      title: Text('第${section.section}节'),
      subtitle: Text('${section.startTime} - ${section.endTime}'),
      trailing: IconButton(
        icon: const Icon(Icons.edit),
        onPressed: () => _editTimeSection(section),
      ),
    );
  }

  /// 编辑时间段对话框
  Future<void> _editTimeSection(TimeSection section) async {
    final startController = TextEditingController(text: section.startTime);
    final endController = TextEditingController(text: section.endTime);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('编辑第${section.section}节时间'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: startController,
              decoration: const InputDecoration(
                labelText: '开始时间',
                hintText: 'HH:mm',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: endController,
              decoration: const InputDecoration(
                labelText: '结束时间',
                hintText: 'HH:mm',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final updatedSections = _config.timeSections.map((s) {
        if (s.section == section.section) {
          return TimeSection(
            section: s.section,
            startTime: startController.text,
            endTime: endController.text,
          );
        }
        return s;
      }).toList();

      setState(() {
        _config = _config.copyWith(timeSections: updatedSections);
      });
    }
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
        title: const Text('课程表设置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveConfig,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 当前周次设置
          Card(
            child: ListTile(
              title: const Text('当前周次'),
              trailing: DropdownButton<int>(
                value: _config.currentWeek,
                items: List.generate(
                  _config.totalWeeks,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text('第${index + 1}周'),
                  ),
                ),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _config = _config.copyWith(currentWeek: value);
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 总周数设置
          Card(
            child: ListTile(
              title: const Text('总周数'),
              trailing: DropdownButton<int>(
                value: _config.totalWeeks,
                items: List.generate(
                  30,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text('${index + 1}周'),
                  ),
                ),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _config = _config.copyWith(totalWeeks: value);
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 课程时间设置
          const Text(
            '课程时间',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: _config.timeSections
                  .map((section) => _buildTimeSectionItem(section))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
