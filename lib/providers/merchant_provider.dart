import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/merchant.dart';
import '../models/activity_type.dart';

class LeadProvider extends ChangeNotifier {
  Lead _lead = Lead.empty();
  bool _isSubmitting = false;
  String? _error;

  List<ActivityType> _activityTypes = [];
  bool _activityTypesLoaded = false;

  final _supabase = Supabase.instance.client;

  // Getters
  Lead get lead => _lead;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;
  List<ActivityType> get activityTypes => _activityTypes;

  /// Fetch activity types for dropdown (once per provider lifetime).
  Future<void> fetchActivityTypes() async {
    if (_activityTypesLoaded) return;
    try {
      final data = await _supabase
          .from('activity_types')
          .select('id, name, sort_order')
          .order('sort_order', ascending: true);
      _activityTypes = (data as List)
          .map((row) => ActivityType.fromJson(row as Map<String, dynamic>))
          .toList();
      _activityTypesLoaded = true;
      notifyListeners();
    } catch (_) {
      // Silently fail — dropdown will be empty, field is optional
    }
  }

  // Field setters
  void updateLead({
    String? name,
    String? phone,
    String? nationalId,
    String? notes,
    String? Function()? businessAddress,
  }) {
    _lead = _lead.copyWith(
      name: name,
      phone: phone,
      nationalId: nationalId,
      notes: notes,
      businessAddress: businessAddress,
    );
    _error = null;
    notifyListeners();
  }

  void toggleProduct(String product) {
    final current = List<String>.from(_lead.products);
    if (current.contains(product)) {
      current.remove(product);
      // Clear product-specific detail when deselected
      if (product == 'Microfinance') {
        _lead = _lead.copyWith(
          products: current,
          microfinanceAmount: () => null,
        );
      } else if (product == 'Acceptance POS') {
        _lead = _lead.copyWith(
          products: current,
          acceptanceDeviceCount: () => null,
        );
      } else {
        _lead = _lead.copyWith(products: current);
      }
    } else {
      current.add(product);
      _lead = _lead.copyWith(products: current);
    }
    _error = null;
    notifyListeners();
  }

  void updateProductDetails({
    double? microfinanceAmount,
    int? acceptanceDeviceCount,
  }) {
    _lead = _lead.copyWith(
      microfinanceAmount: microfinanceAmount != null
          ? () => microfinanceAmount
          : null,
      acceptanceDeviceCount: acceptanceDeviceCount != null
          ? () => acceptanceDeviceCount
          : null,
    );
    _error = null;
    notifyListeners();
  }

  void updateLeadDetails({
    double? Function()? avgMonthlySales,
    String? Function()? activityTypeId,
    String? Function()? activityTypeName,
  }) {
    _lead = _lead.copyWith(
      avgMonthlySales: avgMonthlySales,
      activityTypeId: activityTypeId,
      activityTypeName: activityTypeName,
    );
    _error = null;
    notifyListeners();
  }

  // Validation
  bool get isValid =>
      _lead.name.length >= 2 &&
      _lead.phone.length == 11 &&
      _lead.phone.startsWith('01') &&
      _lead.nationalId.length == 14 &&
      RegExp(r'^\d{14}$').hasMatch(_lead.nationalId) &&
      _lead.products.isNotEmpty &&
      (!_lead.products.contains('Microfinance') ||
          (_lead.microfinanceAmount != null && _lead.microfinanceAmount! > 0)) &&
      (!_lead.products.contains('Acceptance POS') ||
          (_lead.acceptanceDeviceCount != null && _lead.acceptanceDeviceCount! >= 1));

