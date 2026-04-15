import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/merchant.dart';

class LeadProvider extends ChangeNotifier {
  Lead _lead = Lead.empty();
  bool _isSubmitting = false;
  String? _error;

  final _supabase = Supabase.instance.client;

  // Getters
  Lead get lead => _lead;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;

  // Field setters
  void updateLead({
    String? name,
    String? phone,
    String? nationalId,
    String? notes,
  }) {
    _lead = _lead.copyWith(
      name: name,
      phone: phone,
      nationalId: nationalId,
      notes: notes,
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
      RegExp(r'^\d{14}$').hasMatch(_lead.nationalId);

  // Submit to Supabase
  Future<bool> submit() async {
    if (!isValid) return false;

    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      await _supabase.from('merchants').insert(_lead.toJson());

      _isSubmitting = false;
      notifyListeners();
      return true;
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
      return false;
    } catch (e) {
      _isSubmitting = false;
      _error = '\u062d\u062f\u062b \u062e\u0637\u0623 \u063a\u064a\u0631 \u0645\u062a\u0648\u0642\u0639';
      notifyListeners();
      return false;
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
