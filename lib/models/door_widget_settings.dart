/// 桌面微件的显示与行为配置，支持转换为 Map 以便持久化。
class DoorWidgetSettings {
  final bool showLastResult;
  final bool enableHaptics;
  final bool autoRefreshEnabled;
  final int autoRefreshMinutes;

  const DoorWidgetSettings({
    required this.showLastResult,
    required this.enableHaptics,
    required this.autoRefreshEnabled,
    required this.autoRefreshMinutes,
  });

  /// 提供默认配置，避免未初始化时出现空指针。
  factory DoorWidgetSettings.defaults() => const DoorWidgetSettings(
    showLastResult: true,
    enableHaptics: true,
    autoRefreshEnabled: false,
    autoRefreshMinutes: 30,
  );

  /// 复制当前配置并应用增量修改。
  DoorWidgetSettings copyWith({
    bool? showLastResult,
    bool? enableHaptics,
    bool? autoRefreshEnabled,
    int? autoRefreshMinutes,
  }) {
    return DoorWidgetSettings(
      showLastResult: showLastResult ?? this.showLastResult,
      enableHaptics: enableHaptics ?? this.enableHaptics,
      autoRefreshEnabled: autoRefreshEnabled ?? this.autoRefreshEnabled,
      autoRefreshMinutes: autoRefreshMinutes ?? this.autoRefreshMinutes,
    );
  }

  /// 转换为 Map 存储结构，便于写入 SharedPreferences。
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'showLastResult': showLastResult,
      'enableHaptics': enableHaptics,
      'autoRefreshEnabled': autoRefreshEnabled,
      'autoRefreshMinutes': autoRefreshMinutes,
    };
  }

  /// 从 Map 数据还原配置对象，兼容缺失字段场景。
  factory DoorWidgetSettings.fromMap(Map<String, dynamic> map) {
    return DoorWidgetSettings(
      showLastResult: map['showLastResult'] as bool? ?? true,
      enableHaptics: map['enableHaptics'] as bool? ?? true,
      autoRefreshEnabled: map['autoRefreshEnabled'] as bool? ?? false,
      autoRefreshMinutes: map['autoRefreshMinutes'] as int? ?? 30,
    );
  }

  @override
  String toString() {
    return 'DoorWidgetSettings(showLastResult: $showLastResult, enableHaptics: '
        '$enableHaptics, autoRefreshEnabled: $autoRefreshEnabled, '
        'autoRefreshMinutes: $autoRefreshMinutes)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is DoorWidgetSettings &&
        other.showLastResult == showLastResult &&
        other.enableHaptics == enableHaptics &&
        other.autoRefreshEnabled == autoRefreshEnabled &&
        other.autoRefreshMinutes == autoRefreshMinutes;
  }

  @override
  int get hashCode => Object.hash(
    showLastResult,
    enableHaptics,
    autoRefreshEnabled,
    autoRefreshMinutes,
  );
}
