/// 课程表的元数据，用于在多课程表场景下展示与切换
/// 包含课程表的唯一 id 与用于展示的名称
class ScheduleMetadata {
  final String id;
  final String name;

  ScheduleMetadata({required this.id, required this.name});

  /// 将元数据序列化为 JSON Map，便于持久化存储
  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  /// 从 JSON Map 创建 `ScheduleMetadata` 实例
  factory ScheduleMetadata.fromJson(Map<String, dynamic> json) {
    return ScheduleMetadata(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }
}
