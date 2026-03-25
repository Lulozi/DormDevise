import 'dart:convert';

import 'package:dormdevise/models/local_door_lock_config.dart';
import 'package:dormdevise/models/mqtt_config.dart';
import 'package:dormdevise/services/door_widget_service.dart';
import 'package:dormdevise/services/local_door_lock_config_service.dart';
import 'package:dormdevise/services/mqtt_config_service.dart';
import 'package:dormdevise/utils/app_toast.dart';
import 'package:flutter/material.dart';

import 'door_config_share_sheet.dart';
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
  int _pageRevision = 0;

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
        actions: <Widget>[
          IconButton(
            tooltip: '分享/导入整套门锁配置',
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: _openShareImportMenu,
          ),
        ],
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
        children: <Widget>[
          LocalDoorLockSettingsPage(
            key: ValueKey<String>('http-$_pageRevision'),
            showAppBar: false,
          ),
          MqttSettingsPage(
            key: ValueKey<String>('mqtt-$_pageRevision'),
            showAppBar: false,
          ),
        ],
      ),
    );
  }

  Future<void> _openShareImportMenu() async {
    final String payload = await _buildSharePayloadText();
    if (!mounted) {
      return;
    }
    await DoorConfigShareSheet.show(
      context: context,
      configLabel: '门锁配置',
      payload: payload,
      onImport: _importConfigFromText,
    );
  }

  Future<String> _buildSharePayloadText() async {
    final LocalDoorLockConfig localConfig =
        await LocalDoorLockConfigService.instance.loadConfig(forceRefresh: true);
    final MqttConfig mqttConfig =
        await MqttConfigService.instance.loadConfig(forceRefresh: true);
    final Map<String, Object?> payload = <String, Object?>{
      'door_lock_bundle_version': 1,
      ...localConfig.toSharePayload(),
      ...mqttConfig.toStorageMap(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<void> _importConfigFromText(String raw) async {
    final String text = raw.trim();
    if (text.isEmpty) {
      if (!mounted) {
        return;
      }
      AppToast.show(
        context,
        '导入内容为空',
        variant: AppToastVariant.warning,
      );
      return;
    }

    try {
      final dynamic decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw const FormatException('不是有效的配置对象');
      }

      final bool hasLocalConfig = decoded.keys.any(
        (dynamic key) => key.toString().startsWith('local_'),
      );
      final bool hasMqttConfig = decoded.keys.any((dynamic key) {
        final String normalizedKey = key.toString();
        return normalizedKey.startsWith('mqtt_') ||
            normalizedKey == 'custom_open_msg';
      });

      if (!hasLocalConfig && !hasMqttConfig) {
        throw const FormatException('未识别到可导入的门锁配置');
      }

      if (hasLocalConfig) {
        final LocalDoorLockConfig localConfig =
            LocalDoorLockConfig.fromSharePayload(decoded);
        await LocalDoorLockConfigService.instance.saveConfig(localConfig);
      }

      if (hasMqttConfig) {
        final MqttConfig currentConfig =
            await MqttConfigService.instance.loadConfig(forceRefresh: true);
        final MqttConfig importedConfig = MqttConfig.fromStorage(
          Map<String, Object?>.from(decoded),
        );
        await MqttConfigService.instance.saveConfig(
          importedConfig.clientId.isEmpty
              ? importedConfig.copyWith(clientId: currentConfig.clientId)
              : importedConfig,
        );
        await DoorWidgetService.instance.refreshStatusListener();
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _pageRevision++;
      });
      AppToast.show(
        context,
        '门锁配置已导入并保存',
        variant: AppToastVariant.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppToast.show(
        context,
        '导入失败：$error',
        variant: AppToastVariant.error,
      );
    }
  }
}
