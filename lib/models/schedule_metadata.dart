class ScheduleMetadata {
  final String id;
  final String name;

  ScheduleMetadata({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory ScheduleMetadata.fromJson(Map<String, dynamic> json) {
    return ScheduleMetadata(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }
}
