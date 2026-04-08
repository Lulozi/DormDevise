import 'dart:async';
import 'dart:io';

import 'package:dormdevise/models/local_door_lock_config.dart';
import 'package:dormdevise/models/mqtt_config.dart';
import 'package:dormdevise/services/local_door_lock_config_service.dart';
import 'package:dormdevise/services/mqtt_config_service.dart';
import 'package:dormdevise/services/mqtt_service.dart';
import 'package:dormdevise/services/wifi_info_service.dart';
import 'package:http/http.dart' as http;

/// 保存开门触发结果，便于页面和组件统一处理反馈。
class DoorTriggerResult {
  final bool success;
  final String message;

  const DoorTriggerResult({required this.success, required this.message});
}

/// 提供统一的开门触发逻辑，供页面与悬浮窗复用。
class DoorTriggerService {
  DoorTriggerService._();

  static final DoorTriggerService instance = DoorTriggerService._();

  MqttService? _mqttService;
  Future<DoorTriggerResult>? _inFlightTrigger;
  String? _lastFingerprint;
  WifiSnapshot _cachedWifiSnapshot = const WifiSnapshot();
  bool _cachedWifiMatched = false;
  DateTime? _cachedWifiCheckedAt;

  static const Duration _postTimeout = Duration(seconds: 5);

  static const Duration _wifiCheckIntervalFast = Duration(milliseconds: 500);
  static const Duration _wifiCheckIntervalSlow = Duration(seconds: 5);

  /// 读取 WiFi 匹配结果。
  ///
  /// 当配置为“WiFi匹配后优先使用Post请求”时，使用 0.5s/5s 的自适应检查周期：
  /// - 未匹配：0.5s 检查一次，尽快捕获切换到目标 WiFi。
  /// - 已匹配：5s 检查一次，降低高频读取开销。
  Future<({WifiSnapshot wifi, bool matched})> _resolveWifiMatch(
    LocalDoorLockConfig config,
  ) async {
    final bool useAdaptiveCheck =
        config.postEnabled && config.preferPostWhenWifiMatched;
    if (!useAdaptiveCheck) {
      final wifi = await WifiInfoService.instance.getCurrentWifi();
      final matched = config.isWifiMatched(ssid: wifi.ssid, bssid: wifi.bssid);
      _cachedWifiSnapshot = wifi;
      _cachedWifiMatched = matched;
      _cachedWifiCheckedAt = DateTime.now();
      return (wifi: wifi, matched: matched);
    }

    final now = DateTime.now();
    final refreshInterval = _cachedWifiMatched
        ? _wifiCheckIntervalSlow
        : _wifiCheckIntervalFast;
    final bool shouldRefresh =
        _cachedWifiCheckedAt == null ||
        now.difference(_cachedWifiCheckedAt!) >= refreshInterval;

    if (shouldRefresh) {
      final wifi = await WifiInfoService.instance.getCurrentWifi();
      final matched = config.isWifiMatched(ssid: wifi.ssid, bssid: wifi.bssid);
      _cachedWifiSnapshot = wifi;
      _cachedWifiMatched = matched;
      _cachedWifiCheckedAt = now;
    }

    return (wifi: _cachedWifiSnapshot, matched: _cachedWifiMatched);
  }

  /// 触发开门动作，返回结果信息用于展示反馈。
  Future<DoorTriggerResult> triggerDoor() {
    final Future<DoorTriggerResult>? inFlight = _inFlightTrigger;
    if (inFlight != null) {
      return inFlight;
    }

    final Future<DoorTriggerResult> request = _triggerDoorInternal();
    _inFlightTrigger = request;
    request.whenComplete(() {
      if (identical(_inFlightTrigger, request)) {
        _inFlightTrigger = null;
      }
    });
    return request;
  }

