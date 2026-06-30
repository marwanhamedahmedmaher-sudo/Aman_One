import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/aman_branch.dart';
import '../models/governorate.dart';

/// Loads + caches the dropdown lookups used by the field-visit form:
/// governorates (missions 1 & 2) and active Aman branches (mission 3).
/// Loaded once and reused — both are small, admin-managed, rarely changing.
class LookupsProvider extends ChangeNotifier {
  final _supabase = Supabase.instance.client;

  List<Governorate> _governorates = [];
  List<AmanBranch> _branches = [];
  bool _loaded = false;
  bool _isLoading = false;

  List<Governorate> get governorates => _governorates;
  List<AmanBranch> get branches => _branches;
  bool get isLoading => _isLoading;
  bool get loaded => _loaded;

  Future<void> ensureLoaded() async {
    if (_loaded || _isLoading) return;
    _isLoading = true;
    notifyListeners();

    try {
      final govData = await _supabase
          .from('governorates')
          .select('id, name_ar')
          .order('sort_order', ascending: true);
      _governorates = (govData as List)
          .map((r) => Governorate.fromJson(r as Map<String, dynamic>))
          .toList();

      final branchData = await _supabase
          .from('aman_branches')
          .select('id, name_ar, governorate_id')
          .eq('active', true)
          .order('sort_order', ascending: true)
          .order('name_ar', ascending: true);
      _branches = (branchData as List)
          .map((r) => AmanBranch.fromJson(r as Map<String, dynamic>))
          .toList();

      _loaded = true;
    } catch (_) {
      // Leave caches empty; dropdowns show their empty state. The form blocks
      // submit on required dropdowns, so no bad data results.
    }

    _isLoading = false;
    notifyListeners();
  }
}
