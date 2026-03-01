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

/// 本地门锁（Post 开门 + WiFi 匹配）配置。
class LocalDoorLockConfig {
  /// 是否开启 Post 请求开门。
  final bool postEnabled;

  /// Post 请求地址。
  final String postUrl;

  /// 在 WiFi 匹配时是否优先使用 Post 请求。
  final bool preferPostWhenWifiMatched;

  /// 已保存的 WiFi 列表。
  final List<SavedWifiInfo> savedWifis;

  const LocalDoorLockConfig({
    required this.postEnabled,
    required this.postUrl,
    required this.preferPostWhenWifiMatched,
    required this.savedWifis,
  });

  /// 默认配置。
  factory LocalDoorLockConfig.defaults() => const LocalDoorLockConfig(
    postEnabled: false,
    postUrl: '',
    preferPostWhenWifiMatched: true,
    savedWifis: <SavedWifiInfo>[],
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

    return LocalDoorLockConfig(
      postEnabled: storage['local_post_enabled'] as bool? ?? false,
      postUrl: (storage['local_post_url'] as String? ?? '').trim(),
      preferPostWhenWifiMatched:
          storage['local_post_prefer_on_wifi'] as bool? ?? true,
      savedWifis: wifis,
    );
  }

  /// 是否满足可发送 Post 请求的最小条件。
  bool get isPostReady => postEnabled && postUrl.trim().isNotEmpty;

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
    List<SavedWifiInfo>? savedWifis,
  }) {
    return LocalDoorLockConfig(
      postEnabled: postEnabled ?? this.postEnabled,
      postUrl: postUrl ?? this.postUrl,
      preferPostWhenWifiMatched:
          preferPostWhenWifiMatched ?? this.preferPostWhenWifiMatched,
      savedWifis: savedWifis ?? this.savedWifis,
    );
  }
}
