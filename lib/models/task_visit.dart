/// The three field-task missions, keyed by the DB `task_templates.slug`.
/// The visit form is rendered per mission.
enum VisitMission {
  govSchools('gov_schools_hospitals'),
  merchants('merchants_acceptance_finance'),
  branch('aman_branch_visit');

  final String slug;
  const VisitMission(this.slug);

  static VisitMission? fromSlug(String? slug) {
    for (final m in VisitMission.values) {
      if (m.slug == slug) return m;
    }
    return null;
  }
}

/// Mission-1 place kind (single-select).
enum PlaceKind {
  school('school', 'مدرسة'),
  govInstitution('gov_institution', 'مؤسسة حكومية'),
  hospital('hospital', 'مستشفى');

  final String value;
  final String labelAr;
  const PlaceKind(this.value, this.labelAr);

  /// Arabic label for a stored `place_kind` string (falls back to the raw value).
  static String labelForValue(String value) {
    for (final k in PlaceKind.values) {
      if (k.value == value) return k.labelAr;
    }
    return value;
  }
}

/// Mission-2 product. Stored as a string in the `products` text[] column.
enum VisitProduct {
  microfinance('microfinance', 'تمويل'),
  acceptance('acceptance', 'Acceptance');

  final String value;
  final String labelAr;
  const VisitProduct(this.value, this.labelAr);

  /// Arabic label for a stored product string (falls back to the raw value).
  static String labelForValue(String value) {
    for (final p in VisitProduct.values) {
      if (p.value == value) return p.labelAr;
    }
    return value;
  }

  /// " + "-joined Arabic labels for a list of stored product strings.
  static String joinLabels(List<String> products) =>
      products.map(labelForValue).join(' + ');
}

/// One logged field visit (a row in `public.task_visits`).
class TaskVisit {
  final String id;
  final String taskId;
  final String templateSlug;
  final double lat;
  final double lng;
  final double? accuracyM;
  final DateTime recordedAt;
  final bool inWindow;
  final int? governorateId;
  final String? governorateName; // joined, optional
  final String photoPath;
  final String notes;
  final int contactedCount;
  final int onboardedCount;
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
  // mission 2: «هل تم التقديم؟»
  final bool? applicationSubmitted;

  const TaskVisit({
    required this.id,
    required this.taskId,
    required this.templateSlug,
    required this.lat,
    required this.lng,
    this.accuracyM,
    required this.recordedAt,
    required this.inWindow,
    this.governorateId,
    this.governorateName,
    required this.photoPath,
    this.notes = '',
    this.contactedCount = 0,
    this.onboardedCount = 0,
    this.placeKind,
    this.placeName,
    this.products = const [],
    this.merchantName,
    this.businessName,
    this.branchId,
    this.branchName,
    this.applicationSubmitted,
  });

  /// A short headline for the visit list — the institution/merchant/branch name.
  String get title {
    if (placeName != null && placeName!.isNotEmpty) return placeName!;
    final m = [merchantName, businessName].where((s) => s != null && s.isNotEmpty);
    if (m.isNotEmpty) return m.join(' - ');
    if (branchName != null && branchName!.isNotEmpty) return branchName!;
    return 'زيارة';
  }

  factory TaskVisit.fromJson(Map<String, dynamic> json) {
    final gov = json['governorates'] as Map<String, dynamic>?;
    final branch = json['aman_branches'] as Map<String, dynamic>?;
    return TaskVisit(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      templateSlug: json['template_slug'] as String? ?? '',
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      inWindow: json['in_window'] as bool? ?? false,
      governorateId: (json['governorate_id'] as num?)?.toInt(),
      governorateName: gov?['name_ar'] as String?,
      photoPath: json['photo_path'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      contactedCount: (json['contacted_count'] as num?)?.toInt() ?? 0,
      onboardedCount: (json['onboarded_count'] as num?)?.toInt() ?? 0,
      placeKind: json['place_kind'] as String?,
      placeName: json['place_name'] as String?,
      products: (json['products'] as List?)?.map((e) => e as String).toList() ?? const [],
      merchantName: json['merchant_name'] as String?,
      businessName: json['business_name'] as String?,
      branchId: json['branch_id'] as String?,
      branchName: branch?['name_ar'] as String?,
      applicationSubmitted: json['application_submitted'] as bool?,
    );
  }
}
