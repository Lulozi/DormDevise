/// 桌面微件的运行态数据，包括忙碌状态与上次开门结果等信息。
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

  /// 构建初始状态，默认处于空闲并无历史记录。
  factory DoorWidgetState.initial() => const DoorWidgetState(
    busy: false,
    lastResultSuccess: null,
    lastResultMessage: null,
    lastUpdatedAt: null,
  );

  static const Object _unset = Object();

  /// 复制当前状态并根据入参更新部分字段，支持显式写入 `null` 以清除旧值。
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

  /// 序列化为 Map，便于写入 SharedPreferences。
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'busy': busy,
      'lastResultSuccess': lastResultSuccess,
      'lastResultMessage': lastResultMessage,
      'lastUpdatedAt': lastUpdatedAt?.toIso8601String(),
    };
  }

  /// 从 Map 结构恢复状态实例，对于缺失字段提供默认值。
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