  /// Returns an Arabic error for the first invalid field, or null if all valid.
  String? validate() {
    if (_lead.name.length < 2) {
      return '\u0627\u062f\u062e\u0644 \u0627\u0633\u0645 \u0627\u0644\u062a\u0627\u062c\u0631 (\u062d\u0631\u0641\u064a\u0646 \u0639\u0644\u0649 \u0627\u0644\u0623\u0642\u0644)'; // ادخل اسم التاجر (حرفين على الأقل)
    }
    if (_lead.phone.isEmpty || !_lead.phone.startsWith('01') || _lead.phone.length != 11) {
      return '\u0631\u0642\u0645 \u0627\u0644\u0645\u0648\u0628\u0627\u064a\u0644 \u063a\u064a\u0631 \u0635\u062d\u064a\u062d'; // رقم الموبايل غير صحيح
    }
    if (_lead.nationalId.length != 14 || !RegExp(r'^\d{14}$').hasMatch(_lead.nationalId)) {
      return '\u0627\u0644\u0631\u0642\u0645 \u0627\u0644\u0642\u0648\u0645\u064a \u064a\u062c\u0628 \u0623\u0646 \u064a\u0643\u0648\u0646 \u0661\u0664 \u0631\u0642\u0645'; // الرقم القومي يجب أن يكون ١٤ رقم
    }
    if (_lead.products.isEmpty) {
      return '\u0627\u062e\u062a\u0631 \u0645\u0646\u062a\u062c \u0648\u0627\u062d\u062f \u0639\u0644\u0649 \u0627\u0644\u0623\u0642\u0644'; // اختر منتج واحد على الأقل
    }
    if (_lead.products.contains('Microfinance') &&
        (_lead.microfinanceAmount == null || _lead.microfinanceAmount! <= 0)) {
      return '\u0627\u062f\u062e\u0644 \u0627\u0644\u0645\u0628\u0644\u063a \u0644\u0644\u062a\u0645\u0648\u064a\u0644 \u0627\u0644\u0623\u0635\u063a\u0631'; // ادخل المبلغ للتمويل الأصغر
    }
    if (_lead.products.contains('Acceptance POS') &&
        (_lead.acceptanceDeviceCount == null || _lead.acceptanceDeviceCount! < 1)) {
      return '\u0627\u062f\u062e\u0644 \u0639\u062f\u062f \u0627\u0644\u0623\u062c\u0647\u0632\u0629'; // ادخل عدد الأجهزة
    }
    return null;
  }

  void setError(String message) {
    _error = message;
    notifyListeners();
  }

  // Submit to Supabase — returns created merchant ID on success, null on failure.
  Future<String?> submit() async {
    if (!isValid) return null;

    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      final userId = _supabase.auth.currentUser?.id;
      final payload = _lead.copyWith(createdBy: userId).toJson();
      final response = await _supabase
          .from('merchants')
          .insert(payload)
          .select('id')
          .single();

      _isSubmitting = false;
      notifyListeners();
      return response['id'] as String?;
    } on PostgrestException catch (e) {
      _isSubmitting = false;

      // Handle specific Postgres errors
      if (e.code == '23505') {
        // Unique constraint violation (duplicate national_id_hash)
        _error = '\u0647\u0630\u0627 \u0627\u0644\u0631\u0642\u0645 \u0627\u0644\u0642\u0648\u0645\u064a \u0645\u0633\u062c\u0644 \u0628\u0627\u0644\u0641\u0639\u0644';
      } else if (e.message.contains('\u0631\u0642\u0645 \u0627\u0644\u0645\u0648\u0628\u0627\u064a\u0644 \u063a\u064a\u0631 \u0635\u062d\u064a\u062d')) {
        _error = '\u0631\u0642\u0645 \u0627\u0644\u0645\u0648\u0628\u0627\u064a\u0644 \u063a\u064a\u0631 \u0635\u062d\u064a\u062d';
      } else if (e.message.contains('\u0631\u0642\u0645 \u0627\u0644\u0642\u0648\u0645\u064a \u063a\u064a\u0631 \u0635\u062d\u064a\u062d')) {
        _error = '\u0627\u0644\u0631\u0642\u0645 \u0627\u0644\u0642\u0648\u0645\u064a \u063a\u064a\u0631 \u0635\u062d\u064a\u062d';
      } else {
        _error = '\u062d\u062f\u062b \u062e\u0637\u0623 \u0623\u062b\u0646\u0627\u0621 \u0627\u0644\u062a\u0633\u062c\u064a\u0644';
      }

      notifyListeners();
      return null;
    } catch (e) {
      _isSubmitting = false;
      _error = '\u062d\u062f\u062b \u062e\u0637\u0623 \u063a\u064a\u0631 \u0645\u062a\u0648\u0642\u0639';
      notifyListeners();
      return null;
    }
  }

  // Reset form
  void reset() {
    _lead = Lead.empty();
    _isSubmitting = false;
    _error = null;
    notifyListeners();
  }
}
