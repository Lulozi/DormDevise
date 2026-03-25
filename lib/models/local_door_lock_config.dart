import 'dart:convert';

/// 单条已保存的 WiFi 信息。
class SavedWifiInfo {
  /// WiFi 名称（SSID）。
  final String ssid;

  /// WiFi 的 BSSID（路由器 MAC），可为空。
  final String bssid;

  const SavedWifiInfo({required this.ssid, required this.bssid});

  /// 生成用于展示的主标题。
  String get displayName {
    if (ssid.isNotEmpty) {
      return ssid;
    }
    if (bssid.isNotEmpty) {
      return bssid;
    }
    return '未知WiFi';
  }

  /// 用于去重与匹配的标识。
  String get identity => bssid.isNotEmpty ? bssid : ssid;

  /// 转换为可持久化的字符串。
  String toStorageString() => '$ssid||$bssid';

  /// 从存储字符串恢复对象。
  factory SavedWifiInfo.fromStorageString(String raw) {
    final parts = raw.split('||');
    final String ssid = parts.isNotEmpty ? parts[0].trim() : '';
    final String bssid = parts.length > 1 ? parts[1].trim() : '';
    return SavedWifiInfo(ssid: ssid, bssid: bssid);
  }
}

/// WiFi 与 Post 请求地址映射项。
class WifiPostMapping {
  /// 映射对应的 WiFi。
  final SavedWifiInfo wifi;

  /// 对应的 Post 请求地址。
  final String postUrl;

  const WifiPostMapping({required this.wifi, required this.postUrl});

  /// 映射项身份标识，与 WiFi 身份保持一致。
  String get identity => wifi.identity;

  /// 用于展示的 WiFi 名称。
  String get displayName => wifi.displayName;

  /// 映射地址（去首尾空格）。
  String get normalizedPostUrl => postUrl.trim();

  /// 判断是否与当前 WiFi 匹配。
  bool matches({String? ssid, String? bssid}) {
    final String normalizedSsid = LocalDoorLockConfig.normalizeWifiValue(ssid);
    final String normalizedBssid = LocalDoorLockConfig.normalizeWifiValue(
      bssid,
    );
    final itemSsid = LocalDoorLockConfig.normalizeWifiValue(wifi.ssid);
    final itemBssid = LocalDoorLockConfig.normalizeWifiValue(wifi.bssid);

    if (normalizedBssid.isNotEmpty &&
        itemBssid.isNotEmpty &&
        normalizedBssid == itemBssid) {
      return true;
    }
    if (normalizedSsid.isNotEmpty &&
        itemSsid.isNotEmpty &&
        normalizedSsid == itemSsid) {
      return true;
    }
    return false;
  }

  /// 转换为可持久化字符串。
  String toStorageString() {
    return jsonEncode(<String, String>{
      'ssid': wifi.ssid,
      'bssid': wifi.bssid,
      'postUrl': normalizedPostUrl,
    });
  }

  /// 从可持久化字符串恢复对象。
  factory WifiPostMapping.fromStorageString(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final String ssid = (decoded['ssid'] as String? ?? '').trim();
        final String bssid = (decoded['bssid'] as String? ?? '').trim();
        final String postUrl = (decoded['postUrl'] as String? ?? '').trim();
        return WifiPostMapping(
          wifi: SavedWifiInfo(ssid: ssid, bssid: bssid),
          postUrl: postUrl,
        );
      }
    } catch (_) {}

    final parts = raw.split('||');
    final String ssid = parts.isNotEmpty ? parts[0].trim() : '';
    final String bssid = parts.length > 1 ? parts[1].trim() : '';
    final String postUrl = parts.length > 2 ? parts[2].trim() : '';
    return WifiPostMapping(
      wifi: SavedWifiInfo(ssid: ssid, bssid: bssid),
      postUrl: postUrl,
    );
  }
}

/// Http（Post 开门 + WiFi 匹配）配置。
class LocalDoorLockConfig {
  /// 是否开启 Post 请求开门。
  final bool postEnabled;

  /// Post 请求地址。
  final String postUrl;

  /// 在 WiFi 匹配时是否优先使用 Post 请求。
  final bool preferPostWhenWifiMatched;

  /// 是否启用多 Post 请求映射。
  final bool multiPostEnabled;

  /// 是否启用 WiFi-Post 映射。
  final bool wifiPostEnabled;

  /// 已保存的 Post 地址列表。
  final List<String> savedPostUrls;

  /// 已保存的 WiFi 列表。
  final List<SavedWifiInfo> savedWifis;

  /// WiFi 与 Post 地址映射列表。
  final List<WifiPostMapping> wifiPostMappings;

  const LocalDoorLockConfig({
    required this.postEnabled,
    required this.postUrl,
    required this.preferPostWhenWifiMatched,
    required this.multiPostEnabled,
    required this.wifiPostEnabled,
    required this.savedPostUrls,
    required this.savedWifis,
    required this.wifiPostMappings,
  });

