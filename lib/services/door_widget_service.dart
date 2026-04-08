import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dormdevise/models/door_widget_settings.dart';
import 'package:dormdevise/models/door_widget_state.dart';
import 'package:dormdevise/models/mqtt_config.dart';
import 'package:dormdevise/services/door_trigger_service.dart';
import 'package:dormdevise/services/local_door_lock_config_service.dart';
import 'package:dormdevise/services/mqtt_config_service.dart';
import 'package:dormdevise/services/mqtt_service.dart';
import 'package:dormdevise/services/wifi_info_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 单次 WiFi 采样结果。
///
/// 使用状态 + 标识组合做去重，避免桌面组件因为瞬时采样抖动反复切换。
class _WifiObservation {
  const _WifiObservation({required this.status, required this.identifier});

  final WifiStatus status;
  final String? identifier;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _WifiObservation &&
        other.status == status &&
        other.identifier == identifier;
  }

  @override
  int get hashCode => Object.hash(status, identifier);
}

/// 管理桌面微件生命周期、数据持久化与交互回调的核心服务。
class DoorWidgetService {
  DoorWidgetService._();

  /// 提供全局单例，方便在应用内统一调度。
  static final DoorWidgetService instance = DoorWidgetService._();

  static const String _settingsPrefKey = 'door_widget_settings';
  static const String _statePrefKey = 'door_widget_state';
  static const String _hwBusyKey = 'door_widget_busy';
  static const String _hwMessageKey = 'door_widget_message';
  static const String _hwSuccessKey = 'door_widget_last_success';
  static const String _hwUpdatedKey = 'door_widget_updated_at';
  static const String _androidProviderQualified =
      'com.lulo.dormdevise.DoorWidgetProvider';
  static const String _androidProviderName = 'DoorWidgetProvider';
  static const Duration _manualTriggerDebounceInterval = Duration(seconds: 4);
  static const Duration _manualSuccessDisplayDuration = Duration(seconds: 2);
  static const Duration _deviceOnlineGracePeriod = Duration(seconds: 45);

  DoorWidgetSettings _settings = DoorWidgetSettings.defaults();
  DoorWidgetState _state = DoorWidgetState.initial();
  bool _initialized = false;
  bool _hasHydrated = false;
  Timer? _autoRefreshTimer;
  Timer? _stateMonitorTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<Uri?>? _widgetClickSubscription;
  final StreamController<Uri?> _launchEventsController =
      StreamController<Uri?>.broadcast();
  Uri? _latestLaunchUri;
  Timer? _successResetTimer;
  MqttService? _statusMqttService;
  Timer? _statusReconnectTimer;
  bool _statusEnsuring = false;
  String? _statusFingerprint;
  String? _statusTopic;
  String? _statusIdleMessage;
  DateTime? _manualResultDeadline;
  bool _disposed = false;
  bool _promptChannelRegistered = false;

  /// WiFi状态缓存，用于被动检测变化
  WifiStatus? _cachedWifiStatus;

  /// 上一次检测到的WiFi信息（SSID:BSSID），用于避免重复更新
  String? _lastWifiIdentifier;

  /// 最近一次已确认的 WiFi 采样结果。
  _WifiObservation? _lastWifiObservation;

  /// 首次出现的新 WiFi 采样结果，需二次确认后才真正更新状态。
  _WifiObservation? _pendingWifiObservation;

  /// MQTT状态主题上一次收到的消息，用于避免重复更新
  String? _lastStatusPayload;

  /// 最近一次收到设备在线心跳的时间，用于避免断线抖动造成在线/离线闪烁。
  DateTime? _lastStatusOnlineAt;

  /// 状态监听日志节流时间戳，避免日志刷屏。
  DateTime? _lastStatusLogAt;

  /// 上一次输出的状态监听日志内容，用于抑制重复行。
  String? _lastStatusLogLine;

  int _statusReconnectAttempts = 0;

  /// 对外暴露的可监听状态，便于设置页面实时刷新。
  final ValueNotifier<DoorWidgetState> stateNotifier =
      ValueNotifier<DoorWidgetState>(DoorWidgetState.initial());

