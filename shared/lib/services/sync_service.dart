import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import '../models/message.dart';
import '../models/call_request.dart';
import '../models/session_log.dart';
import '../models/room_meta.dart';
import '../utils/logger.dart';
import 'auth_service.dart';

class SyncService {
  static const String messagesBoxName = 'messages_box';
  static const String callsBoxName = 'calls_box';
  static const String sessionsBoxName = 'sessions_box';
  static const String roomsBoxName = 'rooms_box';

  late Box _messagesBox;
  late Box _callsBox;
  late Box _sessionsBox;
  late Box _roomsBox;

  Timer? _syncTimer;
  int _lastSyncTimestamp = 0;
  bool _isSyncing = false;

  final Ref _ref;

  SyncService(this._ref);

  String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:3000';
    }
    // Android emulator loopback alias to host machine
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

  Future<void> init() async {
    _messagesBox = await Hive.openBox(messagesBoxName);
    _callsBox = await Hive.openBox(callsBoxName);
    _sessionsBox = await Hive.openBox(sessionsBoxName);
    _roomsBox = await Hive.openBox(roomsBoxName);

    AppLogger.system('SyncService boxes opened successfully');
  }

  void startSyncLoop() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      syncNow();
      fetchTypingStatus();
    });
    AppLogger.system('Periodic syncing loop started');
  }

  void stopSyncLoop() {
    _syncTimer?.cancel();
    AppLogger.system('Periodic syncing loop stopped');
  }

  Future<void> syncNow() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/sync?since=$_lastSyncTimestamp'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _lastSyncTimestamp = data['timestamp'] as int;

        final newMessages = data['messages'] as List;
        final newRequests = data['callRequests'] as List;
        final newLogs = data['sessionLogs'] as List;
        final roomMetas = data['roomMetas'] as List;

        // Sync messages to Hive
        for (var item in newMessages) {
          final map = Map<String, dynamic>.from(item as Map);
          final message = Message.fromJson(map);
          await _messagesBox.put(message.id, message.toJson());
        }

        // Sync call requests to Hive
        for (var item in newRequests) {
          final map = Map<String, dynamic>.from(item as Map);
          final request = CallRequest.fromJson(map);
          await _callsBox.put(request.id, request.toJson());
        }

        // Sync session logs to Hive
        for (var item in newLogs) {
          final map = Map<String, dynamic>.from(item as Map);
          final log = SessionLog.fromJson(map);
          await _sessionsBox.put(log.id, log.toJson());
        }

        // Sync room metas to Hive
        for (var item in roomMetas) {
          final map = Map<String, dynamic>.from(item as Map);
          final meta = RoomMeta.fromJson(map);
          await _roomsBox.put(meta.callRequestId, meta.toJson());
        }
      }
    } catch (e) {
      // Fail silently for offline robustness
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> sendChatMessage(Message message) async {
    // 1. Write locally
    await _messagesBox.put(message.id, message.toJson());
    AppLogger.chat('Saved message locally: ${message.text}');

    // 2. Post to server
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/chat'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(message.toJson()),
      );
      if (response.statusCode == 200) {
        final serverMsg = Message.fromJson(json.decode(response.body));
        await _messagesBox.put(serverMsg.id, serverMsg.toJson());
        AppLogger.chat('Message synced to server: ${serverMsg.id}');
      }
    } catch (e) {
      AppLogger.chat('Message sync offline: will retry on next cycle');
    }
  }

  Future<void> updateMessageStatus(String messageId, MessageStatus status) async {
    final existing = _messagesBox.get(messageId);
    if (existing != null) {
      final map = Map<String, dynamic>.from(existing as Map);
      final updated = Message.fromJson(map).copyWith(status: status);
      await _messagesBox.put(messageId, updated.toJson());
      
      try {
        await http.post(
          Uri.parse('$baseUrl/api/chat'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(updated.toJson()),
        );
      } catch (e) {
        // Fail silently, will sync later
      }
    }
  }

  Future<void> setTypingStatus(String userId, bool isTyping) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/typing'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'userId': userId, 'isTyping': isTyping}),
      );
    } catch (e) {
      // Ignore network errors
    }
  }

  Future<void> fetchTypingStatus() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/typing'));
      if (response.statusCode == 200) {
        final typingMap = Map<String, dynamic>.from(json.decode(response.body));
        final currentUser = _ref.read(currentUserProvider);
        if (currentUser != null) {
          final isPeerTyping = typingMap.entries
              .where((e) => e.key != currentUser.id)
              .any((e) => e.value == true);
          _ref.read(peerTypingProvider.notifier).state = isPeerTyping;
        }
      }
    } catch (e) {
      // Ignore
    }
  }

  Future<void> requestCall(CallRequest request) async {
    await _callsBox.put(request.id, request.toJson());
    AppLogger.schedule('Saved call request locally: ${request.scheduledFor}');

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/calls'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(request.toJson()),
      );
      if (response.statusCode == 200) {
        final serverReq = CallRequest.fromJson(json.decode(response.body));
        await _callsBox.put(serverReq.id, serverReq.toJson());
        AppLogger.schedule('Call request synced to server');
      }
    } catch (e) {
      AppLogger.schedule('Call request sync failed (offline)');
    }
  }

  Future<void> updateCallRequestStatus(String requestId, CallRequestStatus status, {String? declineReason}) async {
    final existing = _callsBox.get(requestId);
    if (existing != null) {
      final map = Map<String, dynamic>.from(existing as Map);
      final updated = CallRequest.fromJson(map).copyWith(
        status: status,
        declineReason: declineReason,
      );
      await _callsBox.put(requestId, updated.toJson());

      try {
        final response = await http.post(
          Uri.parse('$baseUrl/api/calls'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(updated.toJson()),
        );
        
        if (response.statusCode == 200 && status == CallRequestStatus.approved) {
          // Trigger room creation on server
          final roomResponse = await http.post(
            Uri.parse('$baseUrl/api/rooms'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'callRequestId': requestId}),
          );
          if (roomResponse.statusCode == 200) {
            final roomMeta = RoomMeta.fromJson(json.decode(roomResponse.body));
            await _roomsBox.put(requestId, roomMeta.toJson());
            AppLogger.rtc('100ms Room created: ${roomMeta.hmsRoomId}');
          }
        }
      } catch (e) {
        AppLogger.schedule('Failed to sync call update to server');
      }
    }
  }

  Future<void> saveSessionLog(SessionLog log) async {
    await _sessionsBox.put(log.id, log.toJson());
    AppLogger.schedule('Session log saved locally');

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/sessions'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(log.toJson()),
      );
      if (response.statusCode == 200) {
        final serverLog = SessionLog.fromJson(json.decode(response.body));
        await _sessionsBox.put(serverLog.id, serverLog.toJson());
        AppLogger.schedule('Session log synced to server');
      }
    } catch (e) {
      AppLogger.schedule('Session log sync offline');
    }
  }

  Future<String> getHMSCallToken({required String userId, required String role, required String roomId}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/token?userId=$userId&role=$role&roomId=$roomId'),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['token'] as String;
    } else {
      throw Exception('Failed to fetch HMS token from server');
    }
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(ref);
  final initFuture = service.init();

  ref.listen<User?>(currentUserProvider, (previous, next) {
    if (next != null) {
      initFuture.then((_) {
        if (ref.read(currentUserProvider) != null) {
          service.startSyncLoop();
        }
      });
    } else {
      service.stopSyncLoop();
    }
  }, fireImmediately: true);

  ref.onDispose(() {
    service.stopSyncLoop();
  });
  return service;
});

final peerTypingProvider = StateProvider<bool>((ref) => false);
