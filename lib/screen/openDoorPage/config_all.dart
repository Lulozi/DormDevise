import 'package:flutter/material.dart';

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final List<Tab> _tabs = const [
    Tab(text: 'WiFi设置'),
    Tab(text: 'MQTT设置'),
    Tab(text: '定位设置'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('全部设置'),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs,
          indicatorColor: Theme.of(context).colorScheme.primary,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildWifiSetting(context),
          _buildMqttSetting(context),
          _buildLocationSetting(context),
        ],
      ),
    );
  }

  Widget _buildWifiSetting(BuildContext context) {
    return Center(
      child: FilledButton.icon(
        onPressed: () {
          // TODO: 实现WiFi设置逻辑
        },
        icon: const Icon(Icons.wifi),
        label: const Text('配置WiFi'),
        style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
      ),
    );
  }

  Widget _buildMqttSetting(BuildContext context) {
    return Center(
      child: FilledButton.icon(
        onPressed: () {
          // TODO: 实现MQTT设置逻辑
        },
        icon: const Icon(Icons.settings_ethernet),
        label: const Text('配置MQTT'),
        style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
      ),
    );
  }

  Widget _buildLocationSetting(BuildContext context) {
    return Center(
      child: FilledButton.icon(
        onPressed: () {
          // TODO: 实现定位设置逻辑
        },
        icon: const Icon(Icons.location_on),
        label: const Text('配置定位'),
        style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
      ),
    );
  }
}
