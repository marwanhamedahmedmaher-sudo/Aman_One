import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/task_assignment.dart';

class TasksProvider extends ChangeNotifier {
  final _supabase = Supabase.instance.client;

  List<TaskAssignment> _tasks = [];
  bool _isLoading = false;
  String? _error;
  String? _cachedDate; // Cairo-date string (YYYY-MM-DD) for which tasks are cached
  String? _cachedUid; // which rep the cache belongs to (guards account switch)
  int _refillCount = 0; // refills used today (max 3)

  List<TaskAssignment> get tasks => _tasks;
  int get pendingCount => _tasks.where((t) => t.isPending).length;
  int get completedCount => _tasks.where((t) => t.isCompleted).length;
  int get totalCount => _tasks.length;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Current date in Cairo time (UTC+2). Egypt does not observe DST.
  static String _cairoToday() {
    final cairo = DateTime.now().toUtc().add(const Duration(hours: 2));
    return cairo.toIso8601String().substring(0, 10);
  }

  /// Load tasks once per Cairo day. Returns cached data on subsequent calls.
  Future<void> loadTodaysTasks() async {
    final today = _cairoToday();
    final uid = _supabase.auth.currentUser?.id;

    // Cache hit — same rep AND same Cairo day, already loaded
    if (_cachedUid == uid && _cachedDate == today && _tasks.isNotEmpty) {
      return;
    }

    // Different rep or new day — clear stale cache + reset refill counter
    if (_cachedUid != uid || _cachedDate != today) {
      _tasks = [];
      _cachedDate = null;
      _cachedUid = null;
      _refillCount = 0;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Trigger distribution RPC (idempotent, race-safe, Cairo-aware on DB side)
      await _supabase.rpc('distribute_daily_tasks');

      // Fetch today's assignments with joined pool data
      final data = await _supabase
          .from('task_assignments')
          .select('*, cross_sell_pool(*)')
          .eq('assigned_date', today)
          .order('status', ascending: true)
          .order('created_at', ascending: true);

      _tasks = (data as List)
          .map((row) => TaskAssignment.fromJson(row as Map<String, dynamic>))
          .toList();
      _cachedDate = today;
      _cachedUid = uid;
    } catch (e) {
      _error = '\u062d\u062f\u062b \u062e\u0637\u0623 \u0623\u062b\u0646\u0627\u0621 \u062a\u062d\u0645\u064a\u0644 \u0627\u0644\u0645\u0647\u0627\u0645'; // حدث خطأ أثناء تحميل المهام
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Drop cached tasks. Call on logout so the next rep starts clean instead of
  /// seeing the previous rep's cached assignments.
  void reset() {
    _tasks = [];
    _cachedDate = null;
    _cachedUid = null;
    _refillCount = 0;
    _error = null;
    notifyListeners();
  }

  /// Mark task as completed, optionally linking to converted merchant.
  Future<bool> completeTask(String taskId,
      {String? notes, String? merchantId}) async {
    try {
      final update = <String, dynamic>{
        'status': 'completed',
        'outcome_notes': notes ?? '',
      };
      if (merchantId != null) {
        update['converted_merchant_id'] = merchantId;
      }
      await _supabase
          .from('task_assignments')
          .update(update)
          .eq('id', taskId);

      _tasks = _tasks.map((t) {
        if (t.id == taskId) {
          return t.copyWith(
            status: 'completed',
            outcomeNotes: notes,
            convertedMerchantId: merchantId,
          );
        }
        return t;
      }).toList();
      notifyListeners();
      await _refillIfEmpty();
      return true;
    } catch (_) {
      _error = '\u062d\u062f\u062b \u062e\u0637\u0623 \u0623\u062b\u0646\u0627\u0621 \u062a\u062d\u062f\u064a\u062b \u0627\u0644\u0645\u0647\u0645\u0629'; // حدث خطأ أثناء تحديث المهمة
      notifyListeners();
      return false;
    }
  }

  /// Skip a task with optional reason.
  Future<bool> skipTask(String taskId, {String? reason}) async {
    try {
      await _supabase
          .from('task_assignments')
          .update({
            'status': 'skipped',
            'outcome_notes': reason ?? '',
          })
          .eq('id', taskId);

      _tasks = _tasks.map((t) {
        if (t.id == taskId) {
          return t.copyWith(status: 'skipped', outcomeNotes: reason);
        }
        return t;
      }).toList();
      notifyListeners();
      await _refillIfEmpty();
      return true;
    } catch (_) {
      _error = '\u062d\u062f\u062b \u062e\u0637\u0623 \u0623\u062b\u0646\u0627\u0621 \u062a\u062e\u0637\u064a \u0627\u0644\u0645\u0647\u0645\u0629'; // حدث خطأ أثناء تخطي المهمة
      notifyListeners();
      return false;
    }
  }

  /// When pending hits 0, call refill RPC and re-fetch new tasks. Max 3 per day.
  Future<void> _refillIfEmpty() async {
    if (pendingCount > 0 || _refillCount >= 3) return;

    try {
      await _supabase.rpc('refill_rep_tasks');
      _refillCount++;

      // Re-fetch to pick up newly assigned tasks
      final today = _cairoToday();
      final data = await _supabase
          .from('task_assignments')
          .select('*, cross_sell_pool(*)')
          .eq('assigned_date', today)
          .order('status', ascending: true)
          .order('created_at', ascending: true);

      _tasks = (data as List)
          .map((row) => TaskAssignment.fromJson(row as Map<String, dynamic>))
          .toList();
      _cachedDate = today;
      notifyListeners();
    } catch (_) {
      // Refill failed silently — rep just sees completed list
    }
  }
}
