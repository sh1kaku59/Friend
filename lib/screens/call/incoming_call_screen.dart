import 'package:flutter/material.dart';
import '../../services/signaling.dart';
import 'call_screen.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';

class IncomingCallScreen extends StatefulWidget {
  final String callerName;
  final String callerAvatarUrl;
  final String appointmentId;

  const IncomingCallScreen({
    super.key,
    required this.callerName,
    required this.callerAvatarUrl,
    required this.appointmentId,
  });

  @override
  _IncomingCallScreenState createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  final Signaling _signaling = Signaling();
  late StreamSubscription _callSubscription;

  @override
  void initState() {
    super.initState();
    _setupCallListener();
  }

  void _setupCallListener() {
    _callSubscription = FirebaseDatabase.instance
        .ref('calls/${widget.appointmentId}')
        .onValue
        .listen((event) {
          if (event.snapshot.value == null) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Cuộc gọi đã kết thúc")),
            );
            return;
          }

          final data = event.snapshot.value as Map<dynamic, dynamic>;
          if (data['status'] == 'rejected' || data['status'] == 'ended') {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Cuộc gọi đã kết thúc")),
            );
          }
        });
  }

  @override
  void dispose() {
    _callSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 1),
            // Avatar và thông tin người gọi
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundImage: NetworkImage(widget.callerAvatarUrl),
                  backgroundColor: Colors.grey[300],
                ),
                const SizedBox(height: 24),
                Text(
                  widget.callerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "đang gọi...",
                  style: TextStyle(color: Colors.white70, fontSize: 19),
                ),
              ],
            ),
            const Spacer(flex: 2),
            // Các nút điều khiển cuộc gọi
            Padding(
              padding: const EdgeInsets.only(bottom: 50),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Nút từ chối
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          try {
                            await _signaling.rejectCall(widget.appointmentId);
                            Navigator.pop(context);
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Lỗi khi từ chối cuộc gọi: $e"),
                              ),
                            );
                          }
                        },
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.call_end,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "Từ chối",
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                  // Nút chấp nhận
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () async {
                          try {
                            await _signaling.acceptCall(widget.appointmentId);
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) => CallScreen(
                                      friendId: widget.appointmentId,
                                      friendName: widget.callerName,
                                      friendAvatarUrl: widget.callerAvatarUrl,
                                      appointmentId: widget.appointmentId,
                                    ),
                              ),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Lỗi khi chấp nhận cuộc gọi: $e"),
                              ),
                            );
                          }
                        },
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.call,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "Chấp nhận",
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
