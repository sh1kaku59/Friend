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
  final String remoteParticipantName;
  final String remoteParticipantAvatar;

  const CallScreen({
    Key? key,
    required this.callId,
    required this.userId,
    required this.isIncoming,
    required this.type,
    required this.remoteParticipantName,
    required this.remoteParticipantAvatar,
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
  static int _retryCount = 0;
  static const maxRetries = 3;
  StreamSubscription? _firebaseCallStateSubscription;

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
        print('DEBUG: _autoEndTimer triggered. Ending call.');
        _endCall(reason: "Call duration timeout");
      }
    });
    _initializeAudio();
    _initializeCall();
    _listenToFirebaseCallStatus();
  }

  @override
  void dispose() {
    print('DEBUG: CallScreen dispose() called for CallId: ${widget.callId}.');
    _firebaseCallStateSubscription?.cancel();
    _cleanup();
    WidgetsBinding.instance.removeObserver(this);
    if (_isDisposed) return;
    _isDisposed = true;

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
    if (!mounted) {
      print('DEBUG: _handleConnectionState called but widget not mounted.');
      return;
    }

    switch (state) {
      case livekit.ConnectionState.disconnected:
        print(
          'DEBUG: Connection state: Disconnected for CallId: ${widget.callId}',
        );
        _showReconnectingDialog();
        if (_retryCount < maxRetries) {
          _retryCount++;
          print('DEBUG: Attempting to reconnect, retry count: $_retryCount');
          _reconnectToCall();
        } else {
          _handleError(
            'Không thể kết nối lại sau nhiều lần thử',
            shouldEndCall: true,
          );
          _endCall(reason: "Max reconnect retries reached");
        }
        break;
      case livekit.ConnectionState.connected:
        print(
          'DEBUG: Connection state: Connected for CallId: ${widget.callId}',
        );
        _hideReconnectingDialog();
        _retryCount = 0; // Reset retry count khi kết nối thành công
        break;
      case livekit.ConnectionState.reconnecting:
        print(
          'DEBUG: Connection state: Reconnecting for CallId: ${widget.callId}',
        );
        _showErrorDialog('Đang kết nối lại...');
        break;
      case livekit.ConnectionState.connecting:
        print(
          'DEBUG: Connection state: Connecting for CallId: ${widget.callId}',
        );
        _showErrorDialog('Đang kết nối...');
        break;
    }

    if (mounted) {
      setState(() {
        _currentConnectionState = state;
      });
    }
  }

  Future<void> _reconnectToCall() async {
    print('DEBUG: _reconnectToCall called for CallId: ${widget.callId}.');
    try {
      final callSnapshot =
          await FirebaseDatabase.instance.ref('calls/${widget.callId}').get();
      if (!callSnapshot.exists) {
        print(
          'DEBUG: Call entry not found in Firebase during reconnection. Ending call. CallId: ${widget.callId}',
        );
        if (mounted) {
          _endCall(reason: "Firebase call entry not found during reconnect");
        }
        return;
      }

      final callData = callSnapshot.value as Map<dynamic, dynamic>;
      final roomId = callData['roomId'] as String;

      final token = await _callService.getLiveKitToken(roomId, widget.userId);
      print(
        'DEBUG: New token obtained for reconnection for CallId: ${widget.callId}',
      );

      final newRoom = livekit.Room();

      _roomEventSub?.call(); // Hủy đăng ký sự kiện cũ
      _roomEventSub = newRoom.events.listen((event) {
        print(
          'DEBUG: New Room LiveKit event: ${event.runtimeType} for CallId: ${widget.callId}',
        );
        if (!mounted) {
          print(
            'DEBUG: New Room LiveKit event listener called but widget not mounted. CallId: ${widget.callId}',
          );
          return;
        }
        _handleConnectionState(newRoom.connectionState);

        if (mounted) {
          final remoteParticipants = newRoom.remoteParticipants;
          setState(() {
            _remoteParticipant =
                remoteParticipants.values.isNotEmpty
                    ? remoteParticipants.values.first
                    : null;
          });
        }
      });

      await newRoom.connect(
        'wss://call-bwzw70v1.livekit.cloud',
        token,
        roomOptions: livekit.RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          stopLocalTrackOnUnpublish: true,
        ),
      );
      print(
        'DEBUG: New room connected successfully for CallId: ${widget.callId}.',
      );

      final localVideoTrack = await livekit.LocalVideoTrack.createCameraTrack();
      final localAudioTrack = await livekit.LocalAudioTrack.create();
      print('DEBUG: Local tracks created for CallId: ${widget.callId}.');

      await newRoom.localParticipant?.publishVideoTrack(localVideoTrack);
      await newRoom.localParticipant?.publishAudioTrack(localAudioTrack);
      print('DEBUG: Local tracks published for CallId: ${widget.callId}.');

      if (mounted) {
        setState(() {
          _room = newRoom;
          _localParticipant = newRoom.localParticipant;
        });
        print(
          'DEBUG: _room and _localParticipant updated in state for CallId: ${widget.callId}.',
        );
      }
    } catch (e) {
      print(
        'ERROR: Error in _reconnectToCall for CallId: ${widget.callId}: $e',
      );
      if (mounted) {
        _showErrorDialog('Failed to reconnect to call');
        _endCall(reason: "Failed to reconnect LiveKit");
      }
    }
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
        if (mounted) {
          _endCall(reason: "Initial Firebase call entry not found");
        }
        return;
      }

      final callData = callSnapshot.value as Map<dynamic, dynamic>;
      final roomId = callData['roomId'] as String;

      if (widget.isIncoming) {
        await _startRinging();
      }

      final room = await _initializeLiveKit(roomId);

      if (mounted) {
        setState(() {
          _room = room;
          _localParticipant = room.localParticipant;
          _isInitialized = true;
        });
        _startTimers();
      }
    } catch (e) {
      print('Error initializing call: $e');
      if (mounted) {
        _showErrorDialog('Failed to initialize call');
        _endCall(reason: "Failed to initialize call setup");
      }
    }
  }

  Future<livekit.Room> _initializeLiveKit(String roomId) async {
    print(
      'DEBUG: _initializeLiveKit called for roomId: $roomId, userId: ${widget.userId}.',
    );
    try {
      final token = await _callService.getLiveKitToken(roomId, widget.userId);
      print(
        'DEBUG: Token received for LiveKit initialization for roomId: $roomId.',
      );
      final room = livekit.Room();

      _roomEventSub = room.events.listen((event) {
        print('DEBUG: LiveKit event: ${event.runtimeType} for roomId: $roomId');

        if (!mounted) {
          print(
            'DEBUG: LiveKit event listener called but widget not mounted for roomId: $roomId.',
          );
          return;
        }

        _handleConnectionState(room.connectionState);

        if (_room != null && mounted) {
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
        roomOptions: livekit.RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          stopLocalTrackOnUnpublish: true,
        ),
      );
      print('DEBUG: LiveKit room connected successfully for roomId: $roomId.');

      final localVideoTrack = await livekit.LocalVideoTrack.createCameraTrack();
      final localAudioTrack = await livekit.LocalAudioTrack.create();
      print('DEBUG: Local video and audio tracks created for roomId: $roomId.');

      await room.localParticipant?.publishVideoTrack(localVideoTrack);
      await room.localParticipant?.publishAudioTrack(localAudioTrack);
      print('DEBUG: Local tracks published for roomId: $roomId.');

      return room;
    } catch (e) {
      print('ERROR: Error initializing LiveKit for roomId: $roomId: $e');
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
                    onPressed:
                        () => _endCall(reason: "User ended call manually"),
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
                    child: ClipOval(
                      child: Image.network(
                        widget.remoteParticipantAvatar,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          print(
                            'Error loading avatar for ${widget.remoteParticipantName}: $error',
                          );
                          return Image.asset(
                            'assets/default_avatar.png',
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          );
                        },
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    widget.remoteParticipantName,
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

  Future<void> _endCall({String reason = "Unknown"}) async {
    print(
      'DEBUG: _endCall called for CallId: ${widget.callId}. Reason: $reason',
    );
    try {
      await _stopRinging();
      await _playCallEndSound();
      await _updateCallStatus('ended');
      await _callService.updateCallStatus(widget.callId, 'ended');
      print(
        'DEBUG: Call status updated to "ended" in Firebase for CallId: ${widget.callId}.',
      );
      if (_room != null) {
        await _room!.disconnect();
        print(
          'DEBUG: LiveKit room disconnected in _endCall for CallId: ${widget.callId}.',
        );
      }
      if (mounted) {
        Navigator.pop(context);
        print('DEBUG: Popped CallScreen for CallId: ${widget.callId}.');
      }
    } catch (e) {
      print('ERROR: Error ending call for CallId: ${widget.callId}: $e');
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

  void _handleError(String message, {bool shouldEndCall = false}) {
    print('Call error: $message');
    if (mounted) {
      _showErrorDialog(message);
      if (shouldEndCall) {
        _endCall();
      }
    }
  }

  Future<void> _cleanup() async {
    print('DEBUG: _cleanup called.');
    try {
      if (!mounted) {
        print('DEBUG: _cleanup called but widget not mounted.');
        return;
      }

      // Dừng tất cả các timer
      _timer?.cancel();
      _autoEndTimer.cancel();
      print('DEBUG: Timers cancelled in _cleanup.');

      // Dừng âm thanh
      await _stopRinging();
      print('DEBUG: Ringtone stopped in _cleanup.');

      // Hủy đăng ký sự kiện
      _roomEventSub?.call();
      print('DEBUG: Room event subscription cancelled in _cleanup.');

      if (_room != null) {
        // Unpublish tất cả tracks
        if (_localParticipant != null) {
          await _localParticipant!.unpublishAllTracks();
          print('DEBUG: Local tracks unpublished in _cleanup.');
        }

        // Ngắt kết nối room
        // Lưu ý: _endCall đã gọi disconnect, nên có thể bỏ qua dòng này nếu cleanup được gọi sau _endCall
        // Tuy nhiên, để an toàn, chúng ta vẫn giữ nó.
        await _room!.disconnect();
        print('DEBUG: LiveKit room disconnected in _cleanup.');

        // Cập nhật trạng thái cuộc gọi
        // _endCall đã xử lý việc này, nên có thể bỏ qua nếu _cleanup được gọi sau _endCall.
        // Nếu _cleanup được gọi độc lập (ví dụ: do dispose), thì cần giữ lại.
        // Để tránh trùng lặp, chúng ta sẽ để _endCall xử lý chính việc này.
        // await _callService.handleCallEnded(widget.callId); // Tạm thời bỏ qua để tránh trùng lặp log/cập nhật
      }
    } catch (e) {
      print('ERROR: Error during cleanup: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_localParticipant == null) return;

    try {
      // Lưu trạng thái video hiện tại
      final wasVideoEnabled = _isVideoEnabled;

      // Unpublish video track hiện tại
      await _localParticipant!.unpublishAllTracks();

      // Tạo video track mới với camera ngược lại
      final newVideoTrack = await livekit.LocalVideoTrack.createCameraTrack();
      // Note: LiveKit Flutter không hỗ trợ trực tiếp cameraPosition
      // Chúng ta sẽ xử lý việc chuyển camera thông qua việc tạo track mới

      // Publish video track mới
      await _localParticipant!.publishVideoTrack(newVideoTrack);

      // Khôi phục trạng thái video
      if (wasVideoEnabled) {
        await _localParticipant!.setCameraEnabled(true);
      }

      setState(() {
        _isFrontCamera = !_isFrontCamera;
      });
    } catch (e) {
      print('Error switching camera: $e');
      _handleError('Không thể chuyển camera');
    }
  }

  Future<void> _updateCallStatus(String status) async {
    print(
      'DEBUG: _updateCallStatus called for CallId: ${widget.callId} with status: $status.',
    );
    try {
      await _callService.updateCallStatus(widget.callId, status);
      if (status == 'ended' && mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      print(
        'ERROR: Error updating call status for CallId: ${widget.callId}: $e',
      );
      _handleError('Không thể cập nhật trạng thái cuộc gọi');
    }
  }

  void _listenToFirebaseCallStatus() {
    _firebaseCallStateSubscription = _callService.listenToCallStatus(widget.callId).listen((
      event,
    ) {
      if (!mounted) {
        print(
          'DEBUG: Firebase call status listener received event but widget not mounted. Cancelling listener.',
        );
        _firebaseCallStateSubscription?.cancel();
        return;
      }

      if (event.snapshot.value == null) {
        print(
          'DEBUG: Firebase call status listener: Call entry disappeared from Firebase. Ending call.',
        );
        _endCall(reason: "Firebase call entry disappeared");
        return;
      }

      final data = event.snapshot.value as Map<dynamic, dynamic>;
      final status = data['status'] as String;
      print(
        'DEBUG: Firebase call status listener: Received status: $status for CallId: ${widget.callId}',
      );

      if (status == 'rejected' ||
          status == 'ended' ||
          status == 'missed' ||
          status == 'cancelled') {
        print('DEBUG: Call status changed to $status. Ending call.');
        _endCall(reason: "Call status updated to $status on Firebase");
      }
    });
  }
}
