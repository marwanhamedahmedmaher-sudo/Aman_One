/// A planned stop for a field task (a row in `public.task_plan_items`).
///
/// Weekly planning: the rep pre-picks WHERE they'll go in each window. During
/// the week, executing a planned stop logs a visit and flips [status] to
/// 'visited' (with [visitId] set). No GPS / photo / counts here — those are
/// captured only when the visit is actually logged.
class TaskPlanItem {
  final String id;
  final String taskId;
  final String templateSlug;
  final int? governorateId;
  final String? governorateName; // joined, optional
  final String notes;
  // mission 1
  final String? placeKind;
  final String? placeName;
  // mission 2
  final List<String> products;
  final String? merchantName;
  final String? businessName;
  // mission 3
  final String? branchId;
  final String? branchName; // joined, optional
  // execution
  final String status; // 'planned' | 'visited' | 'skipped'
  final String? visitId;

  const TaskPlanItem({
    required this.id,
    required this.taskId,
    required this.templateSlug,
    this.governorateId,
    this.governorateName,
    this.notes = '',
    this.placeKind,
    this.placeName,
    this.products = const [],
    this.merchantName,
    this.businessName,
    this.branchId,
    this.branchName,
    this.status = 'planned',
    this.visitId,
  });

  bool get isVisited => status == 'visited';

  /// A short headline — the institution / merchant / branch name.
  String get title {
    if (placeName != null && placeName!.isNotEmpty) return placeName!;
    final m = [merchantName, businessName].where((s) => s != null && s.isNotEmpty);
    if (m.isNotEmpty) return m.join(' - ');
    if (branchName != null && branchName!.isNotEmpty) return branchName!;
    return 'زيارة مخططة';
  }

  factory TaskPlanItem.fromJson(Map<String, dynamic> json) {
    final gov = json['governorates'] as Map<String, dynamic>?;
    final branch = json['aman_branches'] as Map<String, dynamic>?;
    return TaskPlanItem(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      templateSlug: json['template_slug'] as String? ?? '',
      governorateId: (json['governorate_id'] as num?)?.toInt(),
      governorateName: gov?['name_ar'] as String?,
      notes: json['notes'] as String? ?? '',
      placeKind: json['place_kind'] as String?,
      placeName: json['place_name'] as String?,
      products:
          (json['products'] as List?)?.map((e) => e as String).toList() ?? const [],
      merchantName: json['merchant_name'] as String?,
      businessName: json['business_name'] as String?,
      branchId: json['branch_id'] as String?,
      branchName: branch?['name_ar'] as String?,
      status: json['status'] as String? ?? 'planned',
      visitId: json['visit_id'] as String?,
    );
  }
}
