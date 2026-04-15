class Merchant {
  // Step 1 - Identity
  final String? personalPhotoPath;
  final String? nationalIdFrontPath;
  final String? nationalIdBackPath;

  // Step 2 - Business Info
  final String merchantName;
  final String phoneNumber;
  final String businessType;
  final String address;
  final String region;
  final String postalCode;

  // Step 3 - Financial
  final String bankName;
  final String accountNumber;
  final String ibanNumber;

  // Metadata
  final String status;
  final String? submittedAt;

  const Merchant({
    this.personalPhotoPath,
    this.nationalIdFrontPath,
    this.nationalIdBackPath,
    required this.merchantName,
    required this.phoneNumber,
    required this.businessType,
    required this.address,
    required this.region,
    required this.postalCode,
    required this.bankName,
    required this.accountNumber,
    required this.ibanNumber,
    this.status = 'draft',
    this.submittedAt,
  });

  factory Merchant.empty() {
    return const Merchant(
      merchantName: '',
      phoneNumber: '',
      businessType: '',
      address: '',
      region: '',
      postalCode: '',
      bankName: '',
      accountNumber: '',
      ibanNumber: '',
    );
  }

  Merchant copyWith({
    String? personalPhotoPath,
    bool clearPersonalPhoto = false,
    String? nationalIdFrontPath,
    bool clearNationalIdFront = false,
    String? nationalIdBackPath,
    bool clearNationalIdBack = false,
    String? merchantName,
    String? phoneNumber,
    String? businessType,
    String? address,
    String? region,
    String? postalCode,
    String? bankName,
    String? accountNumber,
    String? ibanNumber,
    String? status,
    String? submittedAt,
  }) {
    return Merchant(
      personalPhotoPath: clearPersonalPhoto
          ? null
          : (personalPhotoPath ?? this.personalPhotoPath),
      nationalIdFrontPath: clearNationalIdFront
          ? null
          : (nationalIdFrontPath ?? this.nationalIdFrontPath),
      nationalIdBackPath: clearNationalIdBack
          ? null
          : (nationalIdBackPath ?? this.nationalIdBackPath),
      merchantName: merchantName ?? this.merchantName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      businessType: businessType ?? this.businessType,
      address: address ?? this.address,
      region: region ?? this.region,
      postalCode: postalCode ?? this.postalCode,
      bankName: bankName ?? this.bankName,
      accountNumber: accountNumber ?? this.accountNumber,
      ibanNumber: ibanNumber ?? this.ibanNumber,
      status: status ?? this.status,
      submittedAt: submittedAt ?? this.submittedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'personalPhotoPath': personalPhotoPath,
      'nationalIdFrontPath': nationalIdFrontPath,
      'nationalIdBackPath': nationalIdBackPath,
      'merchantName': merchantName,
      'phoneNumber': phoneNumber,
      'businessType': businessType,
      'address': address,
      'region': region,
      'postalCode': postalCode,
      'bankName': bankName,
      'accountNumber': accountNumber,
      'ibanNumber': ibanNumber,
      'status': status,
      'submittedAt': submittedAt,
    };
  }

  factory Merchant.fromJson(Map<String, dynamic> json) {
    return Merchant(
      personalPhotoPath: json['personalPhotoPath'] as String?,
      nationalIdFrontPath: json['nationalIdFrontPath'] as String?,
      nationalIdBackPath: json['nationalIdBackPath'] as String?,
      merchantName: json['merchantName'] as String,
      phoneNumber: json['phoneNumber'] as String,
      businessType: json['businessType'] as String,
      address: json['address'] as String,
      region: json['region'] as String,
      postalCode: json['postalCode'] as String,
      bankName: json['bankName'] as String,
      accountNumber: json['accountNumber'] as String,
      ibanNumber: json['ibanNumber'] as String,
      status: json['status'] as String? ?? 'draft',
      submittedAt: json['submittedAt'] as String?,
    );
  }
}
