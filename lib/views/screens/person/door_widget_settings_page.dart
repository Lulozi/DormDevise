import 'package:dormdevise/models/door_widget_settings.dart';
import 'package:dormdevise/services/door_widget_service.dart';
import 'package:flutter/material.dart';

/// 桌面微件配置页，提供展示与刷新行为相关的开关。
class DoorWidgetSettingsPage extends StatefulWidget {
  const DoorWidgetSettingsPage({super.key});

  /// 创建状态对象，以便处理用户操作并与服务同步。
  @override
  State<DoorWidgetSettingsPage> createState() => _DoorWidgetSettingsPageState();
}

class _DoorWidgetSettingsPageState extends State<DoorWidgetSettingsPage> {
  late DoorWidgetSettings _settings;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _settings = DoorWidgetService.instance.settings;
  }

  /// 将修改后的配置同步到服务，并在 UI 中反映最新值。
  Future<void> _applySettings(DoorWidgetSettings next) async {
    setState(() {
      _settings = next;
      _updating = true;
    });
    await DoorWidgetService.instance.updateSettings(next);
    if (mounted) {
      setState(() {
        _updating = false;
      });
    }
  }

  /// 构建单个开关条目，复用统一样式。
  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: _updating ? null : onChanged,
    );
  }

  /// 构建自动刷新频率的下拉选择组件。
  Widget _buildRefreshDropdown() {
    const Map<int, String> options = <int, String>{
      5: '每 5 分钟',
      10: '每 10 分钟',
      15: '每 15 分钟',
      30: '每 30 分钟',
      60: '每 60 分钟',
    };
    return ListTile(
      title: const Text('自动刷新频率'),
      subtitle: const Text('开启后将定期刷新微件显示数据'),
      trailing: DropdownButton<int>(
        value: options.containsKey(_settings.autoRefreshMinutes)
            ? _settings.autoRefreshMinutes
            : 30,
        onChanged: _updating || !_settings.autoRefreshEnabled
            ? null
            : (int? value) {
                if (value == null) {
                  return;
                }
                _applySettings(_settings.copyWith(autoRefreshMinutes: value));
              },
        items: options.entries
            .map(
              (entry) => DropdownMenuItem<int>(
                value: entry.key,
                child: Text(entry.value),
              ),
            )
            .toList(),
      ),
    );
  }

  /// 构建页面主体，包括使用说明与设置项。
  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('桌面微件配置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    '使用小贴士',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  Text('1. 长按桌面空白处，添加微件「舍设开门」。'),
                  Text('2. 滑动微件中央即可发送开门指令。'),
                  Text('3. 下方设置项可调整反馈信息与刷新策略。'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildSwitchTile(
            title: '展示上次开门结果',
            subtitle: '在微件底部显示最近一次开门的状态与时间',
            value: _settings.showLastResult,
            onChanged: (bool value) =>
                _applySettings(_settings.copyWith(showLastResult: value)),
          ),
          _buildSwitchTile(
            title: '滑动时启用震动反馈',
            subtitle: '在支持的设备上提供细微震动提示',
            value: _settings.enableHaptics,
            onChanged: (bool value) =>
                _applySettings(_settings.copyWith(enableHaptics: value)),
          ),
          _buildSwitchTile(
            title: '开启自动刷新',
            subtitle: '定时刷新以防止数据与应用状态不同步',
            value: _settings.autoRefreshEnabled,
            onChanged: (bool value) =>
                _applySettings(_settings.copyWith(autoRefreshEnabled: value)),
          ),
          _buildRefreshDropdown(),
          if (_updating)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('正在同步配置…'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