  /// 提供桌面微件唤起应用时的 URI 事件流。
  Stream<Uri?> get launchEvents => _launchEventsController.stream;

  /// 读取最近一次微件唤起 URI，并在读取后清空缓存，防止重复触发。
  Uri? takeLatestLaunchUri() {
    final Uri? result = _latestLaunchUri;
    _latestLaunchUri = null;
    return result;
  }

  DoorWidgetSettings get settings => _settings;
  DoorWidgetState get state => _state;

  /// 初始化桌面微件运行所需的资源与监听。
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _disposed = false;
    WidgetsFlutterBinding.ensureInitialized();
    await _ensureLoaded();
    stateNotifier.value = _state;
    await HomeWidget.registerInteractivityCallback(
      doorWidgetBackgroundCallback,
    );
    // 注册 native -> Dart 的 MethodChannel，用于原生请求直接开门（无 UI）
    if (!_promptChannelRegistered) {
      final MethodChannel promptChannel = const MethodChannel(
        'door_widget/prompt',
      );
      promptChannel.setMethodCallHandler((call) async {
        if (call.method == 'performAutoOpen') {
          debugPrint('桌面微件直开: 开始触发');
          final DoorTriggerResult result = await DoorTriggerService.instance
              .triggerDoor();
          debugPrint(
            '桌面微件直开: ${result.success ? '成功' : '失败'}，原因：${result.message}',
          );
          await recordManualTriggerResult(result);
          // 尝试通知 native 关闭任何可能存在的浮层（若无 Activity 在前台会被忽略）
          try {
            await promptChannel.invokeMethod('close');
          } catch (_) {}
        }
        return null;
      });
      _promptChannelRegistered = true;
    }
    _listenWidgetLaunches();
    // 检查是否存在原生侧写入的 pending 自动开门标志（作为兜底）
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getBool('door_widget_pending_auto_open') ?? false;
      if (pending) {
        await prefs.setBool('door_widget_pending_auto_open', false);
        final DoorTriggerResult result = await DoorTriggerService.instance
            .triggerDoor();
        await recordManualTriggerResult(result);
      }
    } catch (_) {}
    await _persistSettingsToWidget();
    await _persistStateToWidget();
    await syncWidget();
    _scheduleAutoRefresh();
    _startStateMonitoring();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      _,
    ) {
      unawaited(_checkAndUpdateState());
    });
    unawaited(_ensureStatusListener());
    _initialized = true;
  }

  /// 释放桌面微件相关资源，供应用退出时调用。
  Future<void> dispose() async {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    _stateMonitorTimer?.cancel();
    _stateMonitorTimer = null;
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _successResetTimer?.cancel();
    _successResetTimer = null;
    _statusReconnectTimer?.cancel();
    _statusReconnectTimer = null;
    await _teardownStatusListener();
    _hasHydrated = false;
    await _widgetClickSubscription?.cancel();
    await _launchEventsController.close();
    _latestLaunchUri = null;
    _disposed = true;
  }

  /// 更新桌面微件设置项并持久化。
  Future<void> updateSettings(DoorWidgetSettings newSettings) async {
    await _ensureLoaded();
    _settings = newSettings;
    await _saveSettings();
    await _persistSettingsToWidget();
    _scheduleAutoRefresh();
    await syncWidget();
  }

  /// 通知桌面微件进入忙碌态，后续将触发 UI 切换。
  Future<void> markManualTriggerStart() async {
    await _ensureLoaded();
    _successResetTimer?.cancel();
    _manualResultDeadline = null;
    _state = _state.copyWith(
      busy: true,
      lastResultMessage: '正在开门，请稍候…',
      lastResultSuccess: null,
    );
    stateNotifier.value = _state;
    await _saveState();
    await _persistStateToWidget();
    await syncWidget();
  }

  /// 将开门结果同步到桌面微件，用于展示开门反馈。
  Future<void> recordManualTriggerResult(DoorTriggerResult result) async {
    await _ensureLoaded();
    _successResetTimer?.cancel();
    _manualResultDeadline = DateTime.now().add(_manualTriggerDebounceInterval);
    final String displayMessage = result.success
        ? '开门成功'
        : (result.message.isNotEmpty ? result.message : '开门失败');
    _state = _state.copyWith(
      busy: false,
      lastResultSuccess: result.success,
      lastResultMessage: displayMessage,
      lastUpdatedAt: DateTime.now(),
      doorLockStatus: result.success
          ? DoorLockStatus.success
          : DoorLockStatus.failed,
    );
    stateNotifier.value = _state;
    await _saveState();
    await _persistStateToWidget();
    await syncWidget();
    // 成功或失败都延迟重置为待开门状态
    _scheduleSuccessReset();
  }

  /// 主动刷新桌面微件展示的数据。
  Future<void> syncWidget() async {
    try {
      // 刷新 2x2 完整版组件
      await HomeWidget.updateWidget(
        name: _androidProviderName,
        qualifiedAndroidName: _androidProviderQualified,
      );
      // 刷新 1x1 简洁版组件
      await HomeWidget.updateWidget(
        name: 'DoorSimpleWidgetProvider',
        qualifiedAndroidName: 'com.lulo.dormdevise.DoorSimpleWidgetProvider',
      );
    } catch (err, stackTrace) {
      debugPrint('刷新桌面微件失败: $err\n$stackTrace');
    }
  }

  /// 强制重建状态订阅监听，用于配置变更后即时生效。
  Future<void> refreshStatusListener() async {
    await _ensureStatusListener(force: true);
  }

  /// 门锁配置变更后刷新状态与组件展示，保证已添加组件即时生效。
  Future<void> onDoorLockConfigChanged({bool mqttConfigChanged = false}) async {
    if (_disposed) {
      return;
    }
    await _ensureLoaded();
    if (mqttConfigChanged) {
      await _ensureStatusListener(force: true);
    }
    await _checkAndUpdateState();
    await _persistStateToWidget();
    await syncWidget();
  }

  /// 处理桌面微件发起的交互请求，例如滑动开门或手动刷新。
  Future<void> handleWidgetInteraction(Uri? uri) async {
    if (uri == null || uri.host != 'door_widget' || uri.pathSegments.isEmpty) {
      return;
    }
    await _ensureLoaded();
    final String action = uri.pathSegments.first;
    switch (action) {
      case 'open':
        if (_state.busy) {
          return;
        }
        await markManualTriggerStart();
        final DoorTriggerResult result = await DoorTriggerService.instance
            .triggerDoor();
        await recordManualTriggerResult(result);
        break;
      case 'refresh':
        await _persistSettingsToWidget();
        await _persistStateToWidget();
        await syncWidget();
        break;
      default:
        break;
    }
  }

  Future<void> _ensureLoaded() async {
    if (_hasHydrated) {
      return;
    }
    _settings = await _loadSettings();
    _state = await _loadState();
    // 从持久化状态恢复WiFi状态缓存，避免状态抖动
    _cachedWifiStatus = _state.wifiStatus;
    _lastWifiObservation ??= _WifiObservation(
      status: _state.wifiStatus,
      identifier: _state.wifiStatus == WifiStatus.disconnected
          ? ''
          : _lastWifiIdentifier,
    );
    _pendingWifiObservation = null;
    _hasHydrated = true;
  }

  void _listenWidgetLaunches() {
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_handleLaunchUri);
    _widgetClickSubscription = HomeWidget.widgetClicked.listen(
      _handleLaunchUri,
    );
  }

  void _handleLaunchUri(Uri? uri) {
    if (uri == null || uri.host != 'door_widget') {
      return;
    }
    _latestLaunchUri = uri;
    _launchEventsController.add(uri);
  }

  Future<DoorWidgetSettings> _loadSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_settingsPrefKey);
    if (raw == null || raw.isEmpty) {
      return DoorWidgetSettings.defaults();
    }
    try {
      final Map<String, dynamic> map =
          (jsonDecode(raw) as Map<dynamic, dynamic>).cast<String, dynamic>();
      return DoorWidgetSettings.fromMap(map);
    } catch (_) {
      return DoorWidgetSettings.defaults();
    }
  }

  Future<void> _saveSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsPrefKey, jsonEncode(_settings.toMap()));
  }

  Future<DoorWidgetState> _loadState() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_statePrefKey);
    if (raw == null || raw.isEmpty) {
      return DoorWidgetState.initial();
    }
    try {
      final Map<String, dynamic> map =
          (jsonDecode(raw) as Map<dynamic, dynamic>).cast<String, dynamic>();
      return DoorWidgetState.fromMap(map);
    } catch (_) {
      return DoorWidgetState.initial();
    }
  }

  Future<void> _saveState() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_statePrefKey, jsonEncode(_state.toMap()));
  }

  Future<void> _persistSettingsToWidget() async {
    final List<Future<bool?>> futures = [
      HomeWidget.saveWidgetData<bool>(
        'door_widget_setting_show_result',
        _settings.showLastResult,
      ),
      HomeWidget.saveWidgetData<bool>(
        'door_widget_setting_auto_refresh',
        _settings.autoRefreshEnabled,
      ),
      HomeWidget.saveWidgetData<int>(
        'door_widget_setting_auto_refresh_minutes',
        _settings.autoRefreshMinutes,
      ),
    ];
    await Future.wait(futures);
  }

  Future<void> _persistStateToWidget() async {
    final List<Future<bool?>> futures = [
      HomeWidget.saveWidgetData<bool>(_hwBusyKey, _state.busy),
      HomeWidget.saveWidgetData<String>(_hwMessageKey, _composeWidgetMessage()),
      HomeWidget.saveWidgetData<bool?>(_hwSuccessKey, _state.lastResultSuccess),
      // 保存各状态的枚举索引值供Android原生组件读取
      HomeWidget.saveWidgetData<int>(
        'door_widget_door_lock_status',
        _state.doorLockStatus.index,
      ),
      HomeWidget.saveWidgetData<int>(
        'door_widget_device_status',
        _state.deviceStatus.index,
      ),
      HomeWidget.saveWidgetData<int>(
        'door_widget_wifi_status',
        _state.wifiStatus.index,
      ),
      HomeWidget.saveWidgetData<int>(
        'door_widget_mqtt_connection_status',
        _state.mqttConnectionStatus.index,
      ),
      HomeWidget.saveWidgetData<int>(
        'door_widget_mqtt_subscription_status',
        _state.mqttSubscriptionStatus.index,
      ),
      HomeWidget.saveWidgetData<String?>(
        _hwUpdatedKey,
        _state.lastUpdatedAt?.toIso8601String(),
      ),
    ];
    await Future.wait(futures);
  }

  String _composeWidgetMessage() {
    if (_state.busy) {
      return '正在开门…';
    }
    final bool hasStatusTopic =
        _statusTopic != null && _statusTopic!.isNotEmpty;
    final String? message = _state.lastResultMessage;
    if (!_settings.showLastResult || message == null || message.isEmpty) {
      if (hasStatusTopic && _statusIdleMessage?.isNotEmpty == true) {
        return _statusIdleMessage!;
      }
      return '未开门';
    }
    if (_state.lastResultSuccess == true) {
      return message;
    }
    if (hasStatusTopic && message == _statusIdleMessage) {
      return message;
    }
    if (message == '未开门') {
      return message;
    }
    final String timestamp = _state.lastUpdatedAt != null
        ? _formatTimestamp(_state.lastUpdatedAt!)
        : '';
    final String suffix = timestamp.isEmpty ? '' : ' · $timestamp';
    final String main = message + suffix;
    // 添加入 HTTP/MQTT 简要状态，便于微件单行显示更多信息
    final String httpState = _state.busy
        ? 'PENDING'
        : (_state.lastResultSuccess == true ? 'HTTP: OK' : 'HTTP: IDLE');
    final String mqttState =
        _statusMqttService != null && _statusMqttService!.isConnected
        ? 'MQTT: CONNECTED'
        : 'MQTT: DISCONNECTED';
    return '$main · $httpState · $mqttState';
  }

  String _formatTimestamp(DateTime value) {
    final List<String> parts = <String>[
      value.month.toString().padLeft(2, '0'),
      value.day.toString().padLeft(2, '0'),
    ];
    final List<String> time = <String>[
      value.hour.toString().padLeft(2, '0'),
      value.minute.toString().padLeft(2, '0'),
    ];
    return '${parts.join('-')} ${time.join(':')}';
  }

  void _scheduleAutoRefresh() {
    _autoRefreshTimer?.cancel();
    if (!_settings.autoRefreshEnabled || _settings.autoRefreshMinutes <= 0) {
      return;
    }
    _autoRefreshTimer = Timer.periodic(
      Duration(minutes: _settings.autoRefreshMinutes),
      (_) async {
        await _persistStateToWidget();
        await syncWidget();
      },
    );
  }

  /// 根据 MQTT 配置确保状态监听连接保持最新，必要时重建连接。
  Future<void> _ensureStatusListener({bool force = false}) async {
    if (_statusEnsuring) {
      return;
    }
    _statusEnsuring = true;
    try {
      final MqttConfig config = await MqttConfigService.instance.loadConfig(
        forceRefresh: force,
      );
      if (!config.isStatusReady) {
        await _teardownStatusListener();
        _statusIdleMessage = null;
        return;
      }
      final String host = config.host;
      final int port = config.port;
      final String statusTopic = config.statusTopic!;
      final String baseClientId = config.clientId.isNotEmpty
          ? config.clientId
          : 'flutter_client';
      final String? username = config.username;
      final String? password = config.password;
      final bool withTls = config.withTls;
      final String caPath = config.caPath;
      final String? certPath = config.certPath;
      final String? keyPath = config.keyPath;
      final String? keyPwd = config.keyPassword;

      final String fingerprint = config.buildFingerprint(
        includeStatusTopic: true,
      );

      if (!force &&
          _statusMqttService != null &&
          _statusFingerprint == fingerprint &&
          _statusMqttService!.isConnected) {
        return;
      }

      await _teardownStatusListener(updateState: false);

      SecurityContext? securityContext;
      if (withTls) {
        securityContext = await buildSecurityContext(
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

      late final MqttService service;
      service = MqttService(
        host: host,
        port: port,
        clientId: '${baseClientId}_widget_status',
        username: username,
        password: password,
        securityContext: securityContext,
        onConnected: () {
          if (_disposed || !identical(_statusMqttService, service)) {
            return;
          }
          unawaited(
            _setMqttStatus(
              connectionStatus: MqttConnectionStatus.connected,
              subscriptionStatus: MqttSubscriptionStatus.subscribed,
            ),
          );
        },
        onDisconnectedCallback: () {
          if (_disposed || !identical(_statusMqttService, service)) {
            return;
          }

          final DateTime? lastOnlineAt = _lastStatusOnlineAt;
          final bool hasRecentOnline =
              lastOnlineAt != null &&
              DateTime.now().difference(lastOnlineAt) <=
                  _deviceOnlineGracePeriod;
          // 最近仍有在线心跳时保持当前状态，避免“已连接->未连接”抖动。
          if (!hasRecentOnline) {
            unawaited(
              _setMqttStatus(
                connectionStatus: MqttConnectionStatus.disconnected,
                subscriptionStatus: MqttSubscriptionStatus.unsubscribed,
              ),
            );
          }
          _scheduleStatusReconnect();
        },
        onNotification: (String topic, Map<String, dynamic> data) {
          if (_disposed || !identical(_statusMqttService, service)) {
            return;
          }
          _handleStatusNotification(topic, data);
        },
        log: (String line) {
          if (_disposed || !identical(_statusMqttService, service)) {
            return;
          }
          _logStatusListener(line);
        },
        onError: (Object error, [StackTrace? _]) {
          if (_disposed || !identical(_statusMqttService, service)) {
            return;
          }
          debugPrint('桌面微件状态监听异常: $error');

          final DateTime? lastOnlineAt = _lastStatusOnlineAt;
          final bool hasRecentOnline =
              lastOnlineAt != null &&
              DateTime.now().difference(lastOnlineAt) <=
                  _deviceOnlineGracePeriod;
          if (!hasRecentOnline) {
            unawaited(
              _setMqttStatus(
                connectionStatus: MqttConnectionStatus.failed,
                subscriptionStatus: MqttSubscriptionStatus.unsubscribed,
              ),
            );
          }
          _scheduleStatusReconnect();
        },
      );

      _statusMqttService = service;
      _statusFingerprint = fingerprint;
      _statusTopic = statusTopic;

      try {
        await service.connect();
        await service.subscribe(statusTopic);
        await _setMqttStatus(
          connectionStatus: MqttConnectionStatus.connected,
          subscriptionStatus: MqttSubscriptionStatus.subscribed,
        );
        _statusReconnectAttempts = 0;
      } catch (error) {
        debugPrint('桌面微件状态订阅失败: $error');
        await _teardownStatusListener();
        _scheduleStatusReconnect();
      }
    } catch (error) {
      // _ensureStatusListener 常由 unawaited 调用，必须兜底避免冒泡为主异常。
      debugPrint('桌面微件状态监听初始化异常: $error');
      unawaited(
        _setMqttStatus(
          connectionStatus: MqttConnectionStatus.failed,
          subscriptionStatus: MqttSubscriptionStatus.unsubscribed,
        ),
      );
      _scheduleStatusReconnect();
    } finally {
      _statusEnsuring = false;
    }
  }

  Future<void> _teardownStatusListener({bool updateState = true}) async {
    _statusReconnectTimer?.cancel();
    _statusReconnectTimer = null;
    final MqttService? service = _statusMqttService;
    _statusMqttService = null;
    _statusFingerprint = null;
    _statusTopic = null;
    _lastStatusPayload = null;
    _lastStatusLogAt = null;
    _lastStatusLogLine = null;
    if (service != null) {
      try {
        await service.dispose();
      } catch (_) {
        // 忽略释放异常
      }
    }
    if (updateState) {
      _statusIdleMessage = null;
      _lastStatusOnlineAt = null;
      _statusReconnectAttempts = 0;
    }
    if (updateState) {
      await _setMqttStatus(
        connectionStatus: MqttConnectionStatus.disconnected,
        subscriptionStatus: MqttSubscriptionStatus.unsubscribed,
      );
    }
  }

  Future<void> _setMqttStatus({
    required MqttConnectionStatus connectionStatus,
    required MqttSubscriptionStatus subscriptionStatus,
  }) async {
    if (_disposed) {
      return;
    }
    await _ensureLoaded();
    DoorWidgetState next = _state;
    if (next.mqttConnectionStatus != connectionStatus) {
      next = next.copyWith(mqttConnectionStatus: connectionStatus);
    }
    if (next.mqttSubscriptionStatus != subscriptionStatus) {
      next = next.copyWith(mqttSubscriptionStatus: subscriptionStatus);
    }
    if (next == _state) {
      return;
    }
    _state = next;
    stateNotifier.value = _state;
    await _saveState();
    await _persistStateToWidget();
    await syncWidget();
  }

  void _logStatusListener(String line) {
    final String normalizedLine = line.trim();
    if (normalizedLine.isEmpty) {
      return;
    }

    final DateTime now = DateTime.now();
    final DateTime? lastLogAt = _lastStatusLogAt;
    final String? lastLogLine = _lastStatusLogLine;

    final bool isConnectedLine = normalizedLine.contains('[MQTT] connected');
    final Duration silenceWindow = isConnectedLine
        ? const Duration(seconds: 30)
        : const Duration(seconds: 1);

    if (lastLogLine == normalizedLine &&
        lastLogAt != null &&
        now.difference(lastLogAt) < silenceWindow) {
      return;
    }

    if (lastLogAt != null &&
        now.difference(lastLogAt) < const Duration(milliseconds: 300)) {
      return;
    }

    _lastStatusLogLine = normalizedLine;
    _lastStatusLogAt = now;
    debugPrint('桌面微件状态监听: $normalizedLine');
  }

  void _scheduleStatusReconnect() {
    if (_disposed) {
      return;
    }
    if (_statusReconnectTimer?.isActive ?? false) {
      return;
    }

    int delaySeconds = 8 * (1 << _statusReconnectAttempts);
    if (delaySeconds > 120) {
      delaySeconds = 120;
    }
    if (_statusReconnectAttempts < 5) {
      _statusReconnectAttempts += 1;
    }

    _statusReconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _statusReconnectTimer = null;
      if (_disposed) {
        return;
      }
      unawaited(_ensureStatusListener(force: true));
    });
  }

  void _handleStatusNotification(String topic, Map<String, dynamic> data) {
    if (_disposed) {
      return;
    }
    if (_statusTopic == null || topic != _statusTopic) {
      return;
    }
    final dynamic raw =
        data['payload'] ?? data['message'] ?? data['data'] ?? data['value'];
    if (raw == null) {
      return;
    }
    final String payload = raw.toString().trim();
    if (payload.isEmpty) {
      return;
    }
    final String normalized = payload.toLowerCase();
    final bool isOnlineHeartbeat = normalized == 'online' || normalized == 'on';

    // 与上次消息一致时直接保持：仅刷新心跳时间，不重复更新状态。
    if (payload == _lastStatusPayload) {
      if (isOnlineHeartbeat) {
        _lastStatusOnlineAt = DateTime.now();
      }
      return;
    }

    if (isOnlineHeartbeat) {
      _lastStatusOnlineAt = DateTime.now();
      // 收到在线心跳时，视作 MQTT 连接可用。
      unawaited(
        _setMqttStatus(
          connectionStatus: MqttConnectionStatus.connected,
          subscriptionStatus: MqttSubscriptionStatus.subscribed,
        ),
      );
    }

    _lastStatusPayload = payload;

    if (normalized == 'online') {
      _statusIdleMessage = '设备在线';
      unawaited(_checkAndUpdateState());
    } else if (normalized == 'on') {
      _statusIdleMessage = '设备在线';
      unawaited(_checkAndUpdateState());
      unawaited(
        _applyStatusMessage(
          message: '开门成功',
          success: true,
          scheduleReset: true,
        ),
      );
    }
  }

  Future<void> _applyStatusMessage({
    required String message,
    bool? success,
    bool scheduleReset = false,
  }) async {
    await _ensureLoaded();
    final bool keepManualResult =
        _manualResultDeadline != null &&
        DateTime.now().isBefore(_manualResultDeadline!) &&
        _state.doorLockStatus != DoorLockStatus.pending;
    if (keepManualResult && success == null) {
      return;
    }

    DoorLockStatus? nextDoorLockStatus;
    if (success == true) {
      nextDoorLockStatus = DoorLockStatus.success;
      _manualResultDeadline = DateTime.now().add(
        _manualTriggerDebounceInterval,
      );
    } else if (success == false) {
      nextDoorLockStatus = DoorLockStatus.failed;
      _manualResultDeadline = DateTime.now().add(
        _manualTriggerDebounceInterval,
      );
    }

    _successResetTimer?.cancel();
    _state = _state.copyWith(
      busy: false,
      lastResultSuccess: success,
      lastResultMessage: message,
      lastUpdatedAt: DateTime.now(),
      doorLockStatus: nextDoorLockStatus,
    );
    stateNotifier.value = _state;
    await _saveState();
    await _persistStateToWidget();
    await syncWidget();
    if (scheduleReset && success == true) {
      _scheduleSuccessReset();
    }
  }

  /// 成功开门后延时恢复默认提示，保持微件状态清爽。
  void _scheduleSuccessReset() {
    _successResetTimer?.cancel();
    _successResetTimer = Timer(_manualSuccessDisplayDuration, () async {
      await _ensureLoaded();
      if (_state.busy) {
        return;
      }
      final bool hasStatusTopic =
          _statusTopic != null && _statusTopic!.isNotEmpty;
      final String? fallbackMessage = hasStatusTopic
          ? (_statusIdleMessage?.isNotEmpty == true ? _statusIdleMessage : null)
          : _statusIdleMessage;
      _state = _state.copyWith(
        lastResultSuccess: null,
        lastResultMessage: fallbackMessage ?? '未开门',
        lastUpdatedAt: DateTime.now(),
        doorLockStatus: DoorLockStatus.pending,
      );
      _manualResultDeadline = null;
      stateNotifier.value = _state;
      await _saveState();
      await _persistStateToWidget();
      await syncWidget();
    });
  }

  /// 启动状态被动监控定时器，检测WiFi和MQTT状态变化
  void _startStateMonitoring() {
    _stateMonitorTimer?.cancel();
    // 每5秒检测一次状态变化，降低抖动与资源占用。
    _stateMonitorTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkAndUpdateState(),
    );
    // 立即执行一次检测
    unawaited(_checkAndUpdateState());
  }

  /// 检测并更新状态变化
  Future<void> _checkAndUpdateState() async {
    if (_disposed) return;
    await _ensureLoaded();

    WifiStatus? nextWifiStatus;
    DeviceStatus? nextDeviceStatus;

    // 检测WiFi状态
    try {
      WifiStatus? newWifiStatus;
      String? newWifiIdentifier;

      // 检测WiFi连接
      final List<ConnectivityResult> connectivityResults = await Connectivity()
          .checkConnectivity();
      final bool hasWifi = connectivityResults.contains(
        ConnectivityResult.wifi,
      );

      final localConfig = await LocalDoorLockConfigService.instance
          .loadConfig();
      final bool needCheckMapping =
          localConfig.postEnabled && localConfig.wifiPostEnabled;
      if (!hasWifi) {
        newWifiStatus = WifiStatus.disconnected;
        newWifiIdentifier = '';
      } else if (!needCheckMapping) {
        newWifiStatus = WifiStatus.connected;
        newWifiIdentifier = 'connected-no-mapping';
      } else {
        final currentWifi = await WifiInfoService.instance.getCurrentWifi();
        if (currentWifi.hasValidValue) {
          newWifiIdentifier = '${currentWifi.ssid}:${currentWifi.bssid}';
          final bool matched = localConfig.wifiPostMappings.any(
            (m) => m.matches(ssid: currentWifi.ssid, bssid: currentWifi.bssid),
          );
          newWifiStatus = matched
              ? WifiStatus.connected
              : WifiStatus.unconfigured;
        } else {
          // WiFi已连接但无法获取有效信息时，保持当前缓存的状态不变
          // 避免因临时无法获取WiFi信息导致状态抖动
          newWifiStatus = _cachedWifiStatus ?? WifiStatus.connected;
          newWifiIdentifier = _lastWifiIdentifier;
        }
      }

      final _WifiObservation observation = _WifiObservation(
        status: newWifiStatus,
        identifier: newWifiIdentifier,
      );

      if (observation == _lastWifiObservation) {
        // 与上一次已确认采样一致时不更新，保持与 MQTT/设备状态相同的去重策略。
        _pendingWifiObservation = null;
      } else if (_pendingWifiObservation != observation) {
        // 首次看到新采样先缓存，等待下一次采样再次确认，避免偶发抖动误切换。
        _pendingWifiObservation = observation;
      } else {
        _pendingWifiObservation = null;
        _lastWifiObservation = observation;
        _lastWifiIdentifier = newWifiIdentifier;
        _cachedWifiStatus = newWifiStatus;
        nextWifiStatus = newWifiStatus;
      }
    } catch (_) {
      // 忽略WiFi检测错误
    }

    // 根据最近在线心跳判断设备状态，避免连接抖动导致在线/离线来回闪烁。
    final DateTime? lastOnlineAt = _lastStatusOnlineAt;
    final bool isOnlineByHeartbeat =
        lastOnlineAt != null &&
        DateTime.now().difference(lastOnlineAt) <= _deviceOnlineGracePeriod;
    nextDeviceStatus = isOnlineByHeartbeat
        ? DeviceStatus.online
        : DeviceStatus.offline;

    DoorWidgetState merged = _state;
    if (nextWifiStatus != null && merged.wifiStatus != nextWifiStatus) {
      merged = merged.copyWith(wifiStatus: nextWifiStatus);
    }
    if (merged.deviceStatus != nextDeviceStatus) {
      merged = merged.copyWith(deviceStatus: nextDeviceStatus);
    }

    // 仅提交变化字段，避免覆盖并发写入的开门结果状态。
    if (merged != _state) {
      _state = merged;
      stateNotifier.value = _state;
      await _saveState();
      await _persistStateToWidget();
      await syncWidget();
    }
  }
}

/// 桌面微件交互回调入口，需保持顶层函数以便原生侧正确定位。
@pragma('vm:entry-point')
Future<void> doorWidgetBackgroundCallback(Uri? data) async {
  WidgetsFlutterBinding.ensureInitialized();
  await DoorWidgetService.instance.handleWidgetInteraction(data);
}
