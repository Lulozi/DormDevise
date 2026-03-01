import 'package:dormdevise/models/local_door_lock_config.dart';
import 'package:dormdevise/services/local_door_lock_config_service.dart';
import 'package:dormdevise/services/wifi_info_service.dart';
import 'package:flutter/material.dart';

/// 本地门锁配置页面。
///
/// 提供 Post 请求开门配置、WiFi 搜索与保存、请求优先级设置等能力。
class LocalDoorLockSettingsPage extends StatefulWidget {
  const LocalDoorLockSettingsPage({super.key, this.showAppBar = true});

  /// 是否显示顶部 AppBar，嵌入 Tab 时可隐藏。
  final bool showAppBar;

  @override
  State<LocalDoorLockSettingsPage> createState() =>
      _LocalDoorLockSettingsPageState();
}

class _LocalDoorLockSettingsPageState extends State<LocalDoorLockSettingsPage> {
  bool _loading = true;
  bool _saving = false;

  bool _postEnabled = false;
  bool _preferPostWhenWifiMatched = true;
  late final TextEditingController _postUrlController;

  List<SavedWifiInfo> _savedWifis = <SavedWifiInfo>[];
  WifiSnapshot _currentWifi = const WifiSnapshot();

  @override
  void initState() {
    super.initState();
    _postUrlController = TextEditingController();
    _loadConfig();
  }

  @override
  void dispose() {
    _postUrlController.dispose();
    super.dispose();
  }

  /// 加载本地门锁配置并尝试读取当前 WiFi。
  Future<void> _loadConfig() async {
    final config = await LocalDoorLockConfigService.instance.loadConfig(
      forceRefresh: true,
    );
    final wifi = await WifiInfoService.instance.getCurrentWifi();
    if (!mounted) return;
    setState(() {
      _postEnabled = config.postEnabled;
      _preferPostWhenWifiMatched = config.preferPostWhenWifiMatched;
      _postUrlController.text = config.postUrl;
      _savedWifis = List<SavedWifiInfo>.from(config.savedWifis);
      _currentWifi = wifi;
      _loading = false;
    });
  }

