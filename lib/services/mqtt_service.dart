import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

typedef OnNotification = void Function(String topic, Map<String, dynamic> msg);
typedef OnLog = void Function(String line);
typedef OnError = void Function(Object error, [StackTrace? st]);

/// 构建安全连接所需的证书上下文。
Future<SecurityContext> buildSecurityContext({
  String caAsset = 'assets/certs/ca.pem',
  String? clientCertAsset,
  String? clientKeyAsset,
  String? clientKeyPassword,
  bool withTrustedRoots = false,
}) async {
  final sc = SecurityContext(withTrustedRoots: withTrustedRoots);
  final caBytes = await rootBundle.load(caAsset);
  sc.setTrustedCertificatesBytes(caBytes.buffer.asUint8List());
  if (clientCertAsset != null && clientKeyAsset != null) {
    final certBytes = await rootBundle.load(clientCertAsset);
    final keyBytes = await rootBundle.load(clientKeyAsset);
    sc.useCertificateChainBytes(certBytes.buffer.asUint8List());
    sc.usePrivateKeyBytes(
      keyBytes.buffer.asUint8List(),
      password: clientKeyPassword,
    );
  }
  return sc;
}

/// 提供 MQTT 连接、订阅与消息发布的封装服务。
class MqttService {
  /// 发布纯文本消息到指定主题。
  Future<void> publishText(
    String topic,
    String text, {
    MqttQos qos = MqttQos.atLeastOnce,
    bool retain = false,
  }) async {
    final builder = MqttClientPayloadBuilder();
    builder.addString(text);
    _client.publishMessage(topic, qos, builder.payload!, retain: retain);
    _debug('📤 [MQTT] publish $topic: $text');
  }

  final String host;
  final int port;
  final String clientId;
  final String? username;
  final String? password;
  final SecurityContext? securityContext;

