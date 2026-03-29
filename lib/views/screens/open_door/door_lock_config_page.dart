import 'dart:convert';

import 'package:dormdevise/models/local_door_lock_config.dart';
import 'package:dormdevise/models/mqtt_config.dart';
import 'package:dormdevise/services/door_widget_service.dart';
import 'package:dormdevise/services/local_door_lock_config_service.dart';
import 'package:dormdevise/services/mqtt_config_service.dart';
import 'package:dormdevise/utils/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'door_config_share_sheet.dart';
import 'local_door_lock_settings_page.dart';
import 'mqtt_settings_page.dart';

/// 门锁配置页，集中承载 HTTP 与 MQTT 两类开门配置。
class OpenDoorSettingsPage extends StatefulWidget {
  const OpenDoorSettingsPage({
    super.key,
    this.initialTabIndex = 0,
    this.initialImportPayload,
  });

  /// 指定初始展示的标签索引，默认显示 HTTP 配置。
  final int initialTabIndex;

  /// 如果通过外部跳转携带了门锁配置文本（JSON），页面加载后会询问是否导入该配置。
  final String? initialImportPayload;

  /// 尝试在给定的上下文中切换到门锁配置页的指定标签（若该页面存在）。
  ///
  /// 该方法对外提供一个安全的入口，允许从子页面或弹窗中请求父页面切换到 HTTP/MQTT 标签。
  static void switchToTabIfExists(BuildContext context, int index) {
    try {
      final _OpenDoorSettingsPageState? state = context
          .findAncestorStateOfType<_OpenDoorSettingsPageState>();
      if (state != null) {
        state._switchToTab(index);
      }
    } catch (_) {
      // ignore: intentionally swallow errors when ancestor not found
    }
  }

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
    // 如果页面是通过跳转并携带了初始导入文本，则在首帧后询问用户是否导入
    if (widget.initialImportPayload != null &&
        widget.initialImportPayload!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final bool? confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('检测到门锁配置'),
              content: const Text('检测到分享的门锁配置，是否导入此配置？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('导入'),
                ),
              ],
            );
          },
        );
        if (confirmed == true && mounted) {
          await _importConfigFromText(widget.initialImportPayload!);
        }
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _switchToTab(int index) {
    if (!mounted) return;
    final int newIndex = index.clamp(0, _tabs.length - 1);
    if (_tabController.index != newIndex) {
      _tabController.animateTo(newIndex);
    }
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
            icon: const Icon(FontAwesomeIcons.retweet, size: 20),
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
    final LocalDoorLockConfig localConfig = await LocalDoorLockConfigService
        .instance
        .loadConfig(forceRefresh: true);
    final MqttConfig mqttConfig = await MqttConfigService.instance.loadConfig(
      forceRefresh: true,
    );
    final Map<String, Object?> mqttMap = Map<String, Object?>.from(
      mqttConfig.toStorageMap(),
    )..remove('mqtt_clientId');
    final Map<String, Object?> payload = <String, Object?>{
      'door_lock_bundle_version': 1,
      ...localConfig.toSharePayload(),
      ...mqttMap,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<void> _importConfigFromText(String raw) async {
    final String text = raw.trim();
    if (text.isEmpty) {
      if (!mounted) {
        return;
      }
      AppToast.show(context, '导入内容为空', variant: AppToastVariant.warning);
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
        final MqttConfig currentConfig = await MqttConfigService.instance
            .loadConfig(forceRefresh: true);
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
      // 若导入内容仅包含某一类配置，则自动切到对应标签以便用户查看
      if (hasLocalConfig && !hasMqttConfig) {
        _switchToTab(0);
      } else if (hasMqttConfig && !hasLocalConfig) {
        _switchToTab(1);
      }

      setState(() {
        _pageRevision++;
      });
      AppToast.show(context, '门锁配置已导入并保存', variant: AppToastVariant.success);
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppToast.show(context, '导入失败：$error', variant: AppToastVariant.error);
    }
  }
}