  /// 默认配置。
  factory LocalDoorLockConfig.defaults() => const LocalDoorLockConfig(
    postEnabled: false,
    postUrl: '',
    preferPostWhenWifiMatched: true,
    multiPostEnabled: false,
    wifiPostEnabled: true,
    savedPostUrls: <String>[],
    savedWifis: <SavedWifiInfo>[],
    wifiPostMappings: <WifiPostMapping>[],
  );

  /// 从存储对象恢复配置。
  factory LocalDoorLockConfig.fromStorage(Map<String, Object?> storage) {
    final List<String> wifiRaw =
        (storage['local_saved_wifis'] as List<String>? ?? <String>[])
            .where((v) => v.trim().isNotEmpty)
            .toList();

    final List<SavedWifiInfo> wifis = wifiRaw
        .map(SavedWifiInfo.fromStorageString)
        .map(
          (wifi) => SavedWifiInfo(
            ssid: normalizeWifiValue(wifi.ssid),
            bssid: normalizeWifiValue(wifi.bssid),
          ),
        )
        .where((wifi) => wifi.identity.isNotEmpty)
        .toList();

    final List<String> mappingRaw =
        (storage['local_wifi_post_mappings'] as List<String>? ?? <String>[])
            .where((v) => v.trim().isNotEmpty)
            .toList();

    final List<WifiPostMapping> mappings = mappingRaw
        .map(WifiPostMapping.fromStorageString)
        .map(
          (mapping) => WifiPostMapping(
            wifi: SavedWifiInfo(
              ssid: normalizeWifiValue(mapping.wifi.ssid),
              bssid: normalizeWifiValue(mapping.wifi.bssid),
            ),
            postUrl: mapping.normalizedPostUrl,
          ),
        )
        .where(
          (mapping) =>
              mapping.identity.isNotEmpty &&
              mapping.normalizedPostUrl.isNotEmpty,
        )
        .toList();

    final List<String> savedPostUrls =
        (storage['local_saved_post_urls'] as List<String>? ?? <String>[])
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList();

    return LocalDoorLockConfig(
      postEnabled: storage['local_post_enabled'] as bool? ?? false,
      postUrl: (storage['local_post_url'] as String? ?? '').trim(),
      preferPostWhenWifiMatched:
          storage['local_post_prefer_on_wifi'] as bool? ?? true,
      multiPostEnabled: storage['local_multi_post_enabled'] as bool? ?? false,
      wifiPostEnabled: storage['local_wifi_post_enabled'] as bool? ?? true,
      savedPostUrls: savedPostUrls,
      savedWifis: wifis,
      wifiPostMappings: mappings,
    );
  }

