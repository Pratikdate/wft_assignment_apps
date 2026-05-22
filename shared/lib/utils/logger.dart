import 'dart:async';

enum LogTag { CHAT, RTC, SCHEDULE, AUTH, SYSTEM }

class LogEntry {
  final DateTime timestamp;
  final LogTag tag;
  final String message;
  final String? details;

  LogEntry({
    required this.timestamp,
    required this.tag,
    required this.message,
    this.details,
  });

  @override
  String toString() {
    return '[${tag.name}] ${timestamp.toIso8601String()} - $message';
  }
}

class AppLogger {
  static const int _maxLogs = 100;
  static const bool _printToConsole = true;
  static final List<LogEntry> _logs = [];
  
  static final _logController = StreamController<List<LogEntry>>.broadcast();

  static List<LogEntry> get logs => List.unmodifiable(_logs);
  static Stream<List<LogEntry>> get logsStream => _logController.stream;

  static void log(LogTag tag, String message, {String? details}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      tag: tag,
      message: message,
      details: details,
    );

    _logs.insert(0, entry);
    if (_logs.length > _maxLogs) {
      _logs.removeLast();
    }

    _logController.add(List.from(_logs));

    if (_printToConsole) {
      // Print to terminal console
      print('${entry.timestamp.toIso8601String()} [${tag.name}] $message');
      if (details != null) {
        print('  Details: $details');
      }
    }
  }

  static void chat(String message, {String? details}) => log(LogTag.CHAT, message, details: details);
  static void rtc(String message, {String? details}) => log(LogTag.RTC, message, details: details);
  static void schedule(String message, {String? details}) => log(LogTag.SCHEDULE, message, details: details);
  static void auth(String message, {String? details}) => log(LogTag.AUTH, message, details: details);
  static void system(String message, {String? details}) => log(LogTag.SYSTEM, message, details: details);
}