  Future<DoorTriggerResult> _triggerDoorInternal() async {
    try {
      final LocalDoorLockConfig localConfig = await LocalDoorLockConfigService
          .instance
          .loadConfig();
      final wifiMatch = await _resolveWifiMatch(localConfig);
      final WifiSnapshot wifi = wifiMatch.wifi;
      final bool wifiMatched = wifiMatch.matched;
      final String resolvedPostUrl = localConfig.resolvePostUrlForWifi(
        ssid: wifi.ssid,
        bssid: wifi.bssid,
      );
      final bool canUsePost =
          wifiMatched && localConfig.postEnabled && resolvedPostUrl.isNotEmpty;

      if (canUsePost) {
        if (localConfig.preferPostWhenWifiMatched) {
          final DoorTriggerResult postResult = await _triggerViaPost(
            resolvedPostUrl,
          );
          if (postResult.success) {
            return postResult;
          }

          final DoorTriggerResult mqttResult = await _triggerViaMqtt();
          if (mqttResult.success) {
            return const DoorTriggerResult(
              success: true,
              message: 'Post 请求失败，已通过 MQTT 发送开门指令',
            );
          }
          return DoorTriggerResult(
            success: false,
            message:
                'Post 与 MQTT 均失败：${postResult.message}；${mqttResult.message}',
          );
        }

        final DoorTriggerResult mqttResult = await _triggerViaMqtt();
        if (mqttResult.success) {
          return mqttResult;
        }

        final DoorTriggerResult postResult = await _triggerViaPost(
          resolvedPostUrl,
        );
        if (postResult.success) {
          return const DoorTriggerResult(
            success: true,
            message: 'MQTT 失败，已通过 Post 请求发送开门指令',
          );
        }
        return DoorTriggerResult(
          success: false,
          message:
              'MQTT 与 Post 均失败：${mqttResult.message}；${postResult.message}',
        );
      }

      return _triggerViaMqtt();
    } catch (e) {
      return DoorTriggerResult(success: false, message: '开门失败: $e');
    }
  }

  /// 使用 HTTP Post 请求触发开门，返回执行结果。
  Future<DoorTriggerResult> _triggerViaPost(String url) async {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return const DoorTriggerResult(success: false, message: 'Post请求地址无效');
    }

    try {
      final http.Response response = await http.post(uri).timeout(_postTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const DoorTriggerResult(success: true, message: 'Post开门请求已发送');
      }
      return DoorTriggerResult(
        success: false,
        message: 'Post请求失败(HTTP ${response.statusCode})',
      );
    } on TimeoutException {
      return const DoorTriggerResult(success: false, message: 'Post请求超时');
    } catch (e) {
      return DoorTriggerResult(success: false, message: 'Post请求失败: $e');
    }
  }

  /// 使用 MQTT 触发开门，返回执行结果。
  Future<DoorTriggerResult> _triggerViaMqtt() async {
    MqttConfig config = await MqttConfigService.instance.loadConfig();
    if (!config.isCommandReady) {
      config = await MqttConfigService.instance.loadConfig(forceRefresh: true);
    }
    if (!config.isCommandReady) {
      return const DoorTriggerResult(
        success: false,
        message: '请先在MQTT设置中填写服务器与主题',
      );
    }

    final String topic = config.commandTopic;
    final String host = config.host;
    final int port = config.port;
    final String clientId = config.clientId.isNotEmpty
        ? config.clientId
        : 'flutter_client';
    final String? username = config.username;
    final String? password = config.password;
    final bool withTls = config.withTls;
    final String caPath = config.caPath;
    final String? certPath = config.certPath;
    final String? keyPath = config.keyPath;
    final String? keyPwd = config.keyPassword;
    final String msg = config.customMessage;

    SecurityContext? sc;
    if (withTls) {
      sc = await buildSecurityContext(
        caAsset: caPath,
        clientCertAsset: (certPath != null && certPath.isNotEmpty)
            ? certPath
            : null,
        clientKeyAsset: (keyPath != null && keyPath.isNotEmpty)
            ? keyPath
            : null,
        clientKeyPassword: (keyPwd != null && keyPwd.isNotEmpty)
            ? keyPwd
            : null,
      );
    }

    final String fingerprint = config.buildFingerprint();
    if (_mqttService == null || _lastFingerprint != fingerprint) {
      await _mqttService?.dispose();
      _mqttService = null;
      _lastFingerprint = fingerprint;
    }

    _mqttService ??= MqttService(
      host: host,
      port: port,
      clientId: clientId,
      username: (username != null && username.isNotEmpty) ? username : null,
      password: (password != null && password.isNotEmpty) ? password : null,
      securityContext: sc,
    );
    await _mqttService!.connect();
    await _mqttService!.subscribe(topic);
    await _mqttService!.publishText(topic, msg);
    return const DoorTriggerResult(success: true, message: '开门指令已发送');
  }

  /// 主动释放 MQTT 连接，供应用退出时清理资源。
  Future<void> dispose() async {
    await _mqttService?.dispose();
    _mqttService = null;
    _lastFingerprint = null;
  }
}
