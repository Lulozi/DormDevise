import 'package:dormdevise/screens/open_door/location_settings_page.dart';
import 'package:dormdevise/screens/open_door/mqtt_settings_page.dart';
import 'package:dormdevise/screens/open_door/wifi_settings_page.dart';
import 'package:flutter/material.dart';

/// 开门相关设置页，整合多项配置标签。
class OpenDoorSettingsPage extends StatefulWidget {
  const OpenDoorSettingsPage({super.key});

  /// 创建状态对象以驱动标签页控制器。
  @override
  State<OpenDoorSettingsPage> createState() => _OpenDoorSettingsPageState();
}

class _OpenDoorSettingsPageState extends State<OpenDoorSettingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final List<Tab> _tabs = const [
    Tab(text: 'Wi-Fi 设置'),
    Tab(text: 'MQTT 设置'),
    Tab(text: '定位设置'),
  ];

  /// 初始化标签控制器。
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
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
          WifiSettingsPage(),
          MqttSettingsPage(),
          LocationSettingsPage(),
        ],
      ),
    );
  }
}
