/// An Egyptian governorate (lookup row from `public.governorates`).
class Governorate {
  final int id; // official governorate code
  final String nameAr;

  const Governorate({required this.id, required this.nameAr});

  factory Governorate.fromJson(Map<String, dynamic> json) => Governorate(
        id: (json['id'] as num).toInt(),
        nameAr: json['name_ar'] as String? ?? '',
      );
}
