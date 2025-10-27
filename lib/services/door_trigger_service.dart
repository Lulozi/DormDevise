import 'dart:async';
import 'dart:io';

import 'package:dormdevise/services/mqtt_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  String? _lastFingerprint;

  /// 触发开门动作，返回结果信息用于展示反馈。
  Future<DoorTriggerResult> triggerDoor() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String topic = prefs.getString('mqtt_topic') ?? 'test/topic';
      final String host = prefs.getString('mqtt_host') ?? '';
      final int port =
          int.tryParse(prefs.getString('mqtt_port') ?? '1883') ?? 1883;
      final String clientId =
          prefs.getString('mqtt_clientId') ?? 'flutter_client';
      final String? username = prefs.getString('mqtt_username');
      final String? password = prefs.getString('mqtt_password');
      final bool withTls = prefs.getBool('mqtt_with_tls') ?? false;
      final String caPath = prefs.getString('mqtt_ca') ?? 'assets/certs/ca.pem';
      final String? certPath = prefs.getString('mqtt_cert');
      final String? keyPath = prefs.getString('mqtt_key');
      final String? keyPwd = prefs.getString('mqtt_key_pwd');
      final String msg = prefs.getString('custom_open_msg') ?? 'OPEN';
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
      final String fingerprint = [
        host,
        port.toString(),
        clientId,
        username ?? '',
        password ?? '',
        (withTls ? '1' : '0'),
        certPath ?? '',
        keyPath ?? '',
      ].join('|');
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
    } catch (e) {
      return DoorTriggerResult(success: false, message: '开门失败: $e');
    }
  }

  /// 主动释放 MQTT 连接，供应用退出时清理资源。
  Future<void> dispose() async {
    await _mqttService?.dispose();
    _mqttService = null;
    _lastFingerprint = null;
  }
}