  /// 搜索当前连接 WiFi。
  Future<void> _searchCurrentWifi() async {
    final wifi = await WifiInfoService.instance.getCurrentWifi(
      requestPermission: true,
    );
    if (!mounted) return;
    setState(() {
      _currentWifi = wifi;
    });
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          wifi.hasValidValue
              ? '已获取当前 WiFi：${wifi.ssid.isNotEmpty ? wifi.ssid : wifi.bssid}'
              : '未检测到可用 WiFi 信息，请检查定位权限与网络状态',
        ),
      ),
    );
  }

  /// 保存当前配置到本地存储。
  Future<void> _saveConfig({String? successMessage}) async {
    if (_saving) return;
    setState(() {
      _saving = true;
    });

    final config = LocalDoorLockConfig(
      postEnabled: _postEnabled,
      postUrl: _postUrlController.text.trim(),
      preferPostWhenWifiMatched: _preferPostWhenWifiMatched,
      savedWifis: List<SavedWifiInfo>.from(_savedWifis),
    );
    await LocalDoorLockConfigService.instance.saveConfig(config);

    if (!mounted) return;
    setState(() {
      _saving = false;
    });

    if (successMessage != null && successMessage.isNotEmpty) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    }
  }

  /// 判断当前 WiFi 是否已经存在于已保存列表。
  bool _isCurrentWifiSaved() {
    return LocalDoorLockConfig(
      postEnabled: _postEnabled,
      postUrl: _postUrlController.text,
      preferPostWhenWifiMatched: _preferPostWhenWifiMatched,
      savedWifis: _savedWifis,
    ).isWifiMatched(ssid: _currentWifi.ssid, bssid: _currentWifi.bssid);
  }

  /// 保存当前 WiFi 到列表并立即持久化。
  Future<void> _saveCurrentWifi() async {
    final String ssid = LocalDoorLockConfig.normalizeWifiValue(
      _currentWifi.ssid,
    );
    final String bssid = LocalDoorLockConfig.normalizeWifiValue(
      _currentWifi.bssid,
    );
    if (ssid.isEmpty && bssid.isEmpty) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('请先搜索并获取可用 WiFi 信息')),
      );
      return;
    }

    final exists = _savedWifis.any((wifi) {
      final sameBssid =
          bssid.isNotEmpty && wifi.bssid.isNotEmpty && wifi.bssid == bssid;
      final sameSsid =
          ssid.isNotEmpty && wifi.ssid.isNotEmpty && wifi.ssid == ssid;
      return sameBssid || sameSsid;
    });
    if (exists) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('该 WiFi 已保存')));
      return;
    }

    setState(() {
      _savedWifis = List<SavedWifiInfo>.from(_savedWifis)
        ..add(SavedWifiInfo(ssid: ssid, bssid: bssid));
    });
    await _saveConfig(successMessage: '已保存当前 WiFi');
  }

  /// 删除指定索引的已保存 WiFi。
  Future<void> _removeWifiAt(int index) async {
    final updated = List<SavedWifiInfo>.from(_savedWifis)..removeAt(index);
    setState(() {
      _savedWifis = updated;
    });
    await _saveConfig(successMessage: '已删除 WiFi');
  }

  Widget _buildPostConfigCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.http, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Post请求开门',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用 Post 请求开门'),
              value: _postEnabled,
              onChanged: (value) {
                setState(() {
                  _postEnabled = value;
                });
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _postUrlController,
              enabled: _postEnabled,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Post请求地址',
                hintText: '例如: http://192.168.1.10:8080/open',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('WiFi匹配后优先使用Post请求'),
              subtitle: const Text('关闭后将优先使用 MQTT，失败时再尝试 Post'),
              value: _preferPostWhenWifiMatched,
              onChanged: _postEnabled
                  ? (value) {
                      setState(() {
                        _preferPostWhenWifiMatched = value;
                      });
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWifiCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentSsid = _currentWifi.ssid;
    final currentBssid = _currentWifi.bssid;
    final hasCurrentWifi = _currentWifi.hasValidValue;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'WiFi信息',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton.icon(
                  onPressed: _searchCurrentWifi,
                  icon: const Icon(Icons.search, size: 16),
                  label: const Text('搜索'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    hasCurrentWifi ? Icons.wifi : Icons.wifi_off,
                    size: 18,
                    color: hasCurrentWifi
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasCurrentWifi
                          ? '当前：${currentSsid.isNotEmpty ? currentSsid : currentBssid}'
                          : '当前未检测到 WiFi',
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
            if (hasCurrentWifi && currentBssid.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'BSSID：$currentBssid',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: hasCurrentWifi && !_isCurrentWifiSaved()
                    ? _saveCurrentWifi
                    : null,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('保存当前WiFi'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '已保存 WiFi（命中后可按优先级选择 Post/MQTT）',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (_savedWifis.isEmpty)
              Text(
                '暂无已保存 WiFi',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              )
            else
              ListView.separated(
                key: const ValueKey('saved_wifi_list'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _savedWifis.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final wifi = _savedWifis[index];
                  return Container(
                    key: ValueKey('saved_wifi_${wifi.identity}_$index'),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      dense: true,
                      title: Text(wifi.displayName),
                      subtitle: wifi.bssid.isNotEmpty
                          ? Text('BSSID: ${wifi.bssid}')
                          : null,
                      trailing: IconButton(
                        tooltip: '删除',
                        onPressed: () => _removeWifiAt(index),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: widget.showAppBar ? AppBar(title: const Text('本地门锁配置')) : null,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('本地门锁配置')) : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPostConfigCard(context),
          const SizedBox(height: 12),
          _buildWifiCard(context),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving
                ? null
                : () async {
                    await _saveConfig(successMessage: '本地门锁配置已保存');
                  },
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? '保存中...' : '保存配置'),
          ),
        ],
      ),
    );
  }
}
