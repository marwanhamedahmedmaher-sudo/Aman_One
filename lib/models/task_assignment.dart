class TaskAssignment {
  final String id;
  final String poolLeadId;
  final String assignedTo;
  final DateTime assignedDate;
  final String status; // 'pending', 'completed', 'skipped'
  final String outcomeNotes;
  final String? convertedMerchantId;
  // Joined from cross_sell_pool:
  final String leadName;
  final String leadPhone;
  final String leadNotes;

  const TaskAssignment({
    required this.id,
    required this.poolLeadId,
    required this.assignedTo,
    required this.assignedDate,
    this.status = 'pending',
    this.outcomeNotes = '',
    this.convertedMerchantId,
    required this.leadName,
    required this.leadPhone,
    this.leadNotes = '',
  });

  factory TaskAssignment.fromJson(Map<String, dynamic> json) {
    final pool = json['cross_sell_pool'] as Map<String, dynamic>?;
    return TaskAssignment(
      id: json['id'] as String,
      poolLeadId: json['pool_lead_id'] as String,
      assignedTo: json['assigned_to'] as String,
      assignedDate: DateTime.parse(json['assigned_date'] as String),
      status: json['status'] as String? ?? 'pending',
      outcomeNotes: json['outcome_notes'] as String? ?? '',
      convertedMerchantId: json['converted_merchant_id'] as String?,
      leadName: pool?['name'] as String? ?? '',
      leadPhone: pool?['phone'] as String? ?? '',
      leadNotes: pool?['notes'] as String? ?? '',
    );
  }

  TaskAssignment copyWith({
    String? status,
    String? outcomeNotes,
    String? convertedMerchantId,
  }) {
    return TaskAssignment(
      id: id,
      poolLeadId: poolLeadId,
      assignedTo: assignedTo,
      assignedDate: assignedDate,
      status: status ?? this.status,
      outcomeNotes: outcomeNotes ?? this.outcomeNotes,
      convertedMerchantId: convertedMerchantId ?? this.convertedMerchantId,
      leadName: leadName,
      leadPhone: leadPhone,
      leadNotes: leadNotes,
    );
  }

  bool get isPending => status == 'pending';
  bool get isCompleted => status == 'completed';
  bool get isSkipped => status == 'skipped';
}
