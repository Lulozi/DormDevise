import 'dart:convert';
import 'dart:math' as math;

import 'package:dormdevise/models/local_door_lock_config.dart';
import 'package:dormdevise/services/local_door_lock_config_service.dart';
import 'package:dormdevise/services/wifi_info_service.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'door_config_share_sheet.dart';

/// HTTP配置页面。
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
  String _status = '';
  bool _statusIsError = false;
  IconData _statusIcon = Icons.check_circle_outline;

  bool _postEnabled = false;
  bool _preferPostWhenWifiMatched = true;
  bool _multiPostEnabled = false;
  late final TextEditingController _postUrlController;
  GlobalKey<AnimatedListState> _savedWifiListKey =
      GlobalKey<AnimatedListState>();
  GlobalKey<AnimatedListState> _mappingListKey = GlobalKey<AnimatedListState>();
  GlobalKey<AnimatedListState> _postUrlListKey = GlobalKey<AnimatedListState>();
  StateSetter? _postOverlaySetState;
  final GlobalKey _wifiCardKey = GlobalKey();
  final GlobalKey _wifiDropdownTargetKey = GlobalKey();
  final GlobalKey _postDropdownTargetKey = GlobalKey();
  final LayerLink _wifiDropdownLink = LayerLink();
  final LayerLink _postDropdownLink = LayerLink();
  OverlayEntry? _wifiDropdownEntry;
  OverlayEntry? _postDropdownEntry;

  List<SavedWifiInfo> _savedWifis = <SavedWifiInfo>[];
  List<String> _savedPostUrls = <String>[];
  List<WifiPostMapping> _wifiPostMappings = <WifiPostMapping>[];
  String? _selectedPostUrl;
  bool _postAddressListExpanded = false;
  List<WifiSnapshot> _searchedWifis = <WifiSnapshot>[];
  bool _searchedWifiExpanded = false;
  Set<String> _selectedWifiIdentities = <String>{};
  WifiSnapshot _currentWifi = const WifiSnapshot();

  @override
  void initState() {
    super.initState();
    _postUrlController = TextEditingController();
    _loadConfig();
  }

  @override
  void dispose() {
    _hideSearchedWifiOverlay();
    _hidePostAddressOverlay();
    _postUrlController.dispose();
    super.dispose();
  }

  /// 使用与 MQTT 配置页一致的底部状态条样式。
  void _showStatus(String message, {bool isError = false, IconData? icon}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _status = message;
      _statusIsError = isError;
      _statusIcon =
          icon ?? (isError ? Icons.error_outline : Icons.check_circle_outline);
    });
  }

  void _hideSearchedWifiOverlay() {
    _wifiDropdownEntry?.remove();
    _wifiDropdownEntry = null;
    if (!mounted) {
      return;
    }
    if (_searchedWifiExpanded) {
      setState(() {
        _searchedWifiExpanded = false;
      });
    }
  }

  void _showSearchedWifiOverlay() {
    if (!mounted || _searchedWifis.isEmpty) {
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    final media = MediaQuery.of(context);
    final targetBox =
        _wifiDropdownTargetKey.currentContext?.findRenderObject() as RenderBox?;
    final wifiCardBox =
        _wifiCardKey.currentContext?.findRenderObject() as RenderBox?;
    final targetWidth = targetBox?.size.width ?? 260.0;
    final targetTop = targetBox?.localToGlobal(Offset.zero).dy ?? 0;
    final targetBottom = targetTop + (targetBox?.size.height ?? 0);
    final cardTop = wifiCardBox?.localToGlobal(Offset.zero).dy;
    final cardBottom = cardTop != null
        ? cardTop + (wifiCardBox?.size.height ?? 0)
        : null;
    final availableInCard = (cardBottom ?? double.infinity) - targetBottom - 12;
    final availableOnScreen =
        media.size.height - targetBottom - media.viewPadding.bottom - 12;

    final cappedByCard = availableInCard.isFinite
        ? math.max(0.0, availableInCard)
        : math.max(0.0, availableOnScreen);
    final cappedByScreen = math.max(0.0, availableOnScreen);
    final preferredFixedHeight = 220.0;
    final dynamicMaxHeight = math.min(
      preferredFixedHeight,
      math.min(cappedByCard, cappedByScreen),
    );
    final panelMaxHeight = dynamicMaxHeight > 0
        ? dynamicMaxHeight
        : math.min(preferredFixedHeight, cappedByScreen);

    _wifiDropdownEntry?.remove();
    _wifiDropdownEntry = OverlayEntry(
      builder: (overlayContext) {
        final colorScheme = Theme.of(context).colorScheme;
        return Positioned.fill(
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _hideSearchedWifiOverlay,
              ),
              CompositedTransformFollower(
                link: _wifiDropdownLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.bottomLeft,
                followerAnchor: Alignment.topLeft,
                offset: const Offset(0, 8),
                child: Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: targetWidth,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: panelMaxHeight),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.35,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                              color: colorScheme.shadow.withValues(alpha: 0.12),
                            ),
                          ],
                        ),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: _searchedWifis.length,
                          itemBuilder: (context, index) {
                            final item = _searchedWifis[index];
                            final displayName = item.ssid.isNotEmpty
                                ? item.ssid
                                : item.bssid;
                            return ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              leading: const Icon(Icons.wifi, size: 18),
                              title: Text(displayName),
                              subtitle: item.bssid.isNotEmpty
                                  ? Text(
                                      'BSSID: ${item.bssid}',
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    )
                                  : null,
                              trailing: const Icon(
                                Icons.north_west_rounded,
                                size: 16,
                              ),
                              onTap: () => _selectSearchedWifi(item),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    overlay.insert(_wifiDropdownEntry!);
  }

  void _hidePostAddressOverlay() {
    _postDropdownEntry?.remove();
    _postDropdownEntry = null;
    if (!mounted) {
      return;
    }
    if (_postAddressListExpanded) {
      setState(() {
        _postAddressListExpanded = false;
      });
    }
  }

  void _showPostAddressOverlay() {
    if (!mounted || _savedPostUrls.isEmpty) {
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    final media = MediaQuery.of(context);
    final targetBox =
        _postDropdownTargetKey.currentContext?.findRenderObject() as RenderBox?;
    final targetWidth = targetBox?.size.width ?? 260.0;
    final targetTop = targetBox?.localToGlobal(Offset.zero).dy ?? 0;
    final targetBottom = targetTop + (targetBox?.size.height ?? 0);
    final availableOnScreen =
        media.size.height - targetBottom - media.viewPadding.bottom - 12;
    final panelMaxHeight = math.min(220.0, math.max(0.0, availableOnScreen));

    _postDropdownEntry?.remove();
    _postDropdownEntry = OverlayEntry(
      builder: (overlayContext) {
        final colorScheme = Theme.of(context).colorScheme;
        return Positioned.fill(
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _hidePostAddressOverlay,
              ),
              CompositedTransformFollower(
                link: _postDropdownLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.bottomLeft,
                followerAnchor: Alignment.topLeft,
                offset: const Offset(0, 8),
                child: Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: targetWidth,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: panelMaxHeight),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.35,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                              color: colorScheme.shadow.withValues(alpha: 0.12),
                            ),
                          ],
                        ),
                        child: StatefulBuilder(
                          builder: (context, setOverlayState) {
                            _postOverlaySetState = setOverlayState;
                            return AnimatedList(
                              key: _postUrlListKey,
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              initialItemCount: _savedPostUrls.length,
                              itemBuilder: (context, index, animation) {
                                final postUrl = _savedPostUrls[index];
                                return _buildPostUrlTile(
                                  postUrl,
                                  animation,
                                  colorScheme,
                                  isRemoval: false,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    overlay.insert(_postDropdownEntry!);
  }

  Widget _buildPostUrlTile(
    String postUrl,
    Animation<double> animation,
    ColorScheme colorScheme, {
    required bool isRemoval,
  }) {
    final selected = postUrl == _selectedPostUrl;
    return SizeTransition(
      sizeFactor: animation,
      child: FadeTransition(
        opacity: animation,
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(
            selected ? Icons.check_circle_rounded : Icons.link,
            size: 18,
            color: selected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          title: Text(postUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            tooltip: '删除',
            onPressed: isRemoval ? null : () => _removePostUrl(postUrl),
            icon: const Icon(Icons.delete_outline),
          ),
          onTap: isRemoval ? null : () => _selectSavedPostUrl(postUrl),
        ),
      ),
    );
  }

  void _togglePostAddressOverlay() {
    if (_postAddressListExpanded) {
      _hidePostAddressOverlay();
      return;
    }
    if (_savedPostUrls.isEmpty) {
      _showStatus('当前无保存的post地址', isError: true, icon: Icons.info_outline);
      return;
    }
    setState(() {
      _postAddressListExpanded = true;
    });
    _showPostAddressOverlay();
  }

  Future<void> _handleCurrentWifiCardTap() async {
    await _searchCurrentWifi(
      openDropdownAfterSearch: true,
      showResultStatus: false,
    );
    if (_searchedWifis.isEmpty) {
      _showStatus('未扫描到附近 WiFi，请检查权限或稍后重试', isError: true);
    }
  }

  /// 加载HTTP配置并尝试读取当前 WiFi。
  Future<void> _loadConfig() async {
    final config = await LocalDoorLockConfigService.instance.loadConfig(
      forceRefresh: true,
    );
    final wifi = await WifiInfoService.instance.getCurrentWifi();
    if (!mounted) return;
    setState(() {
      _resetAnimatedListKeys();
      _postEnabled = config.postEnabled;
      _preferPostWhenWifiMatched = config.preferPostWhenWifiMatched;
      _multiPostEnabled = config.multiPostEnabled;
      _postUrlController.text = config.postUrl;
      _savedPostUrls = List<String>.from(config.savedPostUrls);
      _savedWifis = List<SavedWifiInfo>.from(config.savedWifis);
      _wifiPostMappings = List<WifiPostMapping>.from(config.wifiPostMappings);

      final currentUrl = config.postUrl.trim();
      _selectedPostUrl = _savedPostUrls.contains(currentUrl)
          ? currentUrl
          : (_savedPostUrls.isNotEmpty ? _savedPostUrls.first : null);
      _selectedWifiIdentities = config.savedWifis
          .map((wifi) => wifi.identity)
          .where((identity) => identity.isNotEmpty)
          .toSet();
      _currentWifi = wifi;
      _loading = false;
    });
  }

  /// 搜索当前连接 WiFi 及附近 WiFi。
  Future<void> _searchCurrentWifi({
    bool openDropdownAfterSearch = false,
    bool showResultStatus = true,
  }) async {
    final currentWifi = await WifiInfoService.instance.getCurrentWifi(
      requestPermission: true,
    );
    final nearbyWifis = await WifiInfoService.instance.scanNearbyWifis(
      requestPermission: true,
    );
    if (!mounted) return;
    setState(() {
      _currentWifi = currentWifi;
      _searchedWifis = List<WifiSnapshot>.from(nearbyWifis);
      if (currentWifi.hasValidValue) {
        _appendSearchedWifi(currentWifi);
      }
      _searchedWifiExpanded = false;
    });
    _hideSearchedWifiOverlay();
    if (openDropdownAfterSearch && _searchedWifis.isNotEmpty) {
      setState(() {
        _searchedWifiExpanded = true;
      });
      _showSearchedWifiOverlay();
    }
    final currentName = currentWifi.ssid.isNotEmpty
        ? currentWifi.ssid
        : currentWifi.bssid;
    final message = currentWifi.hasValidValue
        ? '已获取当前 WiFi：$currentName\n附近可用 WiFi：${_searchedWifis.length} 个'
        : '未检测到当前连接 WiFi\n附近可用 WiFi：${_searchedWifis.length} 个';
    if (showResultStatus) {
      _showStatus(
        message,
        isError: !currentWifi.hasValidValue && _searchedWifis.isEmpty,
        icon: currentWifi.hasValidValue
            ? Icons.wifi
            : (_searchedWifis.isNotEmpty
                  ? Icons.wifi_find_outlined
                  : Icons.info_outline),
      );
    }
  }

  /// 将有效 WiFi 加入搜索历史（按 SSID/BSSID 去重，最近搜索排最前）。
  void _appendSearchedWifi(WifiSnapshot wifi) {
    if (!wifi.hasValidValue) {
      return;
    }
    final normalizedSsid = LocalDoorLockConfig.normalizeWifiValue(wifi.ssid);
    final normalizedBssid = LocalDoorLockConfig.normalizeWifiValue(wifi.bssid);
    final updated = List<WifiSnapshot>.from(_searchedWifis)
      ..removeWhere((item) {
        final itemSsid = LocalDoorLockConfig.normalizeWifiValue(item.ssid);
        final itemBssid = LocalDoorLockConfig.normalizeWifiValue(item.bssid);
        final sameBssid =
            normalizedBssid.isNotEmpty &&
            itemBssid.isNotEmpty &&
            normalizedBssid == itemBssid;
        final sameSsid =
            normalizedSsid.isNotEmpty &&
            itemSsid.isNotEmpty &&
            normalizedSsid == itemSsid;
        return sameBssid || sameSsid;
      })
      ..insert(0, WifiSnapshot(ssid: normalizedSsid, bssid: normalizedBssid));
    if (updated.length > 8) {
      updated.removeRange(8, updated.length);
    }
    _searchedWifis = updated;
  }

  /// 选择一条搜索历史作为当前 WiFi，便于后续直接保存。
  void _selectSearchedWifi(WifiSnapshot wifi) {
    setState(() {
      _currentWifi = wifi;
      _searchedWifiExpanded = false;
    });
    _hideSearchedWifiOverlay();
  }

  List<String> _collectSavedPostUrls() {
    final urls = <String>[];
    for (final raw in _savedPostUrls) {
      final normalized = raw.trim();
      if (normalized.isEmpty || urls.contains(normalized)) {
        continue;
      }
      urls.add(normalized);
    }
    return urls;
  }

  void _resetAnimatedListKeys() {
    _savedWifiListKey = GlobalKey<AnimatedListState>();
    _mappingListKey = GlobalKey<AnimatedListState>();
    _postUrlListKey = GlobalKey<AnimatedListState>();
  }

  Map<String, dynamic> _buildSharePayload() {
    return _buildCurrentConfig().toSharePayload();
  }

  String _buildSharePayloadText() {
    return const JsonEncoder.withIndent('  ').convert(_buildSharePayload());
  }

  Future<void> _importConfigFromText(String raw) async {
    final String text = raw.trim();
    if (text.isEmpty) {
      _showStatus('导入内容为空', isError: true, icon: Icons.info_outline);
      return;
    }

    try {
      final dynamic decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw const FormatException('不是有效的配置对象');
      }
      final LocalDoorLockConfig importedConfig =
          LocalDoorLockConfig.fromSharePayload(decoded);

      await LocalDoorLockConfigService.instance.saveConfig(importedConfig);
      if (!mounted) {
        return;
      }
      await _loadConfig();
      if (!mounted) {
        return;
      }
      _showStatus('配置已导入并保存');
    } catch (error) {
      _showStatus('导入失败：$error', isError: true);
    }
  }

  Future<void> _openShareImportMenu() async {
    await DoorConfigShareSheet.show(
      context: context,
      configLabel: 'HTTP配置',
      payload: _buildSharePayloadText(),
      onImport: _importConfigFromText,
      allowImport: false,
    );
  }

  void _selectSavedPostUrl(String postUrl) {
    setState(() {
      _selectedPostUrl = postUrl;
    });
    _hidePostAddressOverlay();
  }

  void _removePostUrl(String postUrl) {
    final normalizedUrl = postUrl.trim();
    if (normalizedUrl.isEmpty) {
      return;
    }
    final indexToRemove = _savedPostUrls.indexWhere(
      (element) => element.trim() == normalizedUrl,
    );
    if (indexToRemove == -1) return;

    final removedUrl = _savedPostUrls[indexToRemove];

    _postOverlaySetState?.call(() {
      _savedPostUrls = List<String>.from(_savedPostUrls)
        ..removeAt(indexToRemove);
    });

    _postUrlListKey.currentState?.removeItem(indexToRemove, (
      context,
      animation,
    ) {
      return _buildPostUrlTile(
        removedUrl,
        animation,
        Theme.of(context).colorScheme,
        isRemoval: true,
      );
    }, duration: const Duration(milliseconds: 300));

    setState(() {
      _wifiPostMappings = List<WifiPostMapping>.from(_wifiPostMappings)
        ..removeWhere((mapping) => mapping.normalizedPostUrl == normalizedUrl);

      final availablePostUrls = _collectSavedPostUrls();
      if (_selectedPostUrl == normalizedUrl) {
        _selectedPostUrl = availablePostUrls.isNotEmpty
            ? availablePostUrls.first
            : null;
      }
    });

    Future.delayed(const Duration(milliseconds: 300), () {
      if (_savedPostUrls.isEmpty) {
        _hidePostAddressOverlay();
      }
      // removed `else if (_postAddressListExpanded) { _showPostAddressOverlay(); }`
      // since the animated list will just visually remove it.
    });
  }

  void _removeWifiPostMappingAt(int index) {
    if (index < 0 || index >= _wifiPostMappings.length) {
      return;
    }
    final removed = _wifiPostMappings[index];
    setState(() {
      _wifiPostMappings = List<WifiPostMapping>.from(_wifiPostMappings)
        ..removeAt(index);
    });
    _mappingListKey.currentState?.removeItem(
      index,
      (context, animation) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _buildMappingTile(context, removed, index, animation: animation),
      ),
      duration: const Duration(milliseconds: 220),
    );
  }

  /// 标准化 Post 地址，自动补全 http:// 前缀。
  String _normalizePostUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'http://$trimmed';
  }

  void _addSavedPostUrl() {
    if (!_postEnabled) {
      _showStatus('请先启用 Post 请求开门', isError: true);
      return;
    }

    final url = _normalizePostUrl(_postUrlController.text);
    if (url.isEmpty) {
      _showStatus('请先填写 Post 请求地址', isError: true);
      return;
    }

    final exists = _savedPostUrls.any((item) => item.trim() == url);
    if (exists) {
      _showStatus('该 Post 地址已存在', icon: Icons.info_outline);
      return;
    }

    setState(() {
      _savedPostUrls = List<String>.from(_savedPostUrls)..add(url);
      _selectedPostUrl = url;
      _postUrlController.clear();
    });
    if (_postAddressListExpanded) {
      _showPostAddressOverlay();
    }
    _showStatus('已新增 Post 地址，点击“保存配置”后生效', icon: Icons.info_outline);
  }

  /// 保存当前配置到本地存储。
  Future<void> _saveConfig({String? successMessage}) async {
    if (_saving) return;
    setState(() {
      _saving = true;
    });

    // 仅持久化已勾选的 WiFi，确保开门匹配范围与用户最终确认一致。
    final selectedWifis = _savedWifis.where((wifi) {
      return _selectedWifiIdentities.contains(wifi.identity);
    }).toList();

    // 追踪新增映射以播放插入动画。
    final previousMappingCount = _wifiPostMappings.length;
    final workingMappings = List<WifiPostMapping>.from(_wifiPostMappings);
    int newMappingCount = 0;
    final selectedPostUrl = (_selectedPostUrl ?? '').trim();
    if (_multiPostEnabled && selectedPostUrl.isNotEmpty) {
      for (final wifi in selectedWifis) {
        final newMapping = WifiPostMapping(
          wifi: wifi,
          postUrl: selectedPostUrl,
        );
        final index = workingMappings.indexWhere(
          (item) => item.identity == newMapping.identity,
        );
        if (index >= 0) {
          workingMappings[index] = newMapping;
        } else {
          workingMappings.add(newMapping);
          newMappingCount++;
        }
      }
    }

    final config = _buildCurrentConfig(
      savedWifis: selectedWifis,
      wifiPostMappings: workingMappings,
    );
    await LocalDoorLockConfigService.instance.saveConfig(config);

    if (!mounted) return;
    setState(() {
      _saving = false;
      _savedPostUrls = List<String>.from(config.savedPostUrls);
      _wifiPostMappings = workingMappings;
      final availablePostUrls = _collectSavedPostUrls();
      if (_selectedPostUrl == null ||
          _selectedPostUrl!.isEmpty ||
          !availablePostUrls.contains(_selectedPostUrl)) {
        _selectedPostUrl = availablePostUrls.isNotEmpty
            ? availablePostUrls.first
            : null;
      }
    });

    // 为新增的映射播放插入动画。
    for (int i = 0; i < newMappingCount; i++) {
      _mappingListKey.currentState?.insertItem(
        previousMappingCount + i,
        duration: const Duration(milliseconds: 260),
      );
    }

    if (successMessage != null && successMessage.isNotEmpty) {
      _showStatus(successMessage, icon: Icons.check_circle_outline);
    }
  }

  /// 判断当前 WiFi 是否已经存在于已保存列表。
  bool _isCurrentWifiSaved() {
    return _buildCurrentConfig().isWifiMatched(
      ssid: _currentWifi.ssid,
      bssid: _currentWifi.bssid,
    );
  }

  LocalDoorLockConfig _buildCurrentConfig({
    List<SavedWifiInfo>? savedWifis,
    List<WifiPostMapping>? wifiPostMappings,
  }) {
    return LocalDoorLockConfig(
      postEnabled: _postEnabled,
      postUrl: _normalizePostUrl(_postUrlController.text),
      preferPostWhenWifiMatched: _preferPostWhenWifiMatched,
      multiPostEnabled: _multiPostEnabled,
      wifiPostEnabled: _multiPostEnabled,
      savedPostUrls: _collectSavedPostUrls(),
      savedWifis: savedWifis ?? _savedWifis,
      wifiPostMappings: wifiPostMappings ?? _wifiPostMappings,
    );
  }

  bool _isWifiSelected(SavedWifiInfo wifi) {
    return _selectedWifiIdentities.contains(wifi.identity);
  }

  void _toggleWifiSelection(SavedWifiInfo wifi) {
    setState(() {
      final nextSelected = Set<String>.from(_selectedWifiIdentities);
      if (nextSelected.contains(wifi.identity)) {
        nextSelected.remove(wifi.identity);
      } else {
        nextSelected.add(wifi.identity);
      }
      _selectedWifiIdentities = nextSelected;
    });
  }

  Widget _buildSavedWifiTile(
    BuildContext context,
    SavedWifiInfo wifi,
    int index, {
    Animation<double>? animation,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _isWifiSelected(wifi);
    // WiFi 卡片启用状态影响交互。
    final wifiCardEnabled = _postEnabled && _multiPostEnabled;
    final tile = Container(
      key: ValueKey('saved_wifi_${wifi.identity}_$index'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? colorScheme.secondary.withValues(alpha: 0.6)
              : colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
        ),
        child: ListTile(
          dense: true,
          onTap: wifiCardEnabled ? () => _toggleWifiSelection(wifi) : null,
          onLongPress: wifiCardEnabled
              ? () => _toggleWifiSelection(wifi)
              : null,
          leading: Icon(
            isSelected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: isSelected
                ? colorScheme.secondary
                : colorScheme.onSurfaceVariant,
          ),
          title: Text(wifi.displayName),
          subtitle: Text(
            wifi.bssid.isNotEmpty ? 'BSSID: ${wifi.bssid}' : '仅SSID匹配',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          trailing: IconButton(
            tooltip: '删除',
            onPressed: wifiCardEnabled ? () => _removeWifiAt(index) : null,
            icon: const Icon(Icons.delete_outline),
          ),
        ),
      ),
    );

    if (animation == null) {
      return tile;
    }

    return SizeTransition(
      sizeFactor: animation,
      axisAlignment: -1,
      child: FadeTransition(opacity: animation, child: tile),
    );
  }

  /// 保存当前 WiFi 到列表（本地预览），最终由“保存配置”统一持久化。
  void _saveCurrentWifi() {
    final String ssid = LocalDoorLockConfig.normalizeWifiValue(
      _currentWifi.ssid,
    );
    final String bssid = LocalDoorLockConfig.normalizeWifiValue(
      _currentWifi.bssid,
    );
    if (ssid.isEmpty && bssid.isEmpty) {
      _showStatus('请先搜索并获取可用 WiFi 信息', isError: true);
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
      _showStatus('该 WiFi 已保存', icon: Icons.info_outline);
      return;
    }

    final newWifi = SavedWifiInfo(ssid: ssid, bssid: bssid);
    setState(() {
      _savedWifis = List<SavedWifiInfo>.from(_savedWifis)..add(newWifi);
      _selectedWifiIdentities = Set<String>.from(_selectedWifiIdentities)
        ..add(newWifi.identity);
    });
    _savedWifiListKey.currentState?.insertItem(
      _savedWifis.length - 1,
      duration: const Duration(milliseconds: 260),
    );
    _showStatus('已添加当前 WiFi，请点击“保存配置”生效');
  }

  /// 删除指定索引的已保存 WiFi。
  void _removeWifiAt(int index) {
    if (index < 0 || index >= _savedWifis.length) {
      return;
    }
    final removed = _savedWifis[index];
    setState(() {
      _savedWifis = List<SavedWifiInfo>.from(_savedWifis)..removeAt(index);
      _selectedWifiIdentities = Set<String>.from(_selectedWifiIdentities)
        ..remove(removed.identity);
    });
    _savedWifiListKey.currentState?.removeItem(
      index,
      (context, animation) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _buildSavedWifiTile(
          context,
          removed,
          index,
          animation: animation,
        ),
      ),
      duration: const Duration(milliseconds: 220),
    );
  }

  /// 构建已保存映射列表项，与 WiFi 列表项保持一致的视觉风格和动画效果。
  Widget _buildMappingTile(
    BuildContext context,
    WifiPostMapping mapping,
    int index, {
    Animation<double>? animation,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final tile = Container(
      key: ValueKey('mapping_${mapping.identity}_$index'),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
        ),
        child: ListTile(
          dense: true,
          title: Text(
            mapping.normalizedPostUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            'WiFi名：${mapping.wifi.ssid.isNotEmpty ? mapping.wifi.ssid : '未记录'}\nBSSID：${mapping.wifi.bssid.isNotEmpty ? mapping.wifi.bssid : '未记录'}',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          trailing: IconButton(
            tooltip: '删除',
            onPressed: _postEnabled
                ? () => _removeWifiPostMappingAt(index)
                : null,
            icon: const Icon(Icons.delete_outline),
          ),
        ),
      ),
    );

    if (animation == null) {
      return tile;
    }

    return SizeTransition(
      sizeFactor: animation,
      axisAlignment: -1,
      child: FadeTransition(opacity: animation, child: tile),
    );
  }

  Widget _buildConfigActionButtons(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _saving ? null : _openShareImportMenu,
            icon: const Icon(Icons.ios_share_outlined),
            label: const Text('分享配置'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: _saving
                ? null
                : () async {
                    await _saveConfig(successMessage: 'HTTP配置已保存');
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
        ),
      ],
    );
  }

  Widget _buildPostConfigCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final savedPostUrls = _collectSavedPostUrls();
    final currentPostUrl = (_selectedPostUrl ?? '').trim();
    final hasCurrentPostUrl =
        currentPostUrl.isNotEmpty && savedPostUrls.contains(currentPostUrl);
    final currentPostText = hasCurrentPostUrl
        ? '当前：$currentPostUrl'
        : '当前无保存的post地址';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  FontAwesomeIcons.hubspot,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Post请求开门',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                final next = !_postEnabled;
                if (!next) {
                  _hidePostAddressOverlay();
                }
                setState(() => _postEnabled = next);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '启用 Post 请求开门',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    Switch(
                      value: _postEnabled,
                      onChanged: (v) {
                        if (!v) {
                          _hidePostAddressOverlay();
                        }
                        setState(() => _postEnabled = v);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _postEnabled
                  ? () {
                      final next = !_multiPostEnabled;
                      if (!next) {
                        _hidePostAddressOverlay();
                      }
                      setState(() {
                        _multiPostEnabled = next;
                      });
                    }
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '启用WiFi - Post请求',
                        style: TextStyle(
                          fontSize: 16,
                          color: _postEnabled
                              ? colorScheme.onSurface
                              : colorScheme.onSurface.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                    Switch(
                      value: _multiPostEnabled,
                      thumbColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.disabled)) {
                          return colorScheme.onSurface.withValues(alpha: 0.25);
                        }
                        return null;
                      }),
                      trackColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.disabled)) {
                          return colorScheme.onSurface.withValues(alpha: 0.12);
                        }
                        return null;
                      }),
                      trackOutlineColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.disabled)) {
                          return colorScheme.onSurface.withValues(alpha: 0.18);
                        }
                        return null;
                      }),
                      onChanged: _postEnabled
                          ? (v) {
                              if (!v) {
                                _hidePostAddressOverlay();
                              }
                              setState(() {
                                _multiPostEnabled = v;
                              });
                            }
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _postUrlController,
                    enabled: _postEnabled,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Post请求地址',
                      hintText: '例如: http://192.168.1.1/open',
                    ),
                  ),
                ),
                // 用 AnimatedSize 包裹按钮，使 TextField 宽度平滑过渡。
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  clipBehavior: Clip.hardEdge,
                  child: _multiPostEnabled
                      ? Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: FilledButton.tonalIcon(
                            onPressed: _postEnabled ? _addSavedPostUrl : null,
                            label: const Text('新增'),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // "当前：" 展示区，与映射列表分层显示。
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: _multiPostEnabled
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: CompositedTransformTarget(
                        key: _postDropdownTargetKey,
                        link: _postDropdownLink,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _postEnabled
                              ? _togglePostAddressOverlay
                              : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _postEnabled
                                  ? colorScheme.surfaceContainerLowest
                                  : colorScheme.surfaceContainerLowest
                                        .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: _postEnabled ? 0.35 : 0.15,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  hasCurrentPostUrl
                                      ? FontAwesomeIcons.link
                                      : FontAwesomeIcons.linkSlash,
                                  size: 16,
                                  color: _postEnabled
                                      ? (hasCurrentPostUrl
                                            ? colorScheme.primary
                                            : colorScheme.onSurfaceVariant)
                                      : colorScheme.onSurfaceVariant.withValues(
                                          alpha: 0.35,
                                        ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    currentPostText,
                                    style: TextStyle(
                                      color: _postEnabled
                                          ? colorScheme.onSurface
                                          : colorScheme.onSurface.withValues(
                                              alpha: 0.35,
                                            ),
                                    ),
                                  ),
                                ),
                                Icon(
                                  _postAddressListExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 18,
                                  color: _postEnabled
                                      ? colorScheme.onSurfaceVariant
                                      : colorScheme.onSurfaceVariant.withValues(
                                          alpha: 0.35,
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            // 已保存映射列表标题，固定独立行，不受列表增删动画影响。
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: _multiPostEnabled
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '已保存映射列表',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _postEnabled
                              ? colorScheme.onSurface
                              : colorScheme.onSurface.withValues(alpha: 0.35),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            // 已保存映射列表内容，独立区块。
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: _multiPostEnabled
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_wifiPostMappings.isEmpty)
                          Text(
                            '暂无已保存映射',
                            style: TextStyle(
                              color: _postEnabled
                                  ? colorScheme.onSurfaceVariant
                                  : colorScheme.onSurfaceVariant.withValues(
                                      alpha: 0.35,
                                    ),
                            ),
                          ),
                        AnimatedList(
                          key: _mappingListKey,
                          initialItemCount: _wifiPostMappings.length,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemBuilder: (context, index, animation) {
                            final mapping = _wifiPostMappings[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _buildMappingTile(
                                context,
                                mapping,
                                index,
                                animation: animation,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _postEnabled
                  ? () => setState(
                      () => _preferPostWhenWifiMatched =
                          !_preferPostWhenWifiMatched,
                    )
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'WiFi匹配后优先使用Post请求',
                            style: TextStyle(
                              fontSize: 16,
                              color: _postEnabled
                                  ? colorScheme.onSurface
                                  : colorScheme.onSurface.withValues(
                                      alpha: 0.35,
                                    ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '关闭后将优先使用 MQTT，失败时再尝试 Post',
                            style: TextStyle(
                              fontSize: 12,
                              color: _postEnabled
                                  ? colorScheme.onSurfaceVariant
                                  : colorScheme.onSurfaceVariant.withValues(
                                      alpha: 0.3,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _preferPostWhenWifiMatched,
                      thumbColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.disabled)) {
                          return colorScheme.onSurface.withValues(alpha: 0.25);
                        }
                        return null;
                      }),
                      trackColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.disabled)) {
                          return colorScheme.onSurface.withValues(alpha: 0.12);
                        }
                        return null;
                      }),
                      trackOutlineColor: WidgetStateProperty.resolveWith((
                        states,
                      ) {
                        if (states.contains(WidgetState.disabled)) {
                          return colorScheme.onSurface.withValues(alpha: 0.18);
                        }
                        return null;
                      }),
                      onChanged: _postEnabled
                          ? (v) =>
                                setState(() => _preferPostWhenWifiMatched = v)
                          : null,
                    ),
                  ],
                ),
              ),
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

    // WiFi 卡片仅在 Post 请求开门 + Wifi-Post 请求都开启时可操作。
    final wifiCardEnabled = _postEnabled && _multiPostEnabled;

    return Card(
      key: _wifiCardKey,
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
                  onPressed: wifiCardEnabled ? _searchCurrentWifi : null,
                  icon: const Icon(Icons.search, size: 16),
                  label: const Text('搜索'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            CompositedTransformTarget(
              key: _wifiDropdownTargetKey,
              link: _wifiDropdownLink,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: wifiCardEnabled ? _handleCurrentWifiCardTap : null,
                child: Container(
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
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '已保存 WiFi',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  TextSpan(
                    text: '（可多选，保存配置后作为匹配源）',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const SizedBox(height: 8),
            if (_savedWifis.isEmpty)
              Text(
                '暂无已保存 WiFi',
                style: TextStyle(
                  fontSize: 15,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            AnimatedList(
              key: _savedWifiListKey,
              initialItemCount: _savedWifis.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index, animation) {
                final wifi = _savedWifis[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _buildSavedWifiTile(
                    context,
                    wifi,
                    index,
                    animation: animation,
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        wifiCardEnabled &&
                            hasCurrentWifi &&
                            !_isCurrentWifiSaved()
                        ? _saveCurrentWifi
                        : null,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('保存当前WiFi'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建独立的状态消息组件，与卡片平级显示，无白底。
  Widget _buildStatusMessage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _status.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              key: ValueKey(
                '${_status}_${_statusIsError}_${_statusIcon.codePoint}',
              ),
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _statusIsError
                      ? colorScheme.errorContainer
                      : colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _statusIcon,
                      color: _statusIsError
                          ? colorScheme.onErrorContainer
                          : colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _status,
                        style: TextStyle(
                          color: _statusIsError
                              ? colorScheme.onErrorContainer
                              : colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: widget.showAppBar ? AppBar(title: const Text('HTTP配置')) : null,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final bool showButtonsUnderWifi = _postEnabled && _multiPostEnabled;

    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('HTTP配置')) : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPostConfigCard(context),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1,
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: showButtonsUnderWifi
                ? const SizedBox.shrink()
                : Padding(
                    key: const ValueKey('buttons_under_post_card'),
                    padding: const EdgeInsets.only(top: 10),
                    child: _buildConfigActionButtons(context),
                  ),
          ),
          const SizedBox(height: 12),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: _postEnabled && _multiPostEnabled ? 1.0 : 0.45,
            child: _buildWifiCard(context),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1,
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: showButtonsUnderWifi
                ? Padding(
                    key: const ValueKey('buttons_under_wifi_card'),
                    padding: const EdgeInsets.only(top: 10),
                    child: _buildConfigActionButtons(context),
                  )
                : const SizedBox.shrink(),
          ),
          _buildStatusMessage(context),
        ],
      ),
    );
  }
}
