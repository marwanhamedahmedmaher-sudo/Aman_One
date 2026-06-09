class Lead {
  final String? id;
  final String name;
  final String phone;
  final String nationalId;
  final String idDocumentType; // 'national_id' (Egyptian) | 'passport' (foreigner)
  final String notes;
  final List<String> products;
  final double? microfinanceAmount;
  final int? acceptanceDeviceCount;
  final double? avgMonthlySales;
  final String? businessAddress;
  final String? activityTypeId;
  final String? activityTypeName; // display-only, from join
  final String status;
  final String? createdBy;
  final DateTime? createdAt;

  const Lead({
    this.id,
    required this.name,
    required this.phone,
    required this.nationalId,
    this.idDocumentType = 'national_id',
    this.notes = '',
    this.products = const [],
    this.microfinanceAmount,
    this.acceptanceDeviceCount,
    this.avgMonthlySales,
    this.businessAddress,
    this.activityTypeId,
    this.activityTypeName,
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
    String? idDocumentType,
    String? notes,
    List<String>? products,
    double? Function()? microfinanceAmount,
    int? Function()? acceptanceDeviceCount,
    double? Function()? avgMonthlySales,
    String? Function()? businessAddress,
    String? Function()? activityTypeId,
    String? Function()? activityTypeName,
    String? status,
    String? createdBy,
    DateTime? createdAt,
  }) {
    return Lead(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      nationalId: nationalId ?? this.nationalId,
      idDocumentType: idDocumentType ?? this.idDocumentType,
      notes: notes ?? this.notes,
      products: products ?? this.products,
      microfinanceAmount: microfinanceAmount != null
          ? microfinanceAmount()
          : this.microfinanceAmount,
      acceptanceDeviceCount: acceptanceDeviceCount != null
          ? acceptanceDeviceCount()
          : this.acceptanceDeviceCount,
      avgMonthlySales: avgMonthlySales != null
          ? avgMonthlySales()
          : this.avgMonthlySales,
      businessAddress: businessAddress != null
          ? businessAddress()
          : this.businessAddress,
      activityTypeId: activityTypeId != null
          ? activityTypeId()
          : this.activityTypeId,
      activityTypeName: activityTypeName != null
          ? activityTypeName()
          : this.activityTypeName,
      status: status ?? this.status,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'name': name,
      'phone': phone,
      'national_id': nationalId,
      'notes': notes,
      'products': products,
      'microfinance_amount': microfinanceAmount,
      'acceptance_device_count': acceptanceDeviceCount,
      'avg_monthly_sales': avgMonthlySales,
      'business_address': businessAddress,
      'activity_type_id': activityTypeId,
      'status': status,
    };
    if (createdBy != null) {
      json['created_by'] = createdBy;
    }
    return json;
  }

  factory Lead.fromJson(Map<String, dynamic> json) {
    return Lead(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      nationalId: json['national_id'] as String? ?? '',
      idDocumentType: json['id_document_type'] as String? ?? 'national_id',
      notes: json['notes'] as String? ?? '',
      products: (json['products'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? const [],
      microfinanceAmount: (json['microfinance_amount'] as num?)?.toDouble(),
      acceptanceDeviceCount: json['acceptance_device_count'] as int?,
      avgMonthlySales: (json['avg_monthly_sales'] as num?)?.toDouble(),
      businessAddress: json['business_address'] as String?,
      activityTypeId: json['activity_type_id'] as String?,
      activityTypeName: json['activity_type_name'] as String?,
      status: json['status'] as String? ?? 'lead',
      createdBy: json['created_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}
