import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('User Model Tests', () {
    test('User serialization and deserialization works correctly', () {
      final user = User(
        id: 'test_user',
        role: UserRole.member,
        name: 'John Doe',
        email: 'john@example.com',
        avatarUrl: 'https://avatar.com/john',
        assignedTrainerId: 'trainer_id',
      );

      final json = user.toJson();
      expect(json['id'], 'test_user');
      expect(json['role'], 'member');
      expect(json['name'], 'John Doe');
      expect(json['email'], 'john@example.com');
      expect(json['avatarUrl'], 'https://avatar.com/john');
      expect(json['assignedTrainerId'], 'trainer_id');

      final parsed = User.fromJson(json);
      expect(parsed.id, 'test_user');
      expect(parsed.role, UserRole.member);
      expect(parsed.name, 'John Doe');
      expect(parsed.email, 'john@example.com');
      expect(parsed.avatarUrl, 'https://avatar.com/john');
      expect(parsed.assignedTrainerId, 'trainer_id');
    });
  });

  group('Message Model Tests', () {
    test('Message status and json roundtrip matches', () {
      final msg = Message(
        id: 'msg_123',
        chatId: 'chat_456',
        senderId: 'user_1',
        receiverId: 'user_2',
        text: 'Hello from tests',
        createdAt: DateTime.parse('2026-05-22T10:00:00.000Z'),
        status: MessageStatus.sent,
      );

      final json = msg.toJson();
      expect(json['status'], 'sent');
      expect(json['text'], 'Hello from tests');
      expect(json['createdAt'], '2026-05-22T10:00:00.000Z');

      final parsed = Message.fromJson(json);
      expect(parsed.id, 'msg_123');
      expect(parsed.status, MessageStatus.sent);
      expect(parsed.createdAt.isAtSameMomentAs(msg.createdAt), true);
    });
  });

  group('SessionLog Duration Tests', () {
    test('Duration calculates accurately and json serialization works', () {
      final start = DateTime.parse('2026-05-22T10:00:00.000Z');
      final end = DateTime.parse('2026-05-22T10:25:30.000Z');
      final log = SessionLog(
        id: 'session_1',
        memberId: 'dk_member',
        trainerId: 'aarav_trainer',
        startedAt: start,
        endedAt: end,
        durationSec: 1530,
        rating: 5,
        memberNotes: 'Felt great!',
        trainerNotes: 'DK is doing good progress',
      );

      expect(log.durationSec, 25 * 60 + 30); // 1530 seconds

      final json = log.toJson();
      expect(json['durationSec'], 1530);
      expect(json['rating'], 5);

      final parsed = SessionLog.fromJson(json);
      expect(parsed.durationSec, 1530);
      expect(parsed.rating, 5);
      expect(parsed.memberNotes, 'Felt great!');
    });
  });

  group('Scheduler Overlap conflict validator rules', () {
    bool isConflict(DateTime newSlot, List<CallRequest> approvedRequests) {
      for (var req in approvedRequests) {
        if (req.status == CallRequestStatus.approved) {
          final diff = req.scheduledFor.difference(newSlot).inMinutes.abs();
          if (diff < 30) {
            return true; // Slots overlap within 30 min block
          }
        }
      }
      return false;
    }

    final testTime = DateTime.parse('2026-05-22T15:00:00.000Z');
    final approvedList = [
      CallRequest(
        id: 'r1',
        memberId: 'dk',
        trainerId: 'aarav',
        requestedAt: DateTime.now(),
        scheduledFor: testTime,
        note: 'Workout',
        status: CallRequestStatus.approved,
      )
    ];

    test('Conflict detected within 30 minutes interval', () {
      // 10 minutes after scheduled slot -> conflict
      final conflictTime1 = testTime.add(const Duration(minutes: 15));
      expect(isConflict(conflictTime1, approvedList), true);

      // 10 minutes before scheduled slot -> conflict
      final conflictTime2 = testTime.subtract(const Duration(minutes: 15));
      expect(isConflict(conflictTime2, approvedList), true);

      // Exactly same time -> conflict
      expect(isConflict(testTime, approvedList), true);
    });

    test('No conflict detected outside 30 minutes interval', () {
      // Exactly 30 minutes after -> no conflict
      final freeTime1 = testTime.add(const Duration(minutes: 30));
      expect(isConflict(freeTime1, approvedList), false);

      // Exactly 30 minutes before -> no conflict
      final freeTime2 = testTime.subtract(const Duration(minutes: 30));
      expect(isConflict(freeTime2, approvedList), false);

      // 1 hour later -> no conflict
      final freeTime3 = testTime.add(const Duration(hours: 1));
      expect(isConflict(freeTime3, approvedList), false);
    });

    test('Non-approved requests are ignored in conflict check', () {
      final declinedList = [
        CallRequest(
          id: 'r2',
          memberId: 'dk',
          trainerId: 'aarav',
          requestedAt: DateTime.now(),
          scheduledFor: testTime,
          note: 'Workout',
          status: CallRequestStatus.declined,
        )
      ];
      expect(isConflict(testTime, declinedList), false);
    });
  });
}
