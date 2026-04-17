import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/merchant.dart';

class MerchantListProvider extends ChangeNotifier {
  final _supabase = Supabase.instance.client;

  List<Lead> _merchants = [];
  int _weeklyCount = 0;
  bool _isLoading = false;
  String? _error;

  List<Lead> get merchants => _merchants;
  int get weeklyCount => _weeklyCount;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Fetch all merchants created by the current rep (RLS-enforced).
  /// Excludes national_id — plaintext NID only via reveal RPC.
  Future<void> fetchMerchants() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await _supabase
          .from('merchants')
          .select('id, name, phone, notes, products, microfinance_amount, acceptance_device_count, avg_monthly_sales, business_address, activity_type_id, activity_types(name), status, created_by, created_at')
          .order('created_at', ascending: false);

      _merchants = (data as List).map((row) {
        final map = Map<String, dynamic>.from(row as Map<String, dynamic>);
        // Flatten Supabase foreign-table embed: activity_types(name) → activity_type_name
        final activityTypes = map.remove('activity_types');
        if (activityTypes is Map) {
          map['activity_type_name'] = activityTypes['name'];
        }
        return Lead.fromJson(map);
      }).toList();
    } catch (e) {
      _error = 'حدث خطأ أثناء تحميل العملاء';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Count merchants created this week (for home dashboard card).
  Future<void> fetchWeeklyCount() async {
    try {
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday % 7));
      final startOfWeek = DateTime(weekStart.year, weekStart.month, weekStart.day);

      final data = await _supabase
          .from('merchants')
          .select('id')
          .gte('created_at', startOfWeek.toIso8601String());

      _weeklyCount = (data as List).length;
      notifyListeners();
    } catch (_) {
      // Silently fail — dashboard shows 0
    }
  }

  /// Reveal plaintext NID via SECURITY DEFINER RPC. Returns NID or null.
  Future<String?> revealNationalId(String merchantId) async {
    try {
      final result = await _supabase.rpc(
        'reveal_national_id',
        params: {'p_merchant_id': merchantId},
      );
      return result as String?;
    } on PostgrestException catch (e) {
      _error = e.message;
      notifyListeners();
      return null;
    } catch (_) {
      _error = 'حدث خطأ أثناء عرض الرقم القومي';
      notifyListeners();
      return null;
    }
  }
}
