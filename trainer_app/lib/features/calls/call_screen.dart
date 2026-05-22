import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';
import 'package:hmssdk_flutter/hmssdk_flutter.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String requestId;
  const CallScreen({super.key, required this.requestId});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  bool _hasJoined = false;
  bool _isConnecting = false;
  bool _showPostCall = false;

  // Pre-join toggle states
  bool _micOn = true;
  bool _camOn = true;

  // Post-call notes state
  final TextEditingController _notesController = TextEditingController();
  late DateTime _startTime;
  int _finalDurationSec = 0;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _joinCall() async {
    setState(() {
      _isConnecting = true;
    });

    try {
      final callService = ref.read(callServiceProvider);
      
      final hmsState = ref.read(hmsStateProvider);
      ref.read(hmsStateProvider.notifier).state = hmsState.copyWith(
        isLocalAudioOn: _micOn,
        isLocalVideoOn: _camOn,
      );

      _startTime = DateTime.now();
      await callService.joinCall(widget.requestId);

      setState(() {
        _hasJoined = true;
        _isConnecting = false;
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to join call: $e')),
        );
      }
    }
  }

  Future<void> _leaveAndShowFeedback() async {
    final endTime = DateTime.now();
    _finalDurationSec = endTime.difference(_startTime).inSeconds;

    try {
      await ref.read(callServiceProvider).leaveCall();
    } catch (_) {}

    setState(() {
      _hasJoined = false;
      _showPostCall = true;
    });
  }

  Future<void> _submitNotes() async {
    await ref.read(logServiceProvider).submitTrainerFeedback(
      widget.requestId,
      _notesController.text.trim(),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session notes saved. Call completed.'),
          backgroundColor: AppColors.success,
        ),
      );
      context.go('/'); // Back to dashboard
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showPostCall) {
      return _buildPostCallFeedback();
    }

    if (!_hasJoined) {
      return _buildPreJoinCheck();
    }

    return _buildInCallView();
  }

  Widget _buildPreJoinCheck() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pre-Join Device Check'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Ready to join? Check mic and camera.',
                style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Trainer Role Auto-Mapped',
                style: TextStyle(fontSize: 13.0, color: AppColors.trainerPrimary, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              
              // Device preview block
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary,
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16.0),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_camOn)
                          Container(
                            color: Colors.grey.shade900,
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.videocam, size: 64, color: Colors.white70),
                                SizedBox(height: 12),
                                Text('Camera Active (Preview)', style: TextStyle(color: Colors.white70)),
                              ],
                            ),
                          )
                        else
                          const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.videocam_off, size: 64, color: Colors.white38),
                              SizedBox(height: 12),
                              Text('Camera Muted', style: TextStyle(color: Colors.white38)),
                            ],
                          ),
                        
                        Positioned(
                          top: 16,
                          right: 16,
                          child: Icon(
                            _micOn ? Icons.mic : Icons.mic_off,
                            color: _micOn ? AppColors.success : AppColors.error,
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton(
                    heroTag: 'trainer_mic_toggle',
                    onPressed: () {
                      setState(() {
                        _micOn = !_micOn;
                      });
                    },
                    backgroundColor: _micOn ? AppColors.surface : AppColors.error,
                    foregroundColor: _micOn ? AppColors.textPrimary : Colors.white,
                    child: Icon(_micOn ? Icons.mic : Icons.mic_off),
                  ),
                  const SizedBox(width: 24),
                  FloatingActionButton(
                    heroTag: 'trainer_cam_toggle',
                    onPressed: () {
                      setState(() {
                        _camOn = !_camOn;
                      });
                    },
                    backgroundColor: _camOn ? AppColors.surface : AppColors.error,
                    foregroundColor: _camOn ? AppColors.textPrimary : Colors.white,
                    child: Icon(_camOn ? Icons.videocam : Icons.videocam_off),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _isConnecting ? null : _joinCall,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.trainerPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                ),
                child: _isConnecting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Join Call'),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInCallView() {
    final hmsState = ref.watch(hmsStateProvider);
    final callService = ref.read(callServiceProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // 1. Remote participant (Member - DK)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (hmsState.isRemoteVideoOn && hmsState.remoteParticipantName != null)
                          if (callService.isRealHMSUsed && hmsState.remoteVideoTrack != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16.0),
                              child: HMSVideoView(
                                track: hmsState.remoteVideoTrack!,
                                key: Key(hmsState.remoteVideoTrack!.trackId),
                                scaleType: ScaleType.SCALE_ASPECT_FILL,
                              ),
                            )
                          else
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.person, size: 64, color: Colors.white70),
                                  const SizedBox(height: 8),
                                  Text(
                                    hmsState.isRemoteCameraFlipped
                                        ? 'Member Stream Active (Back Camera)'
                                        : 'Member Stream Active (Front Camera)',
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                ],
                              ),
                            )
                        else
                          const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.videocam_off, size: 64, color: Colors.white30),
                                SizedBox(height: 8),
                                Text('Member Video Muted', style: TextStyle(color: Colors.white30)),
                              ],
                            ),
                          ),
                        Positioned(
                          bottom: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            child: Text(
                              hmsState.remoteParticipantName ?? 'DK (Waiting...)',
                              style: const TextStyle(color: Colors.white, fontSize: 12.0),
                            ),
                          ),
                        ),
                        
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Icon(
                            hmsState.isRemoteAudioOn ? Icons.volume_up : Icons.volume_off,
                            color: Colors.white54,
                            size: 20,
                          ),
                        )
                      ],
                    ),
                  ),
                ),

                // 2. Local participant (Trainer - Aarav)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (hmsState.isLocalVideoOn)
                          if (callService.isRealHMSUsed && hmsState.localVideoTrack != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16.0),
                              child: HMSVideoView(
                                track: hmsState.localVideoTrack!,
                                key: Key(hmsState.localVideoTrack!.trackId),
                                scaleType: ScaleType.SCALE_ASPECT_FILL,
                                setMirror: true,
                              ),
                            )
                          else
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.person_outline, size: 64, color: Colors.white70),
                                  const SizedBox(height: 8),
                                  Text(
                                    hmsState.isLocalCameraFlipped
                                        ? 'My Video Stream Active (Back Camera)'
                                        : 'My Video Stream Active (Front Camera)',
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                ],
                              ),
                            )
                        else
                          const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.videocam_off, size: 64, color: Colors.white30),
                                SizedBox(height: 8),
                                Text('Video Off', style: TextStyle(color: Colors.white30)),
                              ],
                            ),
                          ),
                        Positioned(
                          bottom: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            child: const Text(
                              'Aarav (You)',
                              style: TextStyle(color: Colors.white, fontSize: 12.0),
                            ),
                          ),
                        ),
                        
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Icon(
                            hmsState.isLocalAudioOn ? Icons.mic : Icons.mic_off,
                            color: hmsState.isLocalAudioOn ? AppColors.success : AppColors.error,
                            size: 20,
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Call Toolbar (Overlay at Bottom)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton(
                    heroTag: 'trainer_call_mic',
                    onPressed: () => ref.read(callServiceProvider).toggleMic(),
                    backgroundColor: hmsState.isLocalAudioOn ? Colors.grey.shade800 : AppColors.error,
                    foregroundColor: Colors.white,
                    child: Icon(hmsState.isLocalAudioOn ? Icons.mic : Icons.mic_off),
                  ),
                  const SizedBox(width: 16),
                  FloatingActionButton(
                    heroTag: 'trainer_call_video',
                    onPressed: () => ref.read(callServiceProvider).toggleVideo(),
                    backgroundColor: hmsState.isLocalVideoOn ? Colors.grey.shade800 : AppColors.error,
                    foregroundColor: Colors.white,
                    child: Icon(hmsState.isLocalVideoOn ? Icons.videocam : Icons.videocam_off),
                  ),
                  const SizedBox(width: 16),
                  FloatingActionButton(
                    heroTag: 'trainer_call_flip',
                    onPressed: () => ref.read(callServiceProvider).flipCamera(),
                    backgroundColor: hmsState.isLocalCameraFlipped ? AppColors.trainerPrimary : Colors.grey.shade800,
                    foregroundColor: Colors.white,
                    child: const Icon(Icons.flip_camera_ios),
                  ),
                  const SizedBox(width: 24),
                  FloatingActionButton(
                    heroTag: 'trainer_call_end',
                    onPressed: _leaveAndShowFeedback,
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    child: const Icon(Icons.call_end),
                  ),
                ],
              ),
            ),

            if (hmsState.isReconnecting)
              Container(
                color: Colors.black.withOpacity(0.7),
                alignment: Alignment.center,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppColors.trainerPrimary),
                    SizedBox(height: 16),
                    Text(
                      'Reconnecting...',
                      style: TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.bold),
                    )
                  ],
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildPostCallFeedback() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Session Notes'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.rate_review_outlined,
                size: 80,
                color: AppColors.trainerPrimary,
              ),
              const SizedBox(height: 24),
              const Text(
                'Complete Trainer Session Log',
                style: TextStyle(fontSize: 22.0, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Duration: ${_finalDurationSec ~/ 60}m ${_finalDurationSec % 60}s',
                style: const TextStyle(fontSize: 14.0, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              
              const Text(
                'Write Workout/Macros Feedback Notes',
                style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'e.g. DK did great today. Macros reviewed: recommended 180g protein. Added dumbbell curls to list.',
                ),
              ),
              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _submitNotes,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.trainerPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                ),
                child: const Text('Mark as complete & save'),
              )
            ],
          ),
        ),
      ),
    );
  }
}
