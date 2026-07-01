import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/field_task.dart';
import '../models/task_visit.dart';
import '../services/analytics.dart';

/// Outcome of logging a visit, so the UI can show the right message.
class VisitOutcome {
  final bool success;
  final bool inWindow;
  final String? error;
  const VisitOutcome({required this.success, this.inWindow = false, this.error});
}

/// Drives the unified daily field-visit schedule. Each of the 3 daily tasks is
/// an entry point to a multi-visit log: the rep opens a task, taps "أدخل زيارة"
/// and fills a per-mission form (GPS + photo + counts + notes), then explicitly
/// marks the task done.
class FieldTasksProvider extends ChangeNotifier {
  final _supabase = Supabase.instance.client;

  List<FieldTask> _tasks = [];
  final Map<String, int> _visitCounts = {}; // task_id -> number of logged visits
  bool _isLoading = false;
  bool _locationConsent = false;
  String? _error;
  String? _cachedDate;
  String? _cachedUid; // which rep the cache belongs to (guards account switch)
  final Set<String> _busy = {}; // task ids with an in-flight write

  List<FieldTask> get tasks => _tasks;
  bool get isLoading => _isLoading;
  bool get locationConsent => _locationConsent;
  String? get error => _error;
  int visitCount(String taskId) => _visitCounts[taskId] ?? 0;
  bool isBusy(String taskId) => _busy.contains(taskId);

  /// Current date in Cairo time (UTC+2; Egypt has no DST).
  static String _cairoToday() {
    final cairo = DateTime.now().toUtc().add(const Duration(hours: 2));
    return cairo.toIso8601String().substring(0, 10);
  }

