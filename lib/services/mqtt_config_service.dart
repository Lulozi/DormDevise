import 'package:dormdevise/models/mqtt_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 负责统一读取与写入 MQTT 配置的服务，提供简单缓存以减少 IO。
class MqttConfigService {
  MqttConfigService._();

  /// 全局单例，方便在应用任意位置访问配置。
  static final MqttConfigService instance = MqttConfigService._();

  MqttConfig? _cachedConfig;

  /// 读取当前配置，当缓存存在时优先返回缓存。
  Future<MqttConfig> loadConfig({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedConfig != null) {
      return _cachedConfig!;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, Object?> storage = <String, Object?>{
      'mqtt_host': prefs.getString('mqtt_host'),
      'mqtt_port': prefs.getString('mqtt_port'),
      'mqtt_topic': prefs.getString('mqtt_topic'),
      'mqtt_clientId': prefs.getString('mqtt_clientId'),
      'mqtt_username': prefs.getString('mqtt_username'),
      'mqtt_password': prefs.getString('mqtt_password'),
      'mqtt_with_tls': prefs.getBool('mqtt_with_tls'),
      'mqtt_ca': prefs.getString('mqtt_ca'),
      'mqtt_cert': prefs.getString('mqtt_cert'),
      'mqtt_key': prefs.getString('mqtt_key'),
      'mqtt_key_pwd': prefs.getString('mqtt_key_pwd'),
      'mqtt_status_topic': prefs.getString('mqtt_status_topic'),
      'mqtt_status_enabled': prefs.getBool('mqtt_status_enabled'),
      'custom_open_msg': prefs.getString('custom_open_msg'),
    };
    _cachedConfig = MqttConfig.fromStorage(storage);
    return _cachedConfig!;
  }

  /// 覆盖存储中的配置并同步更新缓存。
  Future<void> saveConfig(MqttConfig config) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('mqtt_host', config.host);
    await prefs.setString('mqtt_port', config.port.toString());
    await prefs.setString('mqtt_topic', config.commandTopic);
    await prefs.setString('mqtt_clientId', config.clientId);
    await prefs.setString('mqtt_username', config.username ?? '');
    await prefs.setString('mqtt_password', config.password ?? '');
    await prefs.setBool('mqtt_with_tls', config.withTls);
    await prefs.setString('mqtt_ca', config.caPath);
    await prefs.setString('mqtt_cert', config.certPath ?? '');
    await prefs.setString('mqtt_key', config.keyPath ?? '');
    await prefs.setString('mqtt_key_pwd', config.keyPassword ?? '');
    await prefs.setString('mqtt_status_topic', config.statusTopic ?? '');
    await prefs.setBool('mqtt_status_enabled', config.statusEnabled);
    await prefs.setString('custom_open_msg', config.customMessage);
    _cachedConfig = config;
  }

  /// 更新状态订阅开关并清理缓存，保持读取一致性。
  Future<void> setStatusEnabled(bool enabled) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mqtt_status_enabled', enabled);
    _cachedConfig = null;
  }

  /// 显式清空缓存，供外部在批量修改后刷新配置。
  Future<void> invalidateCache() async {
    _cachedConfig = null;
  }
}
