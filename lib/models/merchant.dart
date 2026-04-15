class Lead {
  final String? id;
  final String name;
  final String phone;
  final String nationalId;
  final String notes;
  final String status;
  final String? createdBy;
  final DateTime? createdAt;

  const Lead({
    this.id,
    required this.name,
    required this.phone,
    required this.nationalId,
    this.notes = '',
    this.status = 'lead',
    this.createdBy,
    this.createdAt,
  });

  factory Lead.empty() {
    return const Lead(name: '', phone: '', nationalId: '');
  }

  Lead copyWith({
    String? id,
    String? name,
    String? phone,
    String? nationalId,
    String? notes,
    String? status,
    String? createdBy,
    DateTime? createdAt,
  }) {
    return Lead(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      nationalId: nationalId ?? this.nationalId,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
      'national_id': nationalId,
      'notes': notes,
      'status': status,
    };
  }

  factory Lead.fromJson(Map<String, dynamic> json) {
    return Lead(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      nationalId: json['national_id'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      status: json['status'] as String? ?? 'lead',
      createdBy: json['created_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}