  final Set<String> _subscriptions = {};
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};

  final OnNotification? onNotification;
  final OnLog? log;
  final OnError? onError;

  int keepAliveSeconds;
  final Duration minBackoff;
  final Duration maxBackoff;

  late final MqttServerClient _client;
  Timer? _manualReconnectTimer;
  int _reconnectAttempt = 0;
  final Random _rnd = Random();

  bool get isConnected =>
      _client.connectionStatus?.state == MqttConnectionState.connected;

  /// 构造函数，初始化底层客户端及回调。
  MqttService({
    required this.host,
    this.port = 1883,
    required this.clientId,
    this.username,
    this.password,
    this.keepAliveSeconds = 60,
    this.onNotification,
    this.log,
    this.onError,
    this.minBackoff = const Duration(seconds: 1),
    this.maxBackoff = const Duration(seconds: 30),
    this.securityContext,
  }) {
    _client = MqttServerClient(host, clientId)
      ..port = port
      ..keepAlivePeriod = keepAliveSeconds
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true
      ..secure = securityContext != null
      ..onConnected = onConnected
      ..onDisconnected = onDisconnected
      ..onAutoReconnect = onAutoReconnect
      ..onAutoReconnected = onAutoReconnected
      ..logging(on: false);
    if (securityContext != null) {
      _client.securityContext = securityContext!;
    }

    _client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean();

    if (username != null || password != null) {
      _client.connectionMessage = _client.connectionMessage!.authenticateAs(
        username ?? '',
        password ?? '',
      );
    }
  }

  /// 建立与 MQTT 服务器的连接并监听消息。
  Future<void> connect() async {
    if (isConnected) return;
    try {
      _info('🔌 [MQTT] connecting to $host:$port (clientId=$clientId)');
      await _client.connect();
      _client.updates!.listen(
        _onMessage,
        onError: (e, st) {
          _error('❌ [MQTT] stream error: $e', e, st);
        },
        onDone: () {
          _warn('⚠️ [MQTT] update stream done');
        },
      );
    } catch (e, st) {
      _error('🚫 [MQTT] connect failed: $e', e, st);
      _scheduleManualReconnect();
      rethrow;
    }
  }

  /// 订阅主题以便接收消息。
  Future<void> subscribe(
    String topic, {
    MqttQos qos = MqttQos.atLeastOnce,
  }) async {
    if (!_subscriptions.contains(topic)) {
      _subscriptions.add(topic);
    }
    if (!isConnected) return;
    _info('🧭 [MQTT] subscribe $topic, qos=$qos');
    _client.subscribe(topic, qos);
  }

  /// 发布 JSON 格式的消息。
  Future<void> publishJson(
    String topic,
    Map<String, dynamic> payload, {
    MqttQos qos = MqttQos.atLeastOnce,
    bool retain = false,
  }) async {
    final jsonStr = jsonEncode(payload);
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonStr);
    _client.publishMessage(topic, qos, builder.payload!, retain: retain);
    _debug('📤 [MQTT] publish $topic: $jsonStr');
  }

  /// 发送请求并等待响应主题返回结果。
  Future<Map<String, dynamic>> sendRequest({
    required String reqTopic,
    required String respTopic,
    required Map<String, dynamic> payload,
    Duration timeout = const Duration(seconds: 5),
    MqttQos qos = MqttQos.atLeastOnce,
  }) async {
    await subscribe(respTopic, qos: qos);
    final String reqId = (payload['req_id'] as String?) ?? _genReqId();
    payload['req_id'] = reqId;

    final completer = Completer<Map<String, dynamic>>();
    _pending[reqId] = completer;

    await publishJson(reqTopic, payload, qos: qos, retain: false);

    try {
      final rsp = await completer.future.timeout(
        timeout,
        onTimeout: () {
          _pending.remove(reqId);
          throw TimeoutException('MQTT request timeout: $reqId');
        },
      );
      return rsp;
    } catch (e) {
      rethrow;
    }
  }

  /// 处理底层客户端推送的所有消息。
  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final e in events) {
      final topic = e.topic;
      final MqttPublishMessage msg = e.payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
        msg.payload.message,
      );
      _debug('📥 [MQTT] recv $topic: $payload');
      Map<String, dynamic> data;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        } else {
          data = {'payload': decoded};
        }
      } catch (_) {
        data = {'payload': payload};
      }
      final reqId = data['req_id'] as String?;
      if (reqId != null && _pending.containsKey(reqId)) {
        final c = _pending.remove(reqId)!;
        if (!c.isCompleted) c.complete(data);
        continue;
      }
      try {
        onNotification?.call(topic, data);
      } catch (e, st) {
        _error('⚠️ [MQTT] onNotification error: $e', e, st);
      }
    }
  }

  /// 连接成功后自动重新订阅并重置重连状态。
  void onConnected() {
    _info('✅ [MQTT] connected');
    _reconnectAttempt = 0;
    _manualReconnectTimer?.cancel();
    _manualReconnectTimer = null;
    for (final t in _subscriptions) {
      _client.subscribe(t, MqttQos.atLeastOnce);
    }
  }

  /// 连接断开时启动手动重连调度。
  void onDisconnected() {
    _warn('⚠️ [MQTT] disconnected');
    _scheduleManualReconnect();
  }

  /// 自动重连开始时记录提示。
  void onAutoReconnect() {
    _warn('⏳ [MQTT] auto reconnecting...');
  }

  /// 自动重连成功后的回调。
  void onAutoReconnected() {
    _info('🔁 [MQTT] auto reconnected');
  }

  /// 启动带抖动的重连定时器。
  void _scheduleManualReconnect() {
    if (isConnected) return;
    _manualReconnectTimer?.cancel();
    final base = minBackoff.inMilliseconds * pow(2, _reconnectAttempt).toInt();
    final capped = base.clamp(
      minBackoff.inMilliseconds,
      maxBackoff.inMilliseconds,
    );
    final jitter = (capped * (0.2 * (_rnd.nextDouble() * 2 - 1))).round();
    final delay = Duration(milliseconds: max(0, capped + jitter));
    _reconnectAttempt = min(_reconnectAttempt + 1, 10);
    _warn('🕰️ [MQTT] schedule reconnect in ${delay.inMilliseconds} ms');
    _manualReconnectTimer = Timer(delay, () async {
      try {
        await connect();
      } catch (_) {
        _scheduleManualReconnect();
      }
    });
  }

  /// 关闭客户端并清理待完成的请求。
  Future<void> dispose() async {
    _info('🧹 [MQTT] dispose');
    _manualReconnectTimer?.cancel();
    _manualReconnectTimer = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('MQTT disposed'));
    }
    _pending.clear();
    if (isConnected) {
      _client.disconnect();
    } else {
      _client.doAutoReconnect(force: false);
    }
  }

  /// 生成请求 ID，确保唯一性。
  String _genReqId() {
    final v = List<int>.generate(8, (_) => _rnd.nextInt(256));
    return v.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 记录普通信息日志。
  void _info(String s) => log?.call(s);

  /// 记录警告信息。
  void _warn(String s) => log?.call(s);

  /// 记录调试信息。
  void _debug(String s) => log?.call(s);

  /// 记录错误信息并通知外部。
  void _error(String msg, Object e, [StackTrace? st]) {
    log?.call(msg);
    onError?.call(e, st);
  }
}
