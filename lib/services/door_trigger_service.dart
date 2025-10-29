import 'dart:async';
import 'dart:io';

import 'package:dormdevise/models/mqtt_config.dart';
import 'package:dormdevise/services/mqtt_config_service.dart';
import 'package:dormdevise/services/mqtt_service.dart';

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
      MqttConfig config = await MqttConfigService.instance.loadConfig();
      if (!config.isCommandReady) {
        config = await MqttConfigService.instance.loadConfig(
          forceRefresh: true,
        );
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
