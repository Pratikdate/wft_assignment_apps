enum CallRequestStatus { pending, approved, declined, cancelled }

class CallRequest {
  final String id;
  final String memberId;
  final String trainerId;
  final DateTime requestedAt;
  final DateTime scheduledFor;
  final String note;
  final CallRequestStatus status;
  final String? declineReason;

  CallRequest({
    required this.id,
    required this.memberId,
    required this.trainerId,
    required this.requestedAt,
    required this.scheduledFor,
    required this.note,
    required this.status,
    this.declineReason,
  });

  factory CallRequest.fromJson(Map<String, dynamic> json) {
    CallRequestStatus status = CallRequestStatus.pending;
    if (json['status'] == 'approved') {
      status = CallRequestStatus.approved;
    } else if (json['status'] == 'declined') {
      status = CallRequestStatus.declined;
    } else if (json['status'] == 'cancelled') {
      status = CallRequestStatus.cancelled;
    }

    return CallRequest(
      id: json['id'] as String,
      memberId: json['memberId'] as String,
      trainerId: json['trainerId'] as String,
      requestedAt: json['requestedAt'] != null 
          ? DateTime.parse(json['requestedAt'] as String) 
          : DateTime.now(),
      scheduledFor: DateTime.parse(json['scheduledFor'] as String),
      note: (json['note'] ?? '') as String,
      status: status,
      declineReason: json['declineReason'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    String statusStr = 'pending';
    if (status == CallRequestStatus.approved) {
      statusStr = 'approved';
    } else if (status == CallRequestStatus.declined) {
      statusStr = 'declined';
    } else if (status == CallRequestStatus.cancelled) {
      statusStr = 'cancelled';
    }

    return {
      'id': id,
      'memberId': memberId,
      'trainerId': trainerId,
      'requestedAt': requestedAt.toIso8601String(),
      'scheduledFor': scheduledFor.toIso8601String(),
      'note': note,
      'status': statusStr,
      'declineReason': declineReason,
    };
  }

  CallRequest copyWith({
    String? id,
    String? memberId,
    String? trainerId,
    DateTime? requestedAt,
    DateTime? scheduledFor,
    String? note,
    CallRequestStatus? status,
    String? declineReason,
  }) {
    return CallRequest(
      id: id ?? this.id,
      memberId: memberId ?? this.memberId,
      trainerId: trainerId ?? this.trainerId,
      requestedAt: requestedAt ?? this.requestedAt,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      note: note ?? this.note,
      status: status ?? this.status,
      declineReason: declineReason ?? this.declineReason,
    );
  }
}
