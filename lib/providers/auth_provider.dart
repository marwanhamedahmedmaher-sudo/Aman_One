import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart' as app;

class AuthResult {
  final bool success;
  final bool mustChangePassword;
  final String? error;

  const AuthResult({
    required this.success,
    this.mustChangePassword = false,
    this.error,
  });
}

class AuthProvider extends ChangeNotifier {
  bool _isAuthenticated = false;
  String _currentPhone = '';
  app.User? _user;
  bool _loading = false;

  final _supabase = Supabase.instance.client;
  final _secureStorage = const FlutterSecureStorage();
  final _localAuth = LocalAuthentication();

  // Getters
  bool get isAuthenticated => _isAuthenticated;
  String get currentPhone => _currentPhone;
  app.User? get user => _user;
  bool get loading => _loading;

  void setPhone(String phone) {
    _currentPhone = phone.replaceAll(RegExp(r'\s'), '');
    notifyListeners();
  }

  /// Convert local phone to E.164 for Supabase auth
  String _toE164(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.startsWith('0')) {
      return '+2$digits'; // 01012345678 -> +201012345678
    }
    if (digits.startsWith('20')) {
      return '+$digits';
    }
    return '+2$digits'; // fallback
  }

  /// Sign in with phone + password via Supabase
  Future<AuthResult> signIn(String phone, String password) async {
    _loading = true;
    notifyListeners();

    try {
      final e164 = _toE164(phone);
      final response = await _supabase.auth.signInWithPassword(
        phone: e164,
        password: password,
      );

      if (response.user == null) {
        _loading = false;
        notifyListeners();
        return const AuthResult(
            success: false, error: '\u0641\u0634\u0644 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644');
      }

      // Load user profile from public.users table
      _user = await _loadProfile(response.user!.id);

      // Check must_change_password from profile
      final mustChange = _user?.mustChangePassword ?? false;

      if (!mustChange) {
        _isAuthenticated = true;
      }

      _loading = false;
      notifyListeners();

      return AuthResult(
        success: true,
        mustChangePassword: mustChange,
      );
    } on AuthException catch (e) {
      _loading = false;
      notifyListeners();
      return AuthResult(success: false, error: e.message);
    } catch (e) {
      _loading = false;
      notifyListeners();
      return AuthResult(
          success: false,
          error:
              '\u062d\u062f\u062b \u062e\u0637\u0623 \u063a\u064a\u0631 \u0645\u062a\u0648\u0642\u0639');
    }
  }

  /// Load user profile from public.users table
  Future<app.User?> _loadProfile(String uid) async {
    try {
      final data =
          await _supabase.from('users').select().eq('id', uid).single();
      return app.User.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  /// Change password (for first-login rotation or voluntary change)
  Future<AuthResult> changePassword(String newPassword) async {
    _loading = true;
    notifyListeners();

    try {
      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      // Clear must_change_password flag in profile
      final uid = _supabase.auth.currentUser?.id;
      if (uid != null) {
        await _supabase
            .from('users')
            .update({'must_change_password': false}).eq('id', uid);

        _user = _user?.copyWith(mustChangePassword: false);
      }

      _isAuthenticated = true;
      _loading = false;
      notifyListeners();

      return const AuthResult(success: true);
    } catch (e) {
      _loading = false;
      notifyListeners();
      return AuthResult(
          success: false,
          error:
              '\u0641\u0634\u0644 \u062a\u063a\u064a\u064a\u0631 \u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631');
    }
  }

  /// Check if biometric auth is available and credentials are stored
  Future<bool> canUseBiometric() async {
    try {
      final available = await _localAuth.canCheckBiometrics;
      final hasCredentials =
          await _secureStorage.read(key: 'bio_phone') != null;
      return available && hasCredentials;
    } catch (_) {
      return false;
    }
  }

  /// Check if biometric hardware is supported on the device
  Future<bool> isBiometricAvailable() async {
    try {
      return await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Store credentials for biometric login
  Future<void> enableBiometric(String phone, String password) async {
    await _secureStorage.write(key: 'bio_phone', value: phone);
    await _secureStorage.write(key: 'bio_password', value: password);
  }

  /// Sign in using biometric authentication
  Future<AuthResult> signInWithBiometric() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason:
            '\u0633\u062c\u0644 \u0627\u0644\u062f\u062e\u0648\u0644 \u0628\u0627\u0633\u062a\u062e\u062f\u0627\u0645 \u0627\u0644\u0628\u0635\u0645\u0629',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (!authenticated) {
        return const AuthResult(
            success: false,
            error:
                '\u0641\u0634\u0644 \u0627\u0644\u062a\u062d\u0642\u0642 \u0628\u0627\u0644\u0628\u0635\u0645\u0629');
      }

      final phone = await _secureStorage.read(key: 'bio_phone');
      final password = await _secureStorage.read(key: 'bio_password');

      if (phone == null || password == null) {
        return const AuthResult(
            success: false,
            error:
                '\u0644\u0645 \u064a\u062a\u0645 \u0627\u0644\u0639\u062b\u0648\u0631 \u0639\u0644\u0649 \u0628\u064a\u0627\u0646\u0627\u062a \u0627\u0644\u062f\u062e\u0648\u0644');
      }

      return signIn(phone, password);
    } catch (_) {
      return const AuthResult(
          success: false,
          error:
              '\u0627\u0644\u0628\u0635\u0645\u0629 \u063a\u064a\u0631 \u0645\u062a\u0627\u062d\u0629');
    }
  }

  /// Clear biometric credentials
  Future<void> disableBiometric() async {
    await _secureStorage.delete(key: 'bio_phone');
    await _secureStorage.delete(key: 'bio_password');
  }

  /// Complete authentication (called after password change if needed)
  void completeAuth() {
    _isAuthenticated = true;
    notifyListeners();
  }

  /// Sign out
  Future<void> logout() async {
    await _supabase.auth.signOut();
    _isAuthenticated = false;
    _user = null;
    _currentPhone = '';
    notifyListeners();
  }
}