  /// 从分享/导入使用的可读对象恢复配置。
  factory LocalDoorLockConfig.fromSharePayload(Map<dynamic, dynamic> payload) {
    final List<String> importedPostUrls =
        (payload['local_saved_post_urls'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic item) => item.toString().trim())
            .where((String item) => item.isNotEmpty)
            .toSet()
            .toList();

    final List<SavedWifiInfo> importedWifis =
        (payload['local_saved_wifis'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map>()
            .map(
              (Map item) => SavedWifiInfo(
                ssid: normalizeWifiValue(item['ssid']?.toString()),
                bssid: normalizeWifiValue(item['bssid']?.toString()),
              ),
            )
            .where((SavedWifiInfo wifi) => wifi.identity.isNotEmpty)
            .toList();

    final List<WifiPostMapping> importedMappings =
        (payload['local_wifi_post_mappings'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map>()
            .map(
              (Map item) => WifiPostMapping(
                wifi: SavedWifiInfo(
                  ssid: normalizeWifiValue(item['ssid']?.toString()),
                  bssid: normalizeWifiValue(item['bssid']?.toString()),
                ),
                postUrl: item['postUrl']?.toString() ?? '',
              ),
            )
            .where(
              (WifiPostMapping mapping) =>
                  mapping.identity.isNotEmpty &&
                  mapping.normalizedPostUrl.isNotEmpty,
            )
            .toList();

    return LocalDoorLockConfig(
      postEnabled: payload['local_post_enabled'] == true,
      postUrl: (payload['local_post_url']?.toString() ?? '').trim(),
      preferPostWhenWifiMatched: payload['local_post_prefer_on_wifi'] != false,
      multiPostEnabled: payload['local_multi_post_enabled'] == true,
      wifiPostEnabled: payload['local_wifi_post_enabled'] != false,
      savedPostUrls: importedPostUrls,
      savedWifis: importedWifis,
      wifiPostMappings: importedMappings,
    );
  }

  /// 转换为适合分享/二维码导出的可读对象。
  Map<String, Object?> toSharePayload() {
    return <String, Object?>{
      'local_post_enabled': postEnabled,
      'local_post_url': postUrl.trim(),
      'local_post_prefer_on_wifi': preferPostWhenWifiMatched,
      'local_multi_post_enabled': multiPostEnabled,
      'local_wifi_post_enabled': wifiPostEnabled,
      'local_saved_post_urls': savedPostUrls
          .map((String url) => url.trim())
          .where((String url) => url.isNotEmpty)
          .toList(growable: false),
      'local_saved_wifis': savedWifis
          .map(
            (SavedWifiInfo wifi) =>
                <String, String>{'ssid': wifi.ssid, 'bssid': wifi.bssid},
          )
          .toList(growable: false),
      'local_wifi_post_mappings': wifiPostMappings
          .map(
            (WifiPostMapping mapping) => <String, String>{
              'ssid': mapping.wifi.ssid,
              'bssid': mapping.wifi.bssid,
              'postUrl': mapping.normalizedPostUrl,
            },
          )
          .toList(growable: false),
    };
  }

  /// 是否满足可发送 Post 请求的最小条件。
  bool get isPostReady {
    if (!postEnabled) {
      return false;
    }
    if (postUrl.trim().isNotEmpty) {
      return true;
    }
    if (savedPostUrls.any((url) => url.trim().isNotEmpty)) {
      return true;
    }
    return wifiPostMappings.any(
      (mapping) => mapping.normalizedPostUrl.isNotEmpty,
    );
  }

  /// 根据当前 WiFi 解析应使用的 Post 地址。
  String resolvePostUrlForWifi({String? ssid, String? bssid}) {
    String resolveDefaultPostUrl() {
      final direct = postUrl.trim();
      if (direct.isNotEmpty) {
        return direct;
      }
      for (final saved in savedPostUrls) {
        final normalized = saved.trim();
        if (normalized.isNotEmpty) {
          return normalized;
        }
      }
      return '';
    }

    if (!multiPostEnabled || !wifiPostEnabled) {
      return resolveDefaultPostUrl();
    }
    for (final mapping in wifiPostMappings) {
      if (mapping.matches(ssid: ssid, bssid: bssid)) {
        return mapping.normalizedPostUrl;
      }
    }
    return resolveDefaultPostUrl();
  }

  /// 归一化 WiFi 字段，避免不同平台格式差异导致匹配失败。
  static String normalizeWifiValue(String? value) {
    String normalized = (value ?? '').trim();
    if (normalized.startsWith('"') && normalized.endsWith('"')) {
      normalized = normalized.substring(1, normalized.length - 1).trim();
    }

    final lower = normalized.toLowerCase();
    if (lower == '<unknown ssid>' ||
        lower == 'unknown ssid' ||
        lower == 'unknown' ||
        lower == 'null' ||
        lower == '0x') {
      return '';
    }
    return normalized;
  }

  /// 判断当前 WiFi 是否命中已保存列表。
  bool isWifiMatched({String? ssid, String? bssid}) {
    final String normalizedSsid = normalizeWifiValue(ssid);
    final String normalizedBssid = normalizeWifiValue(bssid);
    if (normalizedSsid.isEmpty && normalizedBssid.isEmpty) {
      return false;
    }

    for (final wifi in savedWifis) {
      final itemSsid = normalizeWifiValue(wifi.ssid);
      final itemBssid = normalizeWifiValue(wifi.bssid);
      if (normalizedBssid.isNotEmpty &&
          itemBssid.isNotEmpty &&
          normalizedBssid == itemBssid) {
        return true;
      }
      if (normalizedSsid.isNotEmpty &&
          itemSsid.isNotEmpty &&
          normalizedSsid == itemSsid) {
        return true;
      }
    }
    return false;
  }

  /// 复制当前配置并替换指定字段。
  LocalDoorLockConfig copyWith({
    bool? postEnabled,
    String? postUrl,
    bool? preferPostWhenWifiMatched,
    bool? multiPostEnabled,
    bool? wifiPostEnabled,
    List<String>? savedPostUrls,
    List<SavedWifiInfo>? savedWifis,
    List<WifiPostMapping>? wifiPostMappings,
  }) {
    return LocalDoorLockConfig(
      postEnabled: postEnabled ?? this.postEnabled,
      postUrl: postUrl ?? this.postUrl,
      preferPostWhenWifiMatched:
          preferPostWhenWifiMatched ?? this.preferPostWhenWifiMatched,
      multiPostEnabled: multiPostEnabled ?? this.multiPostEnabled,
      wifiPostEnabled: wifiPostEnabled ?? this.wifiPostEnabled,
      savedPostUrls: savedPostUrls ?? this.savedPostUrls,
      savedWifis: savedWifis ?? this.savedWifis,
      wifiPostMappings: wifiPostMappings ?? this.wifiPostMappings,
    );
  }
}
