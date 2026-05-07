/// 网页导入课表使用的学校信息模型。
///
/// 每个学校对应一个教务系统网页地址，用户通过选择学校
/// 进入对应教务系统完成课表导入。
class WebSchool {
  /// 学校名称。
  final String name;

  /// 教务系统网页地址。
  final String url;

  /// 校徽图片的 Base64 数据。
  ///
  /// 为空时表示使用默认图标或预设校徽。
  final String? badgeBase64;

  const WebSchool({required this.name, required this.url, this.badgeBase64});

  /// 将学校信息序列化为 JSON Map，便于持久化存储。
  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'badgeBase64': badgeBase64,
  };

  /// 从 JSON Map 创建 `WebSchool` 实例。
  factory WebSchool.fromJson(Map<String, dynamic> json) {
    return WebSchool(
      name: json['name'] as String,
      url: json['url'] as String,
      badgeBase64: json['badgeBase64'] as String?,
    );
  }

  /// 创建副本并可选覆盖字段。
  WebSchool copyWith({String? name, String? url, String? badgeBase64}) {
    return WebSchool(
      name: name ?? this.name,
      url: url ?? this.url,
      badgeBase64: badgeBase64 ?? this.badgeBase64,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WebSchool &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          url == other.url &&
          badgeBase64 == other.badgeBase64;

  @override
  int get hashCode => name.hashCode ^ url.hashCode ^ badgeBase64.hashCode;
}
