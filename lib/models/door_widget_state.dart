/// 门锁状态枚举：待开门、开门成功、开门失败
enum DoorLockStatus {
  pending, // 待开门（灰色）
  success, // 开门成功（绿色）
  failed, // 开门失败（红色）
}

/// 设备状态枚举：设备在线、设备离线、设备异常
enum DeviceStatus {
  online, // 设备在线（绿色）
  offline, // 设备离线（灰色）
  abnormal, // 设备异常（黄色）
}

/// WiFi状态枚举：已连接、未连接、非匹配
enum WifiStatus {
  connected, // 已连接（绿色）
  disconnected, // 未连接（灰色）
  unconfigured, // 已连接但不在HTTP映射列表（黄色）
}

/// MQTT连接状态枚举
enum MqttConnectionStatus {
  connected, // 连接成功（绿色）
  disconnected, // 未连接（灰色）
  failed, // 连接失败（红色）
}

/// MQTT订阅状态枚举
enum MqttSubscriptionStatus {
  subscribed, // 已订阅（绿色）
  unsubscribed, // 未订阅（灰色）
}

/// 桌面小部件的运行时状态数据模型，包含当前是否忙碌、上次操作是否成功、
/// 上次操作信息以及最后更新时间等字段。
class DoorWidgetState {
  final bool busy;
  final bool? lastResultSuccess;
  final String? lastResultMessage;
  final DateTime? lastUpdatedAt;

  /// 门锁状态：待开门/开门成功/开门失败
  final DoorLockStatus doorLockStatus;

  /// 设备状态：在线/离线/异常
  final DeviceStatus deviceStatus;

  /// WiFi状态：已连接/未连接
  final WifiStatus wifiStatus;

  /// MQTT连接状态：连接成功/连接失败
  final MqttConnectionStatus mqttConnectionStatus;

  /// MQTT订阅状态：已订阅/未订阅
  final MqttSubscriptionStatus mqttSubscriptionStatus;

  const DoorWidgetState({
    required this.busy,
    required this.lastResultSuccess,
    required this.lastResultMessage,
    required this.lastUpdatedAt,
    required this.doorLockStatus,
    required this.deviceStatus,
    required this.wifiStatus,
    required this.mqttConnectionStatus,
    required this.mqttSubscriptionStatus,
  });

  /// 返回初始状态实例：处于空闲且没有任何历史结果。
  factory DoorWidgetState.initial() => const DoorWidgetState(
    busy: false,
    lastResultSuccess: null,
    lastResultMessage: null,
    lastUpdatedAt: null,
    doorLockStatus: DoorLockStatus.pending,
    deviceStatus: DeviceStatus.offline,
    wifiStatus: WifiStatus.disconnected,
    mqttConnectionStatus: MqttConnectionStatus.disconnected,
    mqttSubscriptionStatus: MqttSubscriptionStatus.unsubscribed,
  );

  static const Object _unset = Object();

  /// 复制当前状态并更新指定字段，采用特殊占位对象 `_unset` 区分未传值和显式 `null`。
  DoorWidgetState copyWith({
    bool? busy,
    Object? lastResultSuccess = _unset,
    Object? lastResultMessage = _unset,
    Object? lastUpdatedAt = _unset,
    DoorLockStatus? doorLockStatus,
    DeviceStatus? deviceStatus,
    WifiStatus? wifiStatus,
    MqttConnectionStatus? mqttConnectionStatus,
    MqttSubscriptionStatus? mqttSubscriptionStatus,
  }) {
    return DoorWidgetState(
      busy: busy ?? this.busy,
      lastResultSuccess: lastResultSuccess == _unset
          ? this.lastResultSuccess
          : lastResultSuccess as bool?,
      lastResultMessage: lastResultMessage == _unset
          ? this.lastResultMessage
          : lastResultMessage as String?,
      lastUpdatedAt: lastUpdatedAt == _unset
          ? this.lastUpdatedAt
          : lastUpdatedAt as DateTime?,
      doorLockStatus: doorLockStatus ?? this.doorLockStatus,
      deviceStatus: deviceStatus ?? this.deviceStatus,
      wifiStatus: wifiStatus ?? this.wifiStatus,
      mqttConnectionStatus: mqttConnectionStatus ?? this.mqttConnectionStatus,
      mqttSubscriptionStatus:
          mqttSubscriptionStatus ?? this.mqttSubscriptionStatus,
    );
  }

