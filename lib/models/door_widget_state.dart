/// 桌面小部件的运行时状态数据模型，包含当前是否忙碌、上次操作是否成功、
/// 上次操作信息以及最后更新时间等字段。
class DoorWidgetState {
  final bool busy;
  final bool? lastResultSuccess;
  final String? lastResultMessage;
  final DateTime? lastUpdatedAt;

  const DoorWidgetState({
    required this.busy,
    required this.lastResultSuccess,
    required this.lastResultMessage,
    required this.lastUpdatedAt,
  });

  /// 返回初始状态实例：处于空闲且没有任何历史结果。
  factory DoorWidgetState.initial() => const DoorWidgetState(
    busy: false,
    lastResultSuccess: null,
    lastResultMessage: null,
    lastUpdatedAt: null,
  );

  static const Object _unset = Object();

  /// 复制当前状态并更新指定字段，采用特殊占位对象 `_unset` 区分未传值和显式 `null`。
  DoorWidgetState copyWith({
    bool? busy,
    Object? lastResultSuccess = _unset,
    Object? lastResultMessage = _unset,
    Object? lastUpdatedAt = _unset,
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
    );
  }

  /// 序列化为 Map，方便持久化存储（例如 SharedPreferences）。
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'busy': busy,
      'lastResultSuccess': lastResultSuccess,
      'lastResultMessage': lastResultMessage,
      'lastUpdatedAt': lastUpdatedAt?.toIso8601String(),
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
    );
  }

  @override
  String toString() {
    return 'DoorWidgetState(busy: $busy, lastResultSuccess: '
        '$lastResultSuccess, lastResultMessage: $lastResultMessage, '
        'lastUpdatedAt: $lastUpdatedAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is DoorWidgetState &&
        other.busy == busy &&
        other.lastResultSuccess == lastResultSuccess &&
        other.lastResultMessage == lastResultMessage &&
        other.lastUpdatedAt == lastUpdatedAt;
  }

  @override
  int get hashCode =>
      Object.hash(busy, lastResultSuccess, lastResultMessage, lastUpdatedAt);
}
