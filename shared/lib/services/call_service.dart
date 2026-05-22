import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hmssdk_flutter/hmssdk_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../models/call_request.dart';
import '../models/room_meta.dart';
import '../models/session_log.dart';
import '../models/user.dart';
import '../utils/logger.dart';
import 'auth_service.dart';
import 'sync_service.dart';

class HMSState {
  final bool isLocalVideoOn;
  final bool isLocalAudioOn;
  final bool isRemoteVideoOn;
  final bool isRemoteAudioOn;
  final bool isLocalCameraFlipped;
  final bool isRemoteCameraFlipped;
  final bool isConnected;
  final bool isReconnecting;
  final String? remoteParticipantName;
  final List<String> peers;
  final HMSVideoTrack? localVideoTrack;
  final HMSVideoTrack? remoteVideoTrack;

  HMSState({
    this.isLocalVideoOn = true,
    this.isLocalAudioOn = true,
    this.isRemoteVideoOn = true,
    this.isRemoteAudioOn = true,
    this.isLocalCameraFlipped = false,
    this.isRemoteCameraFlipped = false,
    this.isConnected = false,
    this.isReconnecting = false,
    this.remoteParticipantName,
    this.peers = const [],
    this.localVideoTrack,
    this.remoteVideoTrack,
  });

  HMSState copyWith({
    bool? isLocalVideoOn,
    bool? isLocalAudioOn,
    bool? isRemoteVideoOn,
    bool? isRemoteAudioOn,
    bool? isLocalCameraFlipped,
    bool? isRemoteCameraFlipped,
    bool? isConnected,
    bool? isReconnecting,
    String? remoteParticipantName,
    List<String>? peers,
    HMSVideoTrack? localVideoTrack,
    HMSVideoTrack? remoteVideoTrack,
    bool clearLocalTrack = false,
    bool clearRemoteTrack = false,
  }) {
    return HMSState(
      isLocalVideoOn: isLocalVideoOn ?? this.isLocalVideoOn,
      isLocalAudioOn: isLocalAudioOn ?? this.isLocalAudioOn,
      isRemoteVideoOn: isRemoteVideoOn ?? this.isRemoteVideoOn,
      isRemoteAudioOn: isRemoteAudioOn ?? this.isRemoteAudioOn,
      isLocalCameraFlipped: isLocalCameraFlipped ?? this.isLocalCameraFlipped,
      isRemoteCameraFlipped: isRemoteCameraFlipped ?? this.isRemoteCameraFlipped,
      isConnected: isConnected ?? this.isConnected,
      isReconnecting: isReconnecting ?? this.isReconnecting,
      remoteParticipantName: remoteParticipantName ?? this.remoteParticipantName,
      peers: peers ?? this.peers,
      localVideoTrack: clearLocalTrack ? null : (localVideoTrack ?? this.localVideoTrack),
      remoteVideoTrack: clearRemoteTrack ? null : (remoteVideoTrack ?? this.remoteVideoTrack),
    );
  }
}

class CallService extends HMSUpdateListener {
  final Ref _ref;
  final _uuid = const Uuid();
  HMSSDK? _hmsSdk;
  
  // Call Session Variables
  DateTime? _callStartTime;
  String? _activeCallRequestId;
  bool _isRealHMSUsed = false;
  
  // Simulated RTC state variables
  Timer? _simulationTimer;
  Timer? _reconnectSimTimer;
  Timer? _simSignalTimer;

  bool get isRealHMSUsed => _isRealHMSUsed;

  CallService(this._ref) {
    // Enable real HMSSDK connection only on Android.
    // iOS, Web, and Desktop fall back to high-fidelity simulator.
    _isRealHMSUsed = !kIsWeb && Platform.isAndroid;
  }

  Box get _callsBox => Hive.box(SyncService.callsBoxName);
  Box get _roomsBox => Hive.box(SyncService.roomsBoxName);

