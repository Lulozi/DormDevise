import 'package:dormdevise/models/local_door_lock_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地门锁配置读写服务。
class LocalDoorLockConfigService {
  LocalDoorLockConfigService._();

  /// 全局单例，统一配置入口。
  static final LocalDoorLockConfigService instance =
      LocalDoorLockConfigService._();

  LocalDoorLockConfig? _cachedConfig;

  /// 读取本地门锁配置，默认优先返回缓存。
  Future<LocalDoorLockConfig> loadConfig({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedConfig != null) {
      return _cachedConfig!;
    }

    final prefs = await SharedPreferences.getInstance();
    final storage = <String, Object?>{
      'local_post_enabled': prefs.getBool('local_post_enabled'),
      'local_post_url': prefs.getString('local_post_url'),
      'local_post_prefer_on_wifi': prefs.getBool('local_post_prefer_on_wifi'),
      'local_multi_post_enabled': prefs.getBool('local_multi_post_enabled'),
      'local_wifi_post_enabled': prefs.getBool('local_wifi_post_enabled'),
      'local_saved_post_urls': prefs.getStringList('local_saved_post_urls'),
      'local_saved_wifis': prefs.getStringList('local_saved_wifis'),
      'local_wifi_post_mappings': prefs.getStringList(
        'local_wifi_post_mappings',
      ),
    };
    _cachedConfig = LocalDoorLockConfig.fromStorage(storage);
    return _cachedConfig!;
  }

  /// 保存本地门锁配置并更新缓存。
  Future<void> saveConfig(LocalDoorLockConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('local_post_enabled', config.postEnabled);
    await prefs.setString('local_post_url', config.postUrl.trim());
    await prefs.setBool(
      'local_post_prefer_on_wifi',
      config.preferPostWhenWifiMatched,
    );
    await prefs.setBool('local_multi_post_enabled', config.multiPostEnabled);
    await prefs.setBool('local_wifi_post_enabled', config.wifiPostEnabled);
    await prefs.setStringList(
      'local_saved_post_urls',
      config.savedPostUrls
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(),
    );
    await prefs.setStringList(
      'local_saved_wifis',
      config.savedWifis.map((wifi) => wifi.toStorageString()).toList(),
    );
    await prefs.setStringList(
      'local_wifi_post_mappings',
      config.wifiPostMappings
          .map((mapping) => mapping.toStorageString())
          .toList(),
    );
    _cachedConfig = config;
  }

  /// 手动清理缓存，下次读取将重新从存储加载。
  Future<void> invalidateCache() async {
    _cachedConfig = null;
  }
}
