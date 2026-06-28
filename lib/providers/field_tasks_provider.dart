import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/field_task.dart';
import '../services/analytics.dart';
import '../services/location_service.dart';

/// Outcome of a check-in attempt, so the UI can show the right message.
class CheckinOutcome {
  final bool success;
  final bool inWindow;
  final String? error;
  const CheckinOutcome({required this.success, this.inWindow = false, this.error});
}

/// Drives the unified daily field-visit schedule + per-task GPS check-ins.
class FieldTasksProvider extends ChangeNotifier {
  final _supabase = Supabase.instance.client;

  List<FieldTask> _tasks = [];
  bool _isLoading = false;
  bool _locationConsent = false;
  String? _error;
  String? _cachedDate;
  final Set<String> _submitting = {}; // task ids with an in-flight check-in

  List<FieldTask> get tasks => _tasks;
  bool get isLoading => _isLoading;
  bool get locationConsent => _locationConsent;
  String? get error => _error;
  bool isSubmitting(String taskId) => _submitting.contains(taskId);

  /// Current date in Cairo time (UTC+2; Egypt has no DST).
  static String _cairoToday() {
    final cairo = DateTime.now().toUtc().add(const Duration(hours: 2));
    return cairo.toIso8601String().substring(0, 10);
  }

  /// Load today's field tasks for the current rep. Generates them via the
  /// idempotent RPC first, then fetches with the embedded check-in.
  Future<void> loadTodaysTasks() async {
    final today = _cairoToday();
    if (_cachedDate == today && _tasks.isNotEmpty) return;
    if (_cachedDate != today) {
      _tasks = [];
      _cachedDate = null;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _loadConsent();

      // Idempotent: creates today's 3 tasks for this rep if missing.
      await _supabase.rpc('ensure_my_field_tasks');

      final data = await _supabase
          .from('field_tasks')
          .select('*, task_checkins(*)')
          .eq('task_date', today)
          .order('window_start', ascending: true);

      _tasks = (data as List)
          .map((row) => FieldTask.fromJson(row as Map<String, dynamic>))
          .toList();
      _cachedDate = today;
    } catch (_) {
      _error = 'حدث خطأ أثناء تحميل مهام اليوم';
    }

    _isLoading = false;
    notifyListeners();
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

  /// Record the rep's one-time opt-in to location check-ins.
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

  /// Capture a GPS fix and submit it as this task's check-in.
  /// Caller must ensure consent is granted first.
  Future<CheckinOutcome> submitCheckin(FieldTask task) async {
    if (_submitting.contains(task.id)) {
      return const CheckinOutcome(success: false);
    }
    _submitting.add(task.id);
    _error = null;
    notifyListeners();

    try {
      final loc = await LocationService.getCurrentPosition();
      if (!loc.isSuccess) {
        await Analytics.track('field_task_checkin_failed',
            properties: {'reason': 'location_unavailable', 'task_id': task.id});
        return CheckinOutcome(success: false, error: loc.error);
      }

      final pos = loc.position!;
      final inWindow = await _supabase.rpc(
        'record_task_checkin',
        params: {
          'p_task_id': task.id,
          'p_lat': pos.latitude,
          'p_lng': pos.longitude,
          'p_accuracy_m': pos.accuracy,
          'p_recorded_at': pos.timestamp.toUtc().toIso8601String(),
        },
      ) as bool;

      // Reflect the new check-in + completed status locally.
      _tasks = _tasks.map((t) {
        if (t.id != task.id) return t;
        return t.copyWith(
          status: 'completed',
          checkin: TaskCheckin(
            lat: pos.latitude,
            lng: pos.longitude,
            accuracyM: pos.accuracy,
            recordedAt: pos.timestamp,
            inWindow: inWindow,
          ),
        );
      }).toList();
      notifyListeners();

      await Analytics.track('field_task_checkin_submitted', properties: {
        'task_id': task.id,
        'template_id': task.templateId,
        'in_window': inWindow,
      });
      return CheckinOutcome(success: true, inWindow: inWindow);
    } on PostgrestException catch (e) {
      await Analytics.track('field_task_checkin_failed',
          properties: {'reason': 'postgrest', 'pg_code': e.code, 'task_id': task.id});
      return CheckinOutcome(success: false, error: e.message);
    } catch (_) {
      await Analytics.track('field_task_checkin_failed',
          properties: {'reason': 'unexpected', 'task_id': task.id});
      return const CheckinOutcome(
          success: false, error: 'حدث خطأ أثناء تسجيل الموقع');
    } finally {
      _submitting.remove(task.id);
      notifyListeners();
    }
  }
}