  List<CallRequest> getCallRequests() {
    final list = <CallRequest>[];
    for (var key in _callsBox.keys) {
      final val = _callsBox.get(key);
      if (val != null) {
        list.add(CallRequest.fromJson(Map<String, dynamic>.from(val as Map)));
      }
    }
    list.sort((a, b) => b.scheduledFor.compareTo(a.scheduledFor));
    return list;
  }

  Stream<List<CallRequest>> watchCallRequests() {
    return _callsBox.watch().map((_) => getCallRequests());
  }

  RoomMeta? getRoomMetaForRequest(String requestId) {
    final val = _roomsBox.get(requestId);
    if (val == null) return null;
    return RoomMeta.fromJson(Map<String, dynamic>.from(val as Map));
  }

  bool isSlotConflict(DateTime time) {
    final existing = getCallRequests();
    for (var req in existing) {
      if (req.status == CallRequestStatus.approved) {
        final diff = req.scheduledFor.difference(time).inMinutes.abs();
        if (diff < 30) {
          return true; // Slots overlap within 30 min block
        }
      }
    }
    return false;
  }

  Future<void> requestCall(DateTime scheduledFor, String note) async {
    final currentUser = _ref.read(currentUserProvider);
    if (currentUser == null) return;

    if (scheduledFor.isBefore(DateTime.now())) {
      throw Exception('Cannot schedule a call in the past.');
    }

    if (isSlotConflict(scheduledFor)) {
      throw Exception('This time slot is already booked. Please choose another.');
    }

    final trainerId = currentUser.assignedTrainerId ?? 'aarav_trainer';
    final request = CallRequest(
      id: _uuid.v4(),
      memberId: currentUser.id,
      trainerId: trainerId,
      requestedAt: DateTime.now(),
      scheduledFor: scheduledFor,
      note: note.length > 140 ? note.substring(0, 140) : note,
      status: CallRequestStatus.pending,
    );

    await _ref.read(syncServiceProvider).requestCall(request);
    AppLogger.schedule('Requested call for ${scheduledFor.toIso8601String()}');
  }

  Future<void> approveCall(String requestId) async {
    await _ref.read(syncServiceProvider).updateCallRequestStatus(requestId, CallRequestStatus.approved);
    AppLogger.schedule('Approved request $requestId');
  }

  Future<void> declineCall(String requestId, String reason) async {
    await _ref.read(syncServiceProvider).updateCallRequestStatus(
      requestId, 
      CallRequestStatus.declined,
      declineReason: reason,
    );
    AppLogger.schedule('Declined request $requestId: $reason');
  }

  // --- RTC Calling Methods ---
  
  Future<void> joinCall(String callRequestId) async {
    _activeCallRequestId = callRequestId;
    _callStartTime = DateTime.now();

    final currentUser = _ref.read(currentUserProvider);
    if (currentUser == null) return;

    final roomMeta = getRoomMetaForRequest(callRequestId);
    if (roomMeta == null) {
      AppLogger.rtc('No Room metadata found for call request: $callRequestId');
      throw Exception('No Room meta found');
    }

    final hmsRole = currentUser.role == UserRole.trainer 
        ? roomMeta.hmsRoleTrainer 
        : roomMeta.hmsRoleMember;

    AppLogger.rtc('Joining Call Room: ${roomMeta.hmsRoomId} with role: $hmsRole');
    
    // Fetch 100ms token from server
    final token = await _ref.read(syncServiceProvider).getHMSCallToken(
      userId: currentUser.id,
      role: hmsRole,
      roomId: roomMeta.hmsRoomId,
    );

    _ref.read(hmsStateProvider.notifier).state = HMSState(
      isConnected: false,
      isReconnecting: false,
    );

    if (_isRealHMSUsed) {
      // Request microphone and camera permissions
      try {
        await [Permission.camera, Permission.microphone].request();
      } catch (e) {
        AppLogger.rtc('Error requesting permissions: $e');
      }

      // Initialize real HMS SDK
      _hmsSdk = HMSSDK();
      await _hmsSdk!.build();
      _hmsSdk!.addUpdateListener(listener: this);
      
      final config = HMSConfig(
        authToken: token,
        userName: currentUser.name,
      );
      
      await _hmsSdk!.join(config: config);
    } else {
      // Simulated RTC join flow (for Desktop/Web developer validation)
      _ref.read(hmsStateProvider.notifier).state = HMSState(
        isConnected: true,
        isLocalAudioOn: _ref.read(hmsStateProvider).isLocalAudioOn,
        isLocalVideoOn: _ref.read(hmsStateProvider).isLocalVideoOn,
        isLocalCameraFlipped: false,
        remoteParticipantName: null,
        peers: [currentUser.role == UserRole.member ? 'DK' : 'Aarav (Lead Trainer)'],
      );
      
      AppLogger.rtc('[SIMULATOR] Joined call room successfully');
      
      _simSignalTimer?.cancel();
      _simSignalTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        _syncSimulatedState();
      });
      await _syncSimulatedState();
      
