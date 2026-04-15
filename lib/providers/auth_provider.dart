import 'package:flutter/foundation.dart';
import '../models/user.dart';

class AuthProvider extends ChangeNotifier {
  bool _isAuthenticated = false;
  String _currentPhone = '';
  User? _user;

  // --- Mock Data (replace with API calls later) ---
  static const _mockOtp = '123456';

  static const _mockUsers = {
    '01012345678': User(
      name: 'فاطمة حسن',
      phone: '01012345678',
      employeeId: 'EMP-2847',
      businessUnit: 'التمويل الرقمي',
      region: 'القاهرة',
    ),
  };

  static const _defaultNewUser = User(
    name: 'أحمد محمود حسن',
    phone: '',
    employeeId: 'EMP-1234',
    businessUnit: 'التمويل الرقمي',
    region: 'القاهرة',
  );
  // --- End Mock Data ---

  // Getters
  bool get isAuthenticated => _isAuthenticated;
  String get currentPhone => _currentPhone;
  User? get user => _user;

  /// Set the current phone number being used for auth
  void setPhone(String phone) {
    _currentPhone = phone.replaceAll(RegExp(r'\s'), '');
    notifyListeners();
  }

  /// Check if the phone belongs to an existing user
  /// Returns: { isFirstTime: bool, user: User? }
  ({bool isFirstTime, User? user}) checkPhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'\s'), '');
    final mockUser = _mockUsers[cleaned];

    if (mockUser != null) {
      _user = mockUser;
      notifyListeners();
      return (isFirstTime: false, user: mockUser);
    }

    return (isFirstTime: true, user: null);
  }

  /// Verify OTP code
  bool verifyOtp(String otp) {
    // TODO: Replace with API call
    return otp == _mockOtp;
  }

  /// Log the user in
  void login({User? userData}) {
    if (userData != null) {
      _user = userData;
    } else if (_user == null) {
      _user = _defaultNewUser.copyWith(phone: _currentPhone);
    }
    _isAuthenticated = true;
    notifyListeners();
  }

  /// Log out
  void logout() {
    _isAuthenticated = false;
    _user = null;
    _currentPhone = '';
    notifyListeners();
  }
}
