class User {
  final String? id;
  final String name;
  final String phone;
  final String employeeId;
  final String businessUnit;
  final String region;
  final String role;
  final String status;
  final bool mustChangePassword;

  const User({
    this.id,
    required this.name,
    required this.phone,
    required this.employeeId,
    this.businessUnit = '',
    this.region = '',
    this.role = 'sales_rep',
    this.status = 'active',
    this.mustChangePassword = false,
  });

  /// Get the first name for greeting
  String get firstName => name.split(' ').first;

  /// Create a copy with modified fields
  User copyWith({
    String? id,
    String? name,
    String? phone,
    String? employeeId,
    String? businessUnit,
    String? region,
    String? role,
    String? status,
    bool? mustChangePassword,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      employeeId: employeeId ?? this.employeeId,
      businessUnit: businessUnit ?? this.businessUnit,
      region: region ?? this.region,
      role: role ?? this.role,
      status: status ?? this.status,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    );
  }

  /// Convert to Map for Supabase
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'employee_id': employeeId,
      'business_unit': businessUnit,
      'region': region,
      'role': role,
      'status': status,
      'must_change_password': mustChangePassword,
    };
  }

  /// Create from Supabase row (snake_case keys)
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      employeeId: json['employee_id'] as String? ?? '',
      businessUnit: json['business_unit'] as String? ?? '',
      region: json['region'] as String? ?? '',
      role: json['role'] as String? ?? 'sales_rep',
      status: json['status'] as String? ?? 'active',
      mustChangePassword: json['must_change_password'] as bool? ?? false,
    );
  }
}