      // Simulate micro connection instability for testing network resilience
      _simulationTimer = Timer(const Duration(seconds: 12), () {
        simulateNetworkBlink();
      });
    }
  }

  void simulateNetworkBlink() {
    AppLogger.rtc('[SIMULATOR] Simulating connection instability');
    final currentState = _ref.read(hmsStateProvider);
    _ref.read(hmsStateProvider.notifier).state = currentState.copyWith(
      isConnected: false,
      isReconnecting: true,
    );

    _reconnectSimTimer = Timer(const Duration(seconds: 3), () {
      final updatedState = _ref.read(hmsStateProvider);
      _ref.read(hmsStateProvider.notifier).state = updatedState.copyWith(
        isConnected: true,
        isReconnecting: false,
      );
      AppLogger.rtc('[SIMULATOR] Connection re-established');
    });
  }

  Future<void> _syncSimulatedState({bool isLeaving = false}) async {
    final currentUser = _ref.read(currentUserProvider);
    if (currentUser == null || _activeCallRequestId == null) return;

    final roomMeta = getRoomMetaForRequest(_activeCallRequestId!);
    if (roomMeta == null) return;

    final syncService = _ref.read(syncServiceProvider);
    final baseUrl = syncService.baseUrl;
    final roomId = roomMeta.hmsRoomId;

    final String simRole = currentUser.role == UserRole.member ? 'member' : 'trainer';
    final currentState = _ref.read(hmsStateProvider);

    final payload = {
      'role': simRole,
      'state': {
        'isJoined': !isLeaving,
        'isAudioOn': currentState.isLocalAudioOn,
        'isVideoOn': currentState.isLocalVideoOn,
        'isCameraFlipped': currentState.isLocalCameraFlipped,
      }
    };

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/rooms/$roomId/signal'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        
        final String remoteRole = simRole == 'member' ? 'trainer' : 'member';
        final remoteData = data[remoteRole] as Map<String, dynamic>?;

        if (remoteData != null) {
          final isRemoteJoined = remoteData['isJoined'] as bool? ?? false;
          final isRemoteAudioOn = remoteData['isAudioOn'] as bool? ?? true;
          final isRemoteVideoOn = remoteData['isVideoOn'] as bool? ?? true;
          final isRemoteCameraFlipped = remoteData['isCameraFlipped'] as bool? ?? false;

          final updatedState = _ref.read(hmsStateProvider);
          
          if (isRemoteJoined) {
            final remoteName = simRole == 'member' ? 'Aarav (Lead Trainer)' : 'DK';
            final peersList = [currentUser.role == UserRole.member ? 'DK' : 'Aarav (Lead Trainer)'];
            if (!peersList.contains(remoteName)) {
              peersList.add(remoteName);
            }

            _ref.read(hmsStateProvider.notifier).state = updatedState.copyWith(
              remoteParticipantName: remoteName,
              isRemoteAudioOn: isRemoteAudioOn,
              isRemoteVideoOn: isRemoteVideoOn,
              isRemoteCameraFlipped: isRemoteCameraFlipped,
              peers: peersList,
            );
          } else {
            final peersList = [currentUser.role == UserRole.member ? 'DK' : 'Aarav (Lead Trainer)'];
            _ref.read(hmsStateProvider.notifier).state = updatedState.copyWith(
              remoteParticipantName: null,
              isRemoteAudioOn: false,
              isRemoteVideoOn: false,
              isRemoteCameraFlipped: false,
              peers: peersList,
            );
          }
        }
      }
    } catch (e) {
      AppLogger.rtc('Simulated signaling sync failed: $e');
    }
  }

  Future<void> leaveCall() async {
    AppLogger.rtc('Leaving call');
    _simulationTimer?.cancel();
    _reconnectSimTimer?.cancel();
    _simSignalTimer?.cancel();

    if (!_isRealHMSUsed) {
      await _syncSimulatedState(isLeaving: true);
    }

    if (_isRealHMSUsed && _hmsSdk != null) {
      await _hmsSdk!.leave();
      _hmsSdk!.removeUpdateListener(listener: this);
      _hmsSdk = null;
    }

    _ref.read(hmsStateProvider.notifier).state = HMSState(isConnected: false);

    // Save Session Log automatically if we have start/end times
    if (_callStartTime != null && _activeCallRequestId != null) {
      final endTime = DateTime.now();
      final duration = endTime.difference(_callStartTime!).inSeconds;

      final request = getCallRequests().firstWhere((r) => r.id == _activeCallRequestId);
      final sessionLog = SessionLog(
        id: _activeCallRequestId!,
        memberId: request.memberId,
        trainerId: request.trainerId,
        startedAt: _callStartTime!,
        endedAt: endTime,
        durationSec: duration,
      );

      await _ref.read(syncServiceProvider).saveSessionLog(sessionLog);
      AppLogger.rtc('Session Log created: ${duration}s duration');

      _activeCallRequestId = null;
      _callStartTime = null;
    }
  }

  void toggleMic() {
    final state = _ref.read(hmsStateProvider);
    final nextState = !state.isLocalAudioOn;
    
    if (_isRealHMSUsed && _hmsSdk != null) {
      // Toggle real audio
      _hmsSdk!.switchAudio(isOn: nextState);
    }
    
    _ref.read(hmsStateProvider.notifier).state = state.copyWith(
      isLocalAudioOn: nextState,
    );
    AppLogger.rtc('Toggled microphone: $nextState');

    if (!_isRealHMSUsed) {
      _syncSimulatedState();
    }
  }

  void toggleVideo() {
    final state = _ref.read(hmsStateProvider);
    final nextState = !state.isLocalVideoOn;
    
    if (_isRealHMSUsed && _hmsSdk != null) {
      // Toggle real video
      _hmsSdk!.switchVideo(isOn: nextState);
    }
    
    _ref.read(hmsStateProvider.notifier).state = state.copyWith(
      isLocalVideoOn: nextState,
    );
    AppLogger.rtc('Toggled video: $nextState');

    if (!_isRealHMSUsed) {
      _syncSimulatedState();
    }
  }

  void flipCamera() {
    final state = _ref.read(hmsStateProvider);
    final nextState = !state.isLocalCameraFlipped;

    if (_isRealHMSUsed && _hmsSdk != null) {
      _hmsSdk!.switchCamera();
    }

    _ref.read(hmsStateProvider.notifier).state = state.copyWith(
      isLocalCameraFlipped: nextState,
    );
    AppLogger.rtc('Flipped camera to: ${nextState ? "Back" : "Front"}');

    if (!_isRealHMSUsed) {
      _syncSimulatedState();
    }
  }

  // --- HMSUpdateListener Override Methods ---
  @override
  void onJoin({required HMSRoom room}) {
    final remotePeers = room.peers?.where((p) => !p.isLocal).toList() ?? [];
    final remotePeer = remotePeers.isNotEmpty ? remotePeers.first : null;
    
    bool isRemoteVideoMuted = true;
    bool isRemoteAudioMuted = true;
    HMSVideoTrack? remoteTrack;
    if (remotePeer != null) {
      try {
        isRemoteVideoMuted = remotePeer.videoTrack?.isMute ?? true;
        remoteTrack = remotePeer.videoTrack;
      } catch (_) {}
      try {
        isRemoteAudioMuted = remotePeer.audioTrack?.isMute ?? true;
      } catch (_) {}
    }

    HMSPeer? localPeer;
    try {
      localPeer = room.peers?.firstWhere((p) => p.isLocal);
    } catch (_) {}
    HMSVideoTrack? localTrack;
    if (localPeer != null) {
      try {
        localTrack = localPeer.videoTrack;
      } catch (_) {}
    }

    _ref.read(hmsStateProvider.notifier).state = HMSState(
      isConnected: true,
      remoteParticipantName: remotePeer?.name,
      isRemoteVideoOn: !isRemoteVideoMuted,
      isRemoteAudioOn: !isRemoteAudioMuted,
      localVideoTrack: localTrack,
      remoteVideoTrack: remoteTrack,
      peers: room.peers?.map((p) => p.name).toList() ?? [],
    );
    AppLogger.rtc('Real HMS Room Join success: ${room.id}. Existing remote peer: ${remotePeer?.name}');
  }

  @override
  void onRoomUpdate({required HMSRoom room, required HMSRoomUpdate update}) {
    AppLogger.rtc('HMS Room Update: ${update.name}');
  }

  @override
  void onPeerUpdate({required HMSPeer peer, required HMSPeerUpdate update}) {
    AppLogger.rtc('HMS Peer Update: ${peer.name} (${update.name})');
    if (peer.isLocal) return; // Ignore local peer updates

    final currentState = _ref.read(hmsStateProvider);
    
    if (update == HMSPeerUpdate.peerJoined) {
      final peersList = List<String>.from(currentState.peers);
      if (!peersList.contains(peer.name)) {
        peersList.add(peer.name);
      }
      _ref.read(hmsStateProvider.notifier).state = currentState.copyWith(
        remoteParticipantName: peer.name,
        peers: peersList,
      );
    } else if (update == HMSPeerUpdate.peerLeft) {
      final peersList = List<String>.from(currentState.peers)..remove(peer.name);
      final isCurrentRemote = currentState.remoteParticipantName == peer.name;
      _ref.read(hmsStateProvider.notifier).state = currentState.copyWith(
        remoteParticipantName: isCurrentRemote ? null : currentState.remoteParticipantName,
        peers: peersList,
        clearRemoteTrack: isCurrentRemote,
        isRemoteVideoOn: isCurrentRemote ? false : currentState.isRemoteVideoOn,
        isRemoteAudioOn: isCurrentRemote ? false : currentState.isRemoteAudioOn,
      );
    }
  }

  @override
  void onTrackUpdate({
    required HMSTrack track,
    required HMSTrackUpdate trackUpdate,
    required HMSPeer peer,
  }) {
    final state = _ref.read(hmsStateProvider);
    final isTrackMuted = trackUpdate == HMSTrackUpdate.trackMuted || trackUpdate == HMSTrackUpdate.trackRemoved;

    if (track.kind == HMSTrackKind.kHMSTrackKindVideo) {
      final videoTrack = track as HMSVideoTrack;
      if (peer.isLocal) {
        _ref.read(hmsStateProvider.notifier).state = state.copyWith(
          isLocalVideoOn: !isTrackMuted,
          localVideoTrack: trackUpdate == HMSTrackUpdate.trackRemoved ? null : videoTrack,
          clearLocalTrack: trackUpdate == HMSTrackUpdate.trackRemoved,
        );
      } else {
        _ref.read(hmsStateProvider.notifier).state = state.copyWith(
          isRemoteVideoOn: !isTrackMuted,
          remoteVideoTrack: trackUpdate == HMSTrackUpdate.trackRemoved ? null : videoTrack,
          clearRemoteTrack: trackUpdate == HMSTrackUpdate.trackRemoved,
        );
      }
    } else if (track.kind == HMSTrackKind.kHMSTrackKindAudio) {
      if (peer.isLocal) {
        _ref.read(hmsStateProvider.notifier).state = state.copyWith(
          isLocalAudioOn: !isTrackMuted,
        );
      } else {
        _ref.read(hmsStateProvider.notifier).state = state.copyWith(
          isRemoteAudioOn: !isTrackMuted,
        );
      }
    }
  }

  @override
  void onHMSError({required HMSException error}) {
    AppLogger.rtc('HMS Error encountered: ${error.message}');
  }

  @override
  void onUpdateSpeakers({required List<HMSSpeaker> updateSpeakers}) {}
  
  @override
  void onReconnecting() {
    final state = _ref.read(hmsStateProvider);
    _ref.read(hmsStateProvider.notifier).state = state.copyWith(isReconnecting: true);
    AppLogger.rtc('HMS Connection re-connecting...');
  }

  @override
  void onReconnected() {
    final state = _ref.read(hmsStateProvider);
    _ref.read(hmsStateProvider.notifier).state = state.copyWith(
      isReconnecting: false,
      isConnected: true,
    );
    AppLogger.rtc('HMS Connection re-established');
  }

  @override
  void onSessionStoreAvailable({HMSSessionStore? hmsSessionStore}) {}

  @override
  void onAudioDeviceChanged({
    HMSAudioDevice? currentAudioDevice,
    List<HMSAudioDevice>? availableAudioDevice,
  }) {}

  @override
  void onChangeTrackStateRequest({
    required HMSTrackChangeRequest hmsTrackChangeRequest,
  }) {}

  @override
  void onMessage({required HMSMessage message}) {}

  @override
  void onPeerListUpdate({
    required List<HMSPeer> addedPeers,
    required List<HMSPeer> removedPeers,
  }) {}

  @override
  void onRemovedFromRoom({
    required HMSPeerRemovedFromPeer hmsPeerRemovedFromPeer,
  }) {}

  @override
  void onRoleChangeRequest({
    required HMSRoleChangeRequest roleChangeRequest,
  }) {}
}

final callServiceProvider = Provider<CallService>((ref) {
  return CallService(ref);
});

final hmsStateProvider = StateProvider<HMSState>((ref) => HMSState());

final callRequestsStreamProvider = StreamProvider<List<CallRequest>>((ref) {
  final callService = ref.watch(callServiceProvider);
  return callService.watchCallRequests();
});

final callRequestsProvider = Provider<List<CallRequest>>((ref) {
  final asyncReqs = ref.watch(callRequestsStreamProvider);
  return asyncReqs.maybeWhen(
    data: (list) => list,
    orElse: () => ref.read(callServiceProvider).getCallRequests(),
  );
});

// A provider that retrieves the single active approved upcoming call request (for join buttons)
final upcomingCallProvider = Provider<CallRequest?>((ref) {
  final requests = ref.watch(callRequestsProvider);
  final now = DateTime.now();

  try {
    return requests.firstWhere((r) {
      if (r.status != CallRequestStatus.approved) return false;
      
      final isToday = r.scheduledFor.year == now.year &&
          r.scheduledFor.month == now.month &&
          r.scheduledFor.day == now.day;
      return isToday;
    });
  } catch (_) {
    return null;
  }
});