  /// 序列化为 Map，方便持久化存储（例如 SharedPreferences）。
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'busy': busy,
      'lastResultSuccess': lastResultSuccess,
      'lastResultMessage': lastResultMessage,
      'lastUpdatedAt': lastUpdatedAt?.toIso8601String(),
      'doorLockStatus': doorLockStatus.index,
      'deviceStatus': deviceStatus.index,
      'wifiStatus': wifiStatus.index,
      'mqttConnectionStatus': mqttConnectionStatus.index,
      'mqttSubscriptionStatus': mqttSubscriptionStatus.index,
    };
  }

  /// 从 Map 恢复 `DoorWidgetState`，对缺失字段使用默认值以保证健壮性。
  factory DoorWidgetState.fromMap(Map<String, dynamic> map) {
    return DoorWidgetState(
      busy: map['busy'] as bool? ?? false,
      lastResultSuccess: map['lastResultSuccess'] as bool?,
      lastResultMessage: map['lastResultMessage'] as String?,
      lastUpdatedAt: map['lastUpdatedAt'] is String
          ? DateTime.tryParse(map['lastUpdatedAt'] as String)
          : null,
      doorLockStatus:
          DoorLockStatus.values.elementAtOrNull(
            map['doorLockStatus'] as int? ?? 0,
          ) ??
          DoorLockStatus.pending,
      deviceStatus:
          DeviceStatus.values.elementAtOrNull(
            map['deviceStatus'] as int? ?? 1,
          ) ??
          DeviceStatus.offline,
      wifiStatus:
          WifiStatus.values.elementAtOrNull(map['wifiStatus'] as int? ?? 1) ??
          WifiStatus.disconnected,
      mqttConnectionStatus:
          MqttConnectionStatus.values.elementAtOrNull(
            map['mqttConnectionStatus'] as int? ?? 1,
          ) ??
          MqttConnectionStatus.disconnected,
      mqttSubscriptionStatus:
          MqttSubscriptionStatus.values.elementAtOrNull(
            map['mqttSubscriptionStatus'] as int? ?? 1,
          ) ??
          MqttSubscriptionStatus.unsubscribed,
    );
  }

  @override
  String toString() {
    return 'DoorWidgetState(busy: $busy, lastResultSuccess: '
        '$lastResultSuccess, lastResultMessage: $lastResultMessage, '
        'lastUpdatedAt: $lastUpdatedAt, doorLockStatus: $doorLockStatus, '
        'deviceStatus: $deviceStatus, wifiStatus: $wifiStatus, '
        'mqttConnectionStatus: $mqttConnectionStatus, '
        'mqttSubscriptionStatus: $mqttSubscriptionStatus)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is DoorWidgetState &&
        other.busy == busy &&
        other.lastResultSuccess == lastResultSuccess &&
        other.lastResultMessage == lastResultMessage &&
        other.lastUpdatedAt == lastUpdatedAt &&
        other.doorLockStatus == doorLockStatus &&
        other.deviceStatus == deviceStatus &&
        other.wifiStatus == wifiStatus &&
        other.mqttConnectionStatus == mqttConnectionStatus &&
        other.mqttSubscriptionStatus == mqttSubscriptionStatus;
  }

  @override
  int get hashCode => Object.hash(
    busy,
    lastResultSuccess,
    lastResultMessage,
    lastUpdatedAt,
    doorLockStatus,
    deviceStatus,
    wifiStatus,
    mqttConnectionStatus,
    mqttSubscriptionStatus,
  );
}
