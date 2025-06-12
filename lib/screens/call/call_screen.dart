import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/callservice.dart';
import 'package:livekit_client/livekit_client.dart' as livekit;
import 'package:livekit_client/livekit_client.dart' show CancelListenFunc;
import 'package:firebase_database/firebase_database.dart';
import 'package:just_audio/just_audio.dart';

class CallScreen extends StatefulWidget {
  final String callId;
  final String userId;
  final bool isIncoming;
  final String type;

  const CallScreen({
    Key? key,
    required this.callId,
    required this.userId,
    required this.isIncoming,
    required this.type,
  }) : super(key: key);

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with WidgetsBindingObserver {
  final CallService _callService = CallService();
  livekit.Room? _room;
  livekit.LocalParticipant? _localParticipant;
  livekit.RemoteParticipant? _remoteParticipant;
  bool _isMicMuted = false;
  bool _isVideoEnabled = true;
  bool _isSpeakerOn = true;
  bool _isFrontCamera = true;
  int _callDuration = 0;
  Timer? _timer;
  late Timer _autoEndTimer;
  CancelListenFunc? _roomEventSub;
  bool _isDisposed = false;
  bool _isInitialized = false;
  late livekit.ConnectionState _currentConnectionState;
  static const Duration _callTimeout = Duration(minutes: 30);
  static const Duration _timerInterval = Duration(seconds: 1);
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  final AudioPlayer _callEndPlayer = AudioPlayer();
  bool _isRinging = false;

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentConnectionState = livekit.ConnectionState.disconnected;
    _autoEndTimer = Timer(_callTimeout, () {
      if (mounted) {
        _endCall();
      }
    });
    _initializeAudio();
    _initializeCall();
  }

  @override
  void dispose() {
    _cleanup();
    WidgetsBinding.instance.removeObserver(this);
    if (_isDisposed) return;
    _isDisposed = true;

    try {
      _timer?.cancel();
      _autoEndTimer?.cancel();
      _roomEventSub?.call();
      _ringtonePlayer.dispose();
      _callEndPlayer.dispose();
      if (_room != null) {
        _room!.disconnect();
      }
    } catch (e) {
      print("Error in dispose: $e");
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _localParticipant?.setCameraEnabled(false);
      _localParticipant?.setMicrophoneEnabled(false);
    } else if (state == AppLifecycleState.resumed) {
      if (_isVideoEnabled) {
        _localParticipant?.setCameraEnabled(true);
      }
      if (!_isMicMuted) {
        _localParticipant?.setMicrophoneEnabled(true);
      }
    }
  }

  void _handleConnectionState(livekit.ConnectionState state) {
    if (!mounted) return;

    switch (state) {
      case livekit.ConnectionState.disconnected:
        _showReconnectingDialog();
        break;
      case livekit.ConnectionState.connected:
        _hideReconnectingDialog();
        break;
      case livekit.ConnectionState.reconnecting:
        _showErrorDialog('Đang kết nối lại...');
        break;
      case livekit.ConnectionState.connecting:
        _showErrorDialog('Đang kết nối...');
        break;
    }
    setState(() {
      _currentConnectionState = state;
    });
  }

  Future<void> _initializeAudio() async {
    try {
      // Khởi tạo ringtone
      await _ringtonePlayer.setAsset('assets/sounds/ringtone.mp3');
      await _ringtonePlayer.setLoopMode(LoopMode.one);

      // Khởi tạo âm thanh kết thúc cuộc gọi
      await _callEndPlayer.setAsset('assets/sounds/call_end.mp3');
    } catch (e) {
      print('Error initializing audio: $e');
    }
  }

  Future<void> _startRinging() async {
    if (!_isRinging) {
      try {
        await _ringtonePlayer.play();
        setState(() => _isRinging = true);
      } catch (e) {
        print('Error playing ringtone: $e');
      }
    }
  }

  Future<void> _stopRinging() async {
    if (_isRinging) {
      try {
        await _ringtonePlayer.stop();
        setState(() => _isRinging = false);
      } catch (e) {
        print('Error stopping ringtone: $e');
      }
    }
  }

  Future<void> _playCallEndSound() async {
    try {
      await _callEndPlayer.play();
    } catch (e) {
      print('Error playing call end sound: $e');
    }
  }

  Future<void> _initializeCall() async {
    try {
      final callSnapshot =
          await FirebaseDatabase.instance.ref('calls/${widget.callId}').get();

      if (!callSnapshot.exists) {
        _endCall();
        return;
      }

      final callData = callSnapshot.value as Map<dynamic, dynamic>;
      final roomId = callData['roomId'] as String;

      // Bắt đầu phát ringtone nếu là cuộc gọi đến
      if (widget.isIncoming) {
        await _startRinging();
      }

      // Khởi tạo LiveKit room
      final room = await _initializeLiveKit(roomId);

      setState(() {
        _room = room;
        _localParticipant = room.localParticipant;
        _isInitialized = true;
      });

      _startTimers();
    } catch (e) {
      print('Error initializing call: $e');
      _showErrorDialog('Failed to initialize call');
    }
  }

