/// A unified daily field-visit task (migration 018/019), with its optional
/// location check-in (task_checkins) embedded.
class FieldTask {
  final String id;
  final String? templateId;
  final String title;
  final String description;
  final String address;
  final DateTime windowStart;
  final DateTime windowEnd;
  final String status; // 'pending' | 'completed' | 'skipped'

  // Embedded check-in (null until the rep submits their location).
  final TaskCheckin? checkin;

  const FieldTask({
    required this.id,
    this.templateId,
    required this.title,
    this.description = '',
    this.address = '',
    required this.windowStart,
    required this.windowEnd,
    this.status = 'pending',
    this.checkin,
  });

  bool get isCompleted => status == 'completed';
  bool get hasCheckin => checkin != null;

  /// True if "now" falls inside the task's time window.
  bool get isWindowOpenNow {
    final now = DateTime.now();
    return !now.isBefore(windowStart) && !now.isAfter(windowEnd);
  }

  factory FieldTask.fromJson(Map<String, dynamic> json) {
    // PostgREST embeds a to-one relationship as either an object or a
    // single-element list depending on how it infers the FK — handle both.
    final raw = json['task_checkins'];
    Map<String, dynamic>? checkinMap;
    if (raw is Map) {
      checkinMap = Map<String, dynamic>.from(raw);
    } else if (raw is List && raw.isNotEmpty) {
      checkinMap = Map<String, dynamic>.from(raw.first as Map);
    }

    return FieldTask(
      id: json['id'] as String,
      templateId: json['template_id'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      address: json['address'] as String? ?? '',
      windowStart: DateTime.parse(json['window_start'] as String),
      windowEnd: DateTime.parse(json['window_end'] as String),
      status: json['status'] as String? ?? 'pending',
      checkin: checkinMap == null ? null : TaskCheckin.fromJson(checkinMap),
    );
  }

  FieldTask copyWith({String? status, TaskCheckin? checkin}) {
    return FieldTask(
      id: id,
      templateId: templateId,
      title: title,
      description: description,
      address: address,
      windowStart: windowStart,
      windowEnd: windowEnd,
      status: status ?? this.status,
      checkin: checkin ?? this.checkin,
    );
  }
}

/// One location check-in for a field task.
class TaskCheckin {
  final double lat;
  final double lng;
  final double? accuracyM;
  final DateTime recordedAt;
  final bool inWindow;

  const TaskCheckin({
    required this.lat,
    required this.lng,
    this.accuracyM,
    required this.recordedAt,
    required this.inWindow,
  });

  factory TaskCheckin.fromJson(Map<String, dynamic> json) {
    return TaskCheckin(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      inWindow: json['in_window'] as bool? ?? false,
    );
  }
}
