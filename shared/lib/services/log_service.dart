import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/session_log.dart';
import '../utils/logger.dart';
import 'sync_service.dart';

class LogService {
  final Ref _ref;

  LogService(this._ref);

  Box get _box => Hive.box(SyncService.sessionsBoxName);

  List<SessionLog> getSessionLogs() {
    final list = <SessionLog>[];
    for (var key in _box.keys) {
      final val = _box.get(key);
      if (val != null) {
        list.add(SessionLog.fromJson(Map<String, dynamic>.from(val as Map)));
      }
    }
    // Sort latest first
    list.sort((a, b) => b.endedAt.compareTo(a.endedAt));
    return list;
  }

  Stream<List<SessionLog>> watchSessionLogs() {
    return _box.watch().map((_) => getSessionLogs());
  }

  Future<void> submitMemberFeedback(String logId, int rating, String note) async {
    final existing = _box.get(logId);
    if (existing != null) {
      final map = Map<String, dynamic>.from(existing as Map);
      final updated = SessionLog.fromJson(map).copyWith(
        rating: rating,
        memberNotes: note,
      );
      await _ref.read(syncServiceProvider).saveSessionLog(updated);
      AppLogger.schedule('Member feedback updated for session $logId');
    }
  }

  Future<void> submitTrainerFeedback(String logId, String notes) async {
    final existing = _box.get(logId);
    if (existing != null) {
      final map = Map<String, dynamic>.from(existing as Map);
      final updated = SessionLog.fromJson(map).copyWith(
        trainerNotes: notes,
      );
      await _ref.read(syncServiceProvider).saveSessionLog(updated);
      AppLogger.schedule('Trainer feedback notes updated for session $logId');
    }
  }

  String generateExportText(SessionLog log) {
    final dateStr = '${log.startedAt.day}/${log.startedAt.month}/${log.startedAt.year}';
    final durMin = log.durationSec ~/ 60;
    final durSec = log.durationSec % 60;
    
    return 'WTF Fitness Call Session Log Summary\n'
        '===================================\n'
        'Date: $dateStr\n'
        'Start: ${log.startedAt.toLocal().hour.toString().padLeft(2, '0')}:${log.startedAt.toLocal().minute.toString().padLeft(2, '0')}\n'
        'Duration: ${durMin}m ${durSec}s\n'
        'Rating: ${log.rating != null ? "${log.rating} Stars" : "Unrated"}\n\n'
        'Member Notes:\n'
        '${log.memberNotes ?? "No notes added"}\n\n'
        'Trainer Notes:\n'
        '${log.trainerNotes ?? "No notes added"}\n'
        '===================================';
  }
}

final logServiceProvider = Provider<LogService>((ref) {
  return LogService(ref);
});

final sessionLogsStreamProvider = StreamProvider<List<SessionLog>>((ref) {
  final logService = ref.watch(logServiceProvider);
  return logService.watchSessionLogs();
});

final sessionLogsProvider = Provider<List<SessionLog>>((ref) {
  final asyncLogs = ref.watch(sessionLogsStreamProvider);
  return asyncLogs.maybeWhen(
    data: (list) => list,
    orElse: () => ref.read(logServiceProvider).getSessionLogs(),
  );
});

enum LogFilter { all, last7Days, thisMonth }

final activeLogFilterProvider = StateProvider<LogFilter>((ref) => LogFilter.all);

final filteredSessionLogsProvider = Provider<List<SessionLog>>((ref) {
  final logs = ref.watch(sessionLogsProvider);
  final filter = ref.watch(activeLogFilterProvider);
  final now = DateTime.now();

  switch (filter) {
    case LogFilter.all:
      return logs;
    case LogFilter.last7Days:
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      return logs.where((l) => l.startedAt.isAfter(sevenDaysAgo)).toList();
    case LogFilter.thisMonth:
      return logs.where((l) => 
        l.startedAt.year == now.year && 
        l.startedAt.month == now.month
      ).toList();
  }
});
