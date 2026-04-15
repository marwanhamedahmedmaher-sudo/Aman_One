class User {
  final String name;
  final String phone;
  final String employeeId;
  final String businessUnit;
  final String region;

  const User({
    required this.name,
    required this.phone,
    required this.employeeId,
    required this.businessUnit,
    required this.region,
  });

  /// Get the first name for greeting
  String get firstName => name.split(' ').first;

  /// Create a copy with modified fields
  User copyWith({
    String? name,
    String? phone,
    String? employeeId,
    String? businessUnit,
    String? region,
  }) {
    return User(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      employeeId: employeeId ?? this.employeeId,
      businessUnit: businessUnit ?? this.businessUnit,
      region: region ?? this.region,
    );
  }

  /// Convert to Map (for future API integration)
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
      'employeeId': employeeId,
      'businessUnit': businessUnit,
      'region': region,
    };
  }

  /// Create from Map (for future API integration)
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      name: json['name'] as String,
      phone: json['phone'] as String,
      employeeId: json['employeeId'] as String,
      businessUnit: json['businessUnit'] as String,
      region: json['region'] as String,
    );
  }
}