  /// Load today's field tasks for the current rep. Generates them via the
  /// idempotent RPC first, then fetches each task with its visit count.
  Future<void> loadTodaysTasks() async {
    final today = _cairoToday();
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    // Cache is valid only for the SAME rep on the SAME Cairo day. Keying on the
    // date alone leaked the previous rep's tasks after an in-session account
    // switch (this provider is app-scoped and survives logout).
    if (_cachedUid == uid && _cachedDate == today && _tasks.isNotEmpty) return;
    if (_cachedUid != uid || _cachedDate != today) {
      _tasks = [];
      _visitCounts.clear();
      _cachedDate = null;
      _cachedUid = null;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _loadConsent();

      // Idempotent: creates today's 3 tasks for this rep if missing.
      // No-ops server-side for anyone who isn't an active sales rep.
      await _supabase.rpc('ensure_my_field_tasks');

      // Scope to the caller's own tasks. RLS already enforces this for reps;
      // the explicit filter also hides other reps' rows from supervisor/admin
      // accounts that happen to open the app (their RLS read is broader).
      final data = await _supabase
          .from('field_tasks')
          .select('*, task_templates(slug), task_visits(count)')
          .eq('assigned_to', uid)
          .eq('task_date', today)
          .order('window_start', ascending: true);

      _tasks = [];
      _visitCounts.clear();
      for (final row in (data as List)) {
        final map = row as Map<String, dynamic>;
        final task = FieldTask.fromJson(map);
        _tasks.add(task);
        _visitCounts[task.id] = _extractCount(map['task_visits']);
      }
      _cachedDate = today;
      _cachedUid = uid;
    } catch (_) {
      _error = 'حدث خطأ أثناء تحميل مهام اليوم';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Drop all cached state. Call on logout so the next rep to sign in on the
  /// same device and day loads their own tasks instead of the previous rep's.
  /// Safe to call anytime: visits are persisted server-side the moment they're
  /// logged (awaited RPC), never buffered here — this only clears a read copy.
  void reset() {
    _tasks = [];
    _visitCounts.clear();
    _cachedDate = null;
    _cachedUid = null;
    _locationConsent = false;
    _error = null;
    _busy.clear();
    notifyListeners();
  }

  /// PostgREST returns an aggregate embed as `[{count: n}]`.
  static int _extractCount(dynamic raw) {
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return (raw.first['count'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  Future<void> _loadConsent() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await _supabase
          .from('users')
          .select('location_consent')
          .eq('id', uid)
          .single();
      _locationConsent = row['location_consent'] as bool? ?? false;
    } catch (_) {
      // Leave consent as-is; the RPC still enforces it server-side.
    }
  }

  /// Record the rep's one-time opt-in to location capture.
  Future<bool> grantConsent() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      await _supabase
          .from('users')
          .update({'location_consent': true})
          .eq('id', uid);
      _locationConsent = true;
      notifyListeners();
      await Analytics.track('location_consent_granted');
      return true;
    } catch (_) {
      _error = 'تعذّر حفظ الموافقة. برجاء المحاولة مرة أخرى.';
      notifyListeners();
      return false;
    }
  }

  /// Fetch the logged visits for one task (newest first), with joined
  /// governorate + branch names for display.
  Future<List<TaskVisit>> fetchVisits(String taskId) async {
    final data = await _supabase
        .from('task_visits')
        .select('*, governorates(name_ar), aman_branches(name_ar)')
        .eq('task_id', taskId)
        .order('recorded_at', ascending: false);
    return (data as List)
        .map((r) => TaskVisit.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Log one visit via the record_task_visit RPC. The caller has already
  /// captured the GPS fix and uploaded the photo (passing [photoPath]).
  Future<VisitOutcome> addVisit({
    required String taskId,
    required double lat,
    required double lng,
    double? accuracyM,
    required DateTime recordedAt,
    required String photoPath,
    required int contactedCount,
    required int onboardedCount,
    int? governorateId,
    String notes = '',
    String? placeKind,
    String? placeName,
    List<String>? products,
    String? merchantName,
    String? businessName,
    String? branchId,
    bool? applicationSubmitted,
    String? templateSlug, // for analytics only
  }) async {
    if (_busy.contains(taskId)) {
      return const VisitOutcome(success: false);
    }
    _busy.add(taskId);
    _error = null;
    notifyListeners();

    try {
      final result = await _supabase.rpc('record_task_visit', params: {
        'p_task_id': taskId,
        'p_lat': lat,
        'p_lng': lng,
        'p_recorded_at': recordedAt.toUtc().toIso8601String(),
        'p_photo_path': photoPath,
        'p_contacted_count': contactedCount,
        'p_onboarded_count': onboardedCount,
        'p_accuracy_m': accuracyM,
        'p_governorate_id': governorateId,
        'p_notes': notes,
        'p_place_kind': placeKind,
        'p_place_name': placeName,
        'p_products': products,
        'p_merchant_name': merchantName,
        'p_business_name': businessName,
        'p_branch_id': branchId,
        'p_application_submitted': applicationSubmitted,
      });

      // RPC returns TABLE(visit_id, in_window) -> a single-row list.
      var inWindow = false;
      if (result is List && result.isNotEmpty && result.first is Map) {
        inWindow = (result.first as Map)['in_window'] as bool? ?? false;
      }

      // Reflect locally: bump the count and move the task to in_progress.
      _visitCounts[taskId] = (_visitCounts[taskId] ?? 0) + 1;
      _tasks = _tasks
          .map((t) => t.id == taskId && t.status == 'pending'
              ? t.copyWith(status: 'in_progress')
              : t)
          .toList();
      notifyListeners();

      await Analytics.track('field_visit_added', properties: {
        'task_id': taskId,
        'template_slug': templateSlug,
        'in_window': inWindow,
        'governorate_id': governorateId,
        'contacted_count': contactedCount,
        'onboarded_count': onboardedCount,
        'application_submitted': applicationSubmitted,
        'has_photo': photoPath.isNotEmpty,
      });
      return VisitOutcome(success: true, inWindow: inWindow);
    } on PostgrestException catch (e) {
      await Analytics.track('field_visit_failed',
          properties: {'reason': 'postgrest', 'pg_code': e.code, 'task_id': taskId});
      return VisitOutcome(success: false, error: e.message);
    } catch (_) {
      await Analytics.track('field_visit_failed',
          properties: {'reason': 'unexpected', 'task_id': taskId});
      return const VisitOutcome(
          success: false, error: 'حدث خطأ أثناء تسجيل الزيارة');
    } finally {
      _busy.remove(taskId);
      notifyListeners();
    }
  }

  /// Explicitly mark a task done (requires >= 1 visit, enforced server-side).
  Future<bool> completeTask(String taskId) async {
    if (_busy.contains(taskId)) return false;
    _busy.add(taskId);
    _error = null;
    notifyListeners();

    try {
      await _supabase.rpc('complete_field_task', params: {'p_task_id': taskId});
      _tasks = _tasks
          .map((t) => t.id == taskId ? t.copyWith(status: 'completed') : t)
          .toList();
      notifyListeners();
      await Analytics.track('field_task_completed', properties: {'task_id': taskId});
      return true;
    } on PostgrestException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (_) {
      _error = 'حدث خطأ أثناء إنهاء المهمة';
      notifyListeners();
      return false;
    } finally {
      _busy.remove(taskId);
      notifyListeners();
    }
  }
}
