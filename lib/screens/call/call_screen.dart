import 'package:flutter/material.dart';
import 'dart:async'; // Import for Timer
import '../../services/signaling.dart'; // Import lớp Signaling
import '../../services/audio_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_database/firebase_database.dart';

class CallScreen extends StatefulWidget {
  final String friendId;
  final String friendName;
  final String friendAvatarUrl;
  final String appointmentId; // Thêm appointmentId
  final bool isIncomingCall;

  const CallScreen({
    super.key,
    required this.friendId,
    required this.friendName,
    required this.friendAvatarUrl,
    required this.appointmentId, // Truyền appointmentId
    this.isIncomingCall = false,
  });

  @override
  _CallScreenState createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  // final Signaling _signaling = Signaling();
  late Timer _timer;
  late Timer _autoEndTimer;
  late StreamSubscription _callSubscription;
  int _callDuration = 0;
  bool _isCallAccepted = false; // Trạng thái cuộc gọi
  final Signaling _signaling = Signaling();
  final AudioService _audioService = AudioService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isMicMuted = false;
  bool _isVideoEnabled = true;
  bool _isSpeakerOn = true;
  late StreamSubscription _callStateSubscription;
  bool _isDisposed = false;
  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _setupLocalStream();
    _setupCallStateListener();
    _setupAutoEndTimer();
    _setupCallListener();
  }

  void _setupAutoEndTimer() {
    if (!widget.isIncomingCall) {
      _autoEndTimer = Timer(Duration(minutes: 1), () {
        if (!_isCallAccepted && mounted) {
          _endCall();
        }
      });
    }
  }

  void _setupLocalStream() async {
    try {
      // Tắt stream cũ nếu có
      if (_localRenderer.srcObject != null) {
        final localStream = _localRenderer.srcObject as MediaStream;
        localStream.getTracks().forEach((track) {
          track.stop();
          track.enabled = false;
        });
      }

      // Khởi tạo stream mới với camera và microphone
      final Map<String, dynamic> mediaConstraints = {
        'audio': true,
        'video': {
          'facingMode': 'user', // Sử dụng camera trước
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
      };

      MediaStream stream = await navigator.mediaDevices.getUserMedia(
        mediaConstraints,
      );

      // Gán stream vào renderer để hiển thị
      _localRenderer.srcObject = stream;

      // Cập nhật state để rebuild UI
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error setting up local stream: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể khởi tạo camera: $e')));
    }
  }

  void _setupCallListener() {
    FirebaseDatabase.instance
        .ref('calls/${widget.appointmentId}')
        .onValue
        .listen((event) {
          if (!mounted) return;

          if (event.snapshot.value == null) {
            Navigator.pop(context);
            return;
          }

          final data = event.snapshot.value as Map<dynamic, dynamic>;
          if (data['status'] == 'ended') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Cuộc gọi đã kết thúc")),
            );
            _cleanupAndExit();
          } else if (data['status'] == 'accepted' && !_isCallAccepted) {
            setState(() {
              _isCallAccepted = true;
            });
            _startCallTimer();
            _audioService.stopRingtone();
          }
        });
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (widget.isIncomingCall) {
      _audioService.playRingtone();
    }
  }

  void _setupCallStateListener() {
    _callStateSubscription = _signaling.callStateStream.listen((state) {
      switch (state['event']) {
        case 'call_accepted':
          setState(() {
            _remoteRenderer.srcObject = state['remoteStream'];
          });
          break;
        case 'call_ended':
          Navigator.pop(context);
          break;
        case 'error':
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state['message'])));
          Navigator.pop(context);
          break;
      }
    });
  }

  void _startCallTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _callDuration++;
      });
    });
  }

  void _cleanupAndExit() {
    if (_isDisposed) return;

    try {
      _timer.cancel();
      _autoEndTimer.cancel();
      _callStateSubscription.cancel();
      _audioService.stopRingtone();
      _signaling.endCall();

      // Tắt local stream
      if (_localRenderer.srcObject != null) {
        final localStream = _localRenderer.srcObject as MediaStream;
        localStream.getTracks().forEach((track) {
          track.stop();
          track.enabled = false;
        });
        _localRenderer.srcObject = null;
      }

      // Tắt remote stream
      if (_remoteRenderer.srcObject != null) {
        final remoteStream = _remoteRenderer.srcObject as MediaStream;
        remoteStream.getTracks().forEach((track) {
          track.stop();
          track.enabled = false;
        });
        _remoteRenderer.srcObject = null;
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      print("Error in cleanup: $e");
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Nếu cuộc gọi đã được chấp nhận, hiển thị giao diện video call hiện tại
    if (_isCallAccepted) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              // Giữ nguyên phần code hiển thị video call
              RTCVideoView(
                _remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),

              // Local camera view (small frame)
              Positioned(
                top: 20,
                right: 20,
                child: Container(
                  width: 120,
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),

              // Controls overlay
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildControlButton(
                      icon: _isMicMuted ? Icons.mic_off : Icons.mic,
                      onPressed: _toggleMic,
                    ),
                    _buildControlButton(
                      icon: Icons.call_end,
                      backgroundColor: Colors.red,
                      onPressed: _endCall,
                    ),
                    _buildControlButton(
                      icon:
                          _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                      onPressed: _toggleVideo,
                    ),
                    _buildControlButton(
                      icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                      onPressed: _toggleSpeaker,
                    ),
                  ],
                ),
              ),

              // Caller info
              Positioned(
                top: 20,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundImage: NetworkImage(widget.friendAvatarUrl),
                    ),
                    SizedBox(height: 8),
                    Text(
                      widget.friendName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Call duration timer
              if (_isCallAccepted)
                Positioned(
                  top: 80,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      _formatDuration(_callDuration),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // Giao diện màn hình đang gọi mới (khi chưa được chấp nhận)
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 60),
            // Avatar của người dùng
            CircleAvatar(
              radius: 50,
              backgroundImage: NetworkImage(widget.friendAvatarUrl),
            ),
            const SizedBox(height: 24),
            // Text "Đang gọi..."
            const Text(
              "Đang gọi...",
              style: TextStyle(color: Colors.white70, fontSize: 24),
            ),
            const SizedBox(height: 16),
            // Chỉ hiển thị tên người dùng
            Text(
              widget.friendName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            // Các nút điều khiển
            Container(
              margin: const EdgeInsets.only(bottom: 50),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildCallButton(
                    icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                    label: 'Loa ngoài',
                    onPressed: _toggleSpeaker,
                  ),
                  _buildCallButton(
                    icon: Icons.videocam,
                    label: 'FaceTime',
                    onPressed: _toggleVideo,
                  ),
                  _buildCallButton(
                    icon: _isMicMuted ? Icons.mic_off : Icons.mic,
                    label: 'Tắt tiếng',
                    onPressed: _toggleMic,
                  ),
                ],
              ),
            ),
            // Nút kết thúc cuộc gọi
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: GestureDetector(
                onTap: _endCall,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.call_end,
                    color: Colors.white,
                    size: 35,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    Color? backgroundColor,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor ?? Colors.white.withOpacity(0.3),
      ),
      child: IconButton(
        icon: Icon(icon),
        color: Colors.white,
        iconSize: 30,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildCallButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.grey[800],
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(icon),
            color: Colors.white,
            iconSize: 30,
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }

  void _toggleMic() {
    setState(() => _isMicMuted = !_isMicMuted);
    _localRenderer.srcObject?.getAudioTracks().forEach((track) {
      track.enabled = !_isMicMuted;
    });
  }

  void _toggleVideo() {
    setState(() => _isVideoEnabled = !_isVideoEnabled);
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
  }

  Future<void> _endCall() async {
    if (_isDisposed) return;

    try {
      // Cập nhật trạng thái cuộc gọi
      await FirebaseDatabase.instance
          .ref('calls/${widget.appointmentId}')
          .update({'status': 'ended'});

      _cleanupAndExit();
    } catch (e) {
      print("Error ending call: $e");
      _cleanupAndExit();
    }
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    try {
      _timer.cancel();
      _autoEndTimer.cancel();
      _callStateSubscription.cancel();
      _audioService.stopRingtone();
      _signaling.endCall();

      // Tắt local stream
      if (_localRenderer.srcObject != null) {
        final localStream = _localRenderer.srcObject as MediaStream;
        localStream.getTracks().forEach((track) {
          track.stop();
          track.enabled = false;
        });
        _localRenderer.srcObject = null;
      }

      // Tắt remote stream
      if (_remoteRenderer.srcObject != null) {
        final remoteStream = _remoteRenderer.srcObject as MediaStream;
        remoteStream.getTracks().forEach((track) {
          track.stop();
          track.enabled = false;
        });
        _remoteRenderer.srcObject = null;
      }

      _remoteRenderer.dispose();
      _localRenderer.dispose();
    } catch (e) {
      print("Error in dispose: $e");
    }

    super.dispose();
  }
}
