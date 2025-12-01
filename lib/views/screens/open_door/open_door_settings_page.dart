import 'local_door_lock_settings_page.dart';
import 'mqtt_settings_page.dart';
import 'package:flutter/material.dart';

/// 开门相关设置页，整合多项配置标签。
class OpenDoorSettingsPage extends StatefulWidget {
  const OpenDoorSettingsPage({super.key, this.initialTabIndex = 0});

  /// 指定初始展示的标签索引，默认显示第一个标签。
  final int initialTabIndex;

  /// 创建状态对象以驱动标签页控制器。
  @override
  State<OpenDoorSettingsPage> createState() => _OpenDoorSettingsPageState();
}

class _OpenDoorSettingsPageState extends State<OpenDoorSettingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final List<Tab> _tabs = const [Tab(text: '本地门锁配置'), Tab(text: 'MQTT 设置')];

  /// 初始化标签控制器。
  @override
  void initState() {
    super.initState();
    final int initialIndex = widget.initialTabIndex.clamp(0, _tabs.length - 1);
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: initialIndex,
    );
  }

  /// 释放标签控制器资源。
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 构建包含标签导航与内容的界面。
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('全部设置'),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs,
          indicatorColor: colorScheme.primary,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          LocalDoorLockSettingsPage(showAppBar: false),
          MqttSettingsPage(showAppBar: false),
        ],
      ),
    );
  }
}
