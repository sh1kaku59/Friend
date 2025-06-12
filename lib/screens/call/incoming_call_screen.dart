import 'package:flutter/material.dart';
import 'call_screen.dart';
// import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/callservice.dart';
import 'package:just_audio/just_audio.dart';
import '../../services/call_animation_service.dart';

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
    _startIncomingCallEffects();
    // Tự động từ chối sau 30 giây
    _callTimeout = Timer(Duration(seconds: 30), () {
      if (mounted) {
        _callService.updateCallStatus(widget.callId, 'rejected');
        Navigator.pop(context);
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
    _callStateSubscription = _callService
        .listenToCallStatus(widget.callId)
        .listen((event) {
          if (event.snapshot.value == null) {
            Navigator.pop(context);
            return;
          }

          final data = event.snapshot.value as Map<dynamic, dynamic>;
          if (data['status'] == 'rejected' ||
              data['status'] == 'ended' ||
              data['status'] == 'missed') {
            Navigator.pop(context);
          }
        });
  }

  Future<void> _acceptCall() async {
    await _stopRinging();
    // Kiểm tra quyền truy cập
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    if (cameraStatus.isDenied || micStatus.isDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cần quyền truy cập camera và microphone')),
      );
      return;
    }

    await _callService.updateCallStatus(widget.callId, 'accepted');

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (context) => CallScreen(
                callId: widget.callId,
                userId: FirebaseAuth.instance.currentUser!.uid,
                isIncoming: true,
                type: widget.type,
              ),
        ),
      );
    }
  }

  Future<void> _rejectCall() async {
    await _stopRinging();
    await _callService.updateCallStatus(widget.callId, 'rejected');
    if (mounted) {
      Navigator.pop(context);
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
    _callTimeout?.cancel();
    _callStateSubscription?.cancel();
    _ringtonePlayer.dispose();
    _animationController.dispose();
    _animationService.dispose();
    super.dispose();
  }
}
