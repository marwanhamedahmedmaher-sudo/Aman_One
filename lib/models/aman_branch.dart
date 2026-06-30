/// An Aman branch (lookup row from `public.aman_branches`) for the mission-3
/// visit dropdown.
class AmanBranch {
  final String id;
  final String nameAr;
  final int? governorateId;

  const AmanBranch({
    required this.id,
    required this.nameAr,
    this.governorateId,
  });

  factory AmanBranch.fromJson(Map<String, dynamic> json) => AmanBranch(
        id: json['id'] as String,
        nameAr: json['name_ar'] as String? ?? '',
        governorateId: (json['governorate_id'] as num?)?.toInt(),
      );
}
