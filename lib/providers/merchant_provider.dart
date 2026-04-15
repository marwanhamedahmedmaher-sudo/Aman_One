import 'package:flutter/foundation.dart';
import '../models/merchant.dart';

class MerchantProvider extends ChangeNotifier {
  int _currentStep = 0;
  Merchant _merchant = Merchant.empty();
  bool _isSubmitting = false;

  // Dropdown data
  static const List<String> businessTypes = [
    'بقالة',
    'صيدلية',
    'مطعم',
    'ملابس',
    'إلكترونيات',
    'مستلزمات منزلية',
    'أخرى',
  ];

  static const List<String> regions = [
    'القاهرة',
    'الجيزة',
    'الإسكندرية',
    'المنصورة',
    'الشرقية',
    'أسيوط',
    'الأقصر',
    'أسوان',
  ];

  static const List<String> bankNames = [
    'البنك الأهلي المصري',
    'بنك مصر',
    'بنك القاهرة',
    'البنك التجاري الدولي',
    'بنك الإسكندرية',
    'بنك QNB الأهلي',
  ];

  // Getters
  int get currentStep => _currentStep;
  Merchant get merchant => _merchant;
  bool get isSubmitting => _isSubmitting;

  // Step navigation
  void nextStep() {
    if (_currentStep < 2) {
      _currentStep++;
      notifyListeners();
    }
  }

  void previousStep() {
    if (_currentStep > 0) {
      _currentStep--;
      notifyListeners();
    }
  }

  // Step 1 - Identity setters
  void setPersonalPhoto(String path) {
    _merchant = _merchant.copyWith(personalPhotoPath: path);
    notifyListeners();
  }

  void setNationalIdFront(String path) {
    _merchant = _merchant.copyWith(nationalIdFrontPath: path);
    notifyListeners();
  }

  void setNationalIdBack(String path) {
    _merchant = _merchant.copyWith(nationalIdBackPath: path);
    notifyListeners();
  }

  // Step 2 - Business info
  void updateBusinessInfo({
    String? merchantName,
    String? phoneNumber,
    String? businessType,
    String? address,
    String? region,
    String? postalCode,
  }) {
    _merchant = _merchant.copyWith(
      merchantName: merchantName,
      phoneNumber: phoneNumber,
      businessType: businessType,
      address: address,
      region: region,
      postalCode: postalCode,
    );
    notifyListeners();
  }

  // Step 3 - Financial info
  void updateFinancialInfo({
    String? bankName,
    String? accountNumber,
    String? ibanNumber,
  }) {
    _merchant = _merchant.copyWith(
      bankName: bankName,
      accountNumber: accountNumber,
      ibanNumber: ibanNumber,
    );
    notifyListeners();
  }

  // Validation
  bool get isStep1Valid =>
      _merchant.personalPhotoPath != null &&
      _merchant.nationalIdFrontPath != null &&
      _merchant.nationalIdBackPath != null;

  bool get isStep2Valid =>
      _merchant.merchantName.length >= 3 &&
      _merchant.phoneNumber.length >= 10 &&
      _merchant.businessType.isNotEmpty &&
      _merchant.address.length >= 5 &&
      _merchant.region.isNotEmpty;

  bool get isStep3Valid =>
      _merchant.bankName.isNotEmpty &&
      _merchant.accountNumber.length >= 10 &&
      _merchant.ibanNumber.length == 29 &&
      _merchant.ibanNumber.startsWith('EG');

  // Submit
  Future<bool> submitRegistration() async {
    _isSubmitting = true;
    notifyListeners();

    // TODO: Replace with actual API call
    await Future.delayed(const Duration(seconds: 2));

    _merchant = _merchant.copyWith(
      status: 'submitted',
      submittedAt: DateTime.now().toIso8601String(),
    );

    _isSubmitting = false;
    notifyListeners();
    return true;
  }

  // Reset
  void reset() {
    _currentStep = 0;
    _merchant = Merchant.empty();
    _isSubmitting = false;
    notifyListeners();
  }
}
