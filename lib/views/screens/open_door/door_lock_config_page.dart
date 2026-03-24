import 'package:flutter/material.dart';

import 'local_door_lock_settings_page.dart';
import 'mqtt_settings_page.dart';

/// 门锁配置页，集中承载 HTTP 与 MQTT 两类开门配置。
class OpenDoorSettingsPage extends StatefulWidget {
  const OpenDoorSettingsPage({super.key, this.initialTabIndex = 0});

  /// 指定初始展示的标签索引，默认显示 HTTP 配置。
  final int initialTabIndex;

  @override
  State<OpenDoorSettingsPage> createState() => _OpenDoorSettingsPageState();
}

class _OpenDoorSettingsPageState extends State<OpenDoorSettingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final List<Tab> _tabs = const [Tab(text: 'HTTP配置'), Tab(text: 'MQTT配置')];

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

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('门锁配置'),
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
        children: const <Widget>[
          LocalDoorLockSettingsPage(showAppBar: false),
          MqttSettingsPage(showAppBar: false),
        ],
      ),
    );
  }
}
