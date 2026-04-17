class ActivityType {
  final String id;
  final String name;
  final int sortOrder;

  const ActivityType({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  factory ActivityType.fromJson(Map<String, dynamic> json) {
    return ActivityType(
      id: json['id'] as String,
      name: json['name'] as String,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }
}
