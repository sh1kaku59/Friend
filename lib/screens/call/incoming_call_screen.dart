import 'package:flutter/material.dart';
import 'call_screen.dart';
// import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/callservice.dart';
import 'package:just_audio/just_audio.dart';
import '../../services/call_animation_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final String callerId;
  final String callerName;
  final String callerAvatar;
  final String type;

  const IncomingCallScreen({
    Key? key,
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.callerAvatar,
    required this.type,
  }) : super(key: key);

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  final CallService _callService = CallService();
  final CallAnimationService _animationService = CallAnimationService();
  Timer? _callTimeout;
  StreamSubscription? _callStateSubscription;
  final AudioPlayer _ringtonePlayer = AudioPlayer();
  bool _isRinging = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _initializeRingtone();
    _setupCallListener();
    _initializeAnimations();
    if (!kIsWeb) {
      _startIncomingCallEffects();
    }
    _callTimeout = Timer(Duration(seconds: 30), () async {
      if (mounted) {
        print(
          'DEBUG: Incoming call timeout. Checking call status on Firebase.',
        );
        final currentCallStatus = await _callService.getCallStatus(
          widget.callId,
        );
        if (currentCallStatus['status'] == 'pending') {
          print(
            'DEBUG: Call ${widget.callId} is still pending. Updating to missed.',
          );
          await _callService.updateCallStatus(widget.callId, 'missed');
        }
        _stopRinging();
        _callStateSubscription?.cancel();
        if (mounted) {
          Navigator.pop(context);
          print('DEBUG: Popped IncomingCallScreen due to timeout.');
        }
      }
    });
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  Future<void> _startIncomingCallEffects() async {
    await _animationService.startVibration();
  }

  Future<void> _initializeRingtone() async {
    try {
      await _ringtonePlayer.setAsset('assets/sounds/ringtone.mp3');
      await _ringtonePlayer.setLoopMode(LoopMode.one);
      await _startRinging();
    } catch (e) {
      print('Error initializing ringtone: $e');
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

  void _setupCallListener() {
    _callStateSubscription = _callService.listenToCallStatus(widget.callId).listen((
      event,
    ) {
      if (!mounted) {
        print(
          'DEBUG: _setupCallListener received event but widget not mounted. Cancelling listener.',
        );
        _callStateSubscription
            ?.cancel(); // Đảm bảo hủy nếu widget không còn mounted
        return;
      }

      if (event.snapshot.value == null) {
        print(
          'DEBUG: Call status listener: Call entry disappeared from Firebase. Popping screen.',
        );
        _callStateSubscription?.cancel(); // Hủy ngay lập tức
        Navigator.pop(context);
        return;
      }

      final data = event.snapshot.value as Map<dynamic, dynamic>;
      print(
        'DEBUG: Call status listener: Received status: ${data['status']} for callId: ${widget.callId}',
      );

      // Nếu trạng thái cuộc gọi không còn là pending (hoặc accepted), pop màn hình
      if (data['status'] == 'rejected' ||
          data['status'] == 'ended' ||
          data['status'] == 'missed' ||
          data['status'] == 'cancelled') {
        print(
          'DEBUG: Call status listener: Status is ${data['status']}. Popping IncomingCallScreen.',
        );
        _callStateSubscription?.cancel(); // Hủy ngay lập tức
        Navigator.pop(context);
      }
    });
  }

  Future<void> _acceptCall() async {
    print('DEBUG: _acceptCall called. CallId: ${widget.callId}');
    await _stopRinging();
    _callTimeout?.cancel(); // Hủy timeout ngay lập tức

    // HUY LISTENER NGAY LẬP TỨC TRƯỚC KHI ĐIỀU HƯỚNG
    _callStateSubscription?.cancel();
    _callStateSubscription = null; // Đảm bảo biến được set về null

    // Kiểm tra quyền truy cập
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    if (cameraStatus.isDenied || micStatus.isDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cần quyền truy cập camera và microphone để thực hiện cuộc gọi',
          ),
          action: SnackBarAction(
            label: 'Cài đặt',
            onPressed: () => openAppSettings(),
          ),
        ),
      );
      print('DEBUG: Camera/Mic permissions denied. Cannot accept call.');
      // Nếu quyền bị từ chối, cập nhật trạng thái cuộc gọi là rejected và pop màn hình
      await _callService.updateCallStatus(widget.callId, 'rejected');
      if (mounted) {
        Navigator.pop(context);
      }
      return;
    }

    await _callService.updateCallStatus(widget.callId, 'accepted');
    print('DEBUG: Call status updated to "accepted" in Firebase.');

    if (mounted) {
      print('DEBUG: Navigating to CallScreen (replacing IncomingCallScreen).');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (context) => CallScreen(
                callId: widget.callId,
                userId: FirebaseAuth.instance.currentUser!.uid,
                isIncoming: true,
                type: widget.type,
                remoteParticipantName: widget.callerName,
                remoteParticipantAvatar: widget.callerAvatar,
              ),
        ),
      );
    }
  }

  Future<void> _rejectCall() async {
    print('DEBUG: _rejectCall called. CallId: ${widget.callId}');
    await _stopRinging();
    _callTimeout?.cancel(); // Hủy timeout
    _callStateSubscription?.cancel(); // Hủy listener ngay lập tức
    _callStateSubscription = null;

    await _callService.updateCallStatus(widget.callId, 'rejected');
    print('DEBUG: Call status updated to "rejected" in Firebase.');
    if (mounted) {
      Navigator.pop(context);
      print('DEBUG: Popped IncomingCallScreen after rejecting.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Spacer(),
            // Animated avatar
            AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Opacity(
                    opacity: _opacityAnimation.value,
                    child: CircleAvatar(
                      radius: 50,
                      backgroundImage: NetworkImage(widget.callerAvatar),
                    ),
                  ),
                );
              },
            ),
            SizedBox(height: 20),
            // Animated text
            AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Opacity(
                  opacity: _opacityAnimation.value,
                  child: Text(
                    widget.callerName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
            Text('đang gọi...', style: TextStyle(color: Colors.white70)),
            Spacer(),
            // Call buttons with animation
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAnimatedCallButton(
                  icon: Icons.call_end,
                  color: Colors.red,
                  onPressed: _rejectCall,
                ),
                _buildAnimatedCallButton(
                  icon: Icons.call,
                  color: Colors.green,
                  onPressed: _acceptCall,
                ),
              ],
            ),
            SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedCallButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(icon),
              color: Colors.white,
              onPressed: onPressed,
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    print(
      'DEBUG: IncomingCallScreen dispose() called for CallId: ${widget.callId}.',
    );
    _callTimeout?.cancel();
    _callStateSubscription?.cancel(); // Đảm bảo hủy listener
    _ringtonePlayer.dispose();
    _animationController.dispose();
    _animationService.dispose();
    super.dispose();
  }
}
