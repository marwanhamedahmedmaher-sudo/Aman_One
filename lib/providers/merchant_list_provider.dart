import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/merchant.dart';
import '../services/analytics.dart';

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
      List<dynamic> data;
      try {
        data = await _supabase
            .from('merchants')
            .select('id, name, phone, id_document_type, notes, products, microfinance_amount, acceptance_device_count, avg_monthly_sales, business_address, activity_type_id, activity_types(name), status, created_by, created_at')
            .order('created_at', ascending: false);
      } on PostgrestException catch (e) {
        // Pre-migration-018 DB: id_document_type doesn't exist yet. The insert
        // path degrades gracefully for this case (see the wizard's
        // _isUndefinedColumn retry) — the read path must too, or reps create
        // merchants they can never list.
        if (e.code != '42703' &&
            e.code != 'PGRST204' &&
            !e.message.contains('id_document_type')) {
          rethrow;
        }
        data = await _supabase
            .from('merchants')
            .select('id, name, phone, notes, products, microfinance_amount, acceptance_device_count, avg_monthly_sales, business_address, activity_type_id, activity_types(name), status, created_by, created_at')
            .order('created_at', ascending: false);
      }

      _merchants = data.map((row) {
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
  Future<String?> revealNationalId(String merchantId) => _revealWithAudit(
        merchantId,
        rpcName: 'reveal_national_id',
        successEvent: 'nid_revealed',
        failEvent: 'nid_reveal_failed',
        fallbackError: 'حدث خطأ أثناء عرض الرقم القومي',
      );

  /// Reveal a foreigner's plaintext passport via SECURITY DEFINER RPC
  /// (migration 019). Returns passport or null.
  Future<String?> revealPassportNumber(String merchantId) => _revealWithAudit(
        merchantId,
        rpcName: 'reveal_passport_number',
        successEvent: 'passport_revealed',
        failEvent: 'passport_reveal_failed',
        fallbackError: 'حدث خطأ أثناء عرض جواز السفر',
      );

  /// Shared reveal-with-audit call: one place for the RPC/error/analytics
  /// shape so the NID and passport paths cannot drift apart.
  Future<String?> _revealWithAudit(
    String merchantId, {
    required String rpcName,
    required String successEvent,
    required String failEvent,
    required String fallbackError,
  }) async {
    try {
      final result = await _supabase.rpc(
        rpcName,
        params: {'p_merchant_id': merchantId},
      );
      await Analytics.track(successEvent, properties: {
        'merchant_id': merchantId,
      });
      return result as String?;
    } on PostgrestException catch (e) {
      _error = e.message;
      notifyListeners();
      await Analytics.track(failEvent, properties: {
        'merchant_id': merchantId,
        'pg_code': e.code,
      });
      return null;
    } catch (_) {
      _error = fallbackError;
      notifyListeners();
      await Analytics.track(failEvent, properties: {
        'merchant_id': merchantId,
        'pg_code': null,
      });
      return null;
    }
  }
}