  Future<livekit.Room> _initializeLiveKit(String roomId) async {
    try {
      final token = await _callService.getLiveKitToken(roomId, widget.userId);
      final room = livekit.Room();

      // Lắng nghe sự kiện Room
      _roomEventSub = room.events.listen((event) {
        print('LiveKit event: [33m[1m[4m[7m${event.runtimeType}[0m');
        // Cập nhật connection state
        _handleConnectionState(room.connectionState);
        // Cập nhật remote participant (nếu có)
        if (_room != null) {
          final remoteParticipants = _room!.remoteParticipants;
          setState(() {
            _remoteParticipant =
                remoteParticipants.values.isNotEmpty
                    ? remoteParticipants.values.first
                    : null;
          });
        }
      });

      await room.connect(
        'wss://call-bwzw70v1.livekit.cloud',
        token,
        roomOptions: livekit.RoomOptions(adaptiveStream: true, dynacast: true),
      );

      // Thiết lập video track với camera trước
      final localVideoTrack = await livekit.LocalVideoTrack.createCameraTrack();

      // Thiết lập audio track
      final localAudioTrack = await livekit.LocalAudioTrack.create();

      // Publish tracks
      await room.localParticipant?.publishVideoTrack(localVideoTrack);
      await room.localParticipant?.publishAudioTrack(localAudioTrack);

      return room;
    } catch (e) {
      print('Error initializing LiveKit: $e');
      throw Exception('Failed to initialize LiveKit');
    }
  }

  void _startTimers() {
    _timer = Timer.periodic(_timerInterval, (_) {
      if (!_isDisposed) {
        setState(() => _callDuration++);
      }
    });
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Error'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('OK'),
              ),
            ],
          ),
    );
  }

  Widget _buildConnectionStateIndicator() {
    String message;
    Color color;

    switch (_currentConnectionState) {
      case livekit.ConnectionState.connecting:
        message = 'Đang kết nối...';
        color = Colors.orange;
        break;
      case livekit.ConnectionState.connected:
        message = 'Đã kết nối';
        color = Colors.green;
        break;
      case livekit.ConnectionState.reconnecting:
        message = 'Đang kết nối lại...';
        color = Colors.orange;
        break;
      case livekit.ConnectionState.disconnected:
        message = 'Mất kết nối';
        color = Colors.red;
        break;
      // default:
      //   message = '';
      //   color = Colors.transparent;
    }

    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      color: color,
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Text(message, style: TextStyle(color: Colors.white)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Video views
            if (_isInitialized) ...[
              // Remote video
              if (_remoteParticipant != null)
                _buildRemoteVideoView(_remoteParticipant!),

              // Local video
              _buildLocalVideoView(),
            ],

            // Connection state indicator
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildConnectionStateIndicator(),
            ),

            // Controls
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
                    icon: _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                    onPressed: _toggleVideo,
                  ),
                  _buildControlButton(
                    icon: Icons.switch_camera,
                    onPressed: _switchCamera,
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
                    backgroundImage: NetworkImage(widget.userId),
                  ),
                  SizedBox(height: 8),
                  Text(
                    widget.userId,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 20),
                  Text(
                    _formatDuration(_callDuration),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteVideoView(livekit.RemoteParticipant participant) {
    try {
      final videoTrackPub = participant.videoTrackPublications.firstWhere(
        (pub) => pub.track != null,
      );
      final videoTrack = videoTrackPub.track as livekit.VideoTrack;
      return Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        child: livekit.VideoTrackRenderer(videoTrack),
      );
    } catch (e) {
      print('Error building remote video view: $e');
      return const SizedBox.shrink();
    }
  }

  Widget _buildLocalVideoView() {
    try {
      if (_localParticipant == null) return const SizedBox.shrink();
      final videoTrackPub = _localParticipant!.videoTrackPublications
          .firstWhere((pub) => pub.track != null);
      final videoTrack = videoTrackPub.track as livekit.VideoTrack;
      return Positioned(
        right: 20,
        top: 20,
        width: 120,
        height: 160,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: livekit.VideoTrackRenderer(videoTrack),
          ),
        ),
      );
    } catch (e) {
      print('Error building local video view: $e');
      return const SizedBox.shrink();
    }
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

  void _toggleMic() {
    setState(() => _isMicMuted = !_isMicMuted);
    _localParticipant?.setMicrophoneEnabled(!_isMicMuted);
  }

  void _toggleVideo() {
    setState(() => _isVideoEnabled = !_isVideoEnabled);
    _localParticipant?.setCameraEnabled(_isVideoEnabled);
  }

  void _toggleSpeaker() async {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    // LiveKit Flutter chưa hỗ trợ chuyển loa trực tiếp, cần dùng package ngoài nếu muốn
  }

  Future<void> _endCall() async {
    try {
      await _stopRinging();
      await _playCallEndSound();
      await _callService.updateCallStatus(widget.callId, 'ended');
      await _room!.disconnect();
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      print('Error ending call: $e');
      _showErrorDialog('Failed to end call properly');
    }
  }

  void _showReconnectingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Text('Reconnecting'),
            content: Text('Attempting to reconnect to the call...'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _endCall();
                },
                child: Text('End Call'),
              ),
            ],
          ),
    );
  }

  void _hideReconnectingDialog() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _cleanup() async {
    try {
      await _stopRinging();
      if (_room != null) {
        if (_localParticipant != null) {
          await _localParticipant!.unpublishAllTracks();
        }
        await _room!.disconnect();
        await _callService.handleCallEnded(widget.callId);
        _roomEventSub?.call();
      }
    } catch (e) {
      print('Error during cleanup: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_localParticipant == null) return;

    try {
      // Unpublish video track hiện tại
      await _localParticipant!.unpublishAllTracks();

      // Tạo video track mới với camera ngược lại
      final newVideoTrack = await livekit.LocalVideoTrack.createCameraTrack();

      // Publish video track mới
      await _localParticipant!.publishVideoTrack(newVideoTrack);

      setState(() {
        _isFrontCamera = !_isFrontCamera;
      });
    } catch (e) {
      print('Error switching camera: $e');
      _showErrorDialog('Failed to switch camera');
    }
  }
}
