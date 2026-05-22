class RoomMeta {
  final String id;
  final String callRequestId;
  final String hmsRoomId;
  final String hmsRoleMember;
  final String hmsRoleTrainer;

  RoomMeta({
    required this.id,
    required this.callRequestId,
    required this.hmsRoomId,
    required this.hmsRoleMember,
    required this.hmsRoleTrainer,
  });

  factory RoomMeta.fromJson(Map<String, dynamic> json) {
    return RoomMeta(
      id: json['id'] as String,
      callRequestId: json['callRequestId'] as String,
      hmsRoomId: json['hmsRoomId'] as String,
      hmsRoleMember: (json['hmsRoleMember'] ?? 'member') as String,
      hmsRoleTrainer: (json['hmsRoleTrainer'] ?? 'trainer') as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'callRequestId': callRequestId,
      'hmsRoomId': hmsRoomId,
      'hmsRoleMember': hmsRoleMember,
      'hmsRoleTrainer': hmsRoleTrainer,
    };
  }
}
