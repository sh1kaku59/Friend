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

    // Lắng nghe trạng thái cuộc gọi
    _callSubscription = FirebaseDatabase.instance
        .ref('calls/${widget.appointmentId}')
        .onValue
        .listen((event) {
          if (event.snapshot.value == null) {
            // Cuộc gọi đã bị hủy
            Navigator.pop(context);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text("Cuộc gọi đã kết thúc")));
            return;
          }

          final data = event.snapshot.value as Map<dynamic, dynamic>;
          if (data['status'] == 'rejected' || data['status'] == 'ended') {
            // Người gọi đã hủy cuộc gọi
            Navigator.pop(context);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text("Cuộc gọi đã kết thúc")));
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
      backgroundColor: Colors.blue[900],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 50,
              backgroundImage: NetworkImage(widget.callerAvatarUrl),
            ),
            SizedBox(height: 20),
            Text(
              widget.callerName,
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 20),
            Text(
              "Đang gọi...",
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
            SizedBox(height: 50),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Nút từ chối cuộc gọi
                IconButton(
                  icon: Icon(Icons.call_end, color: Colors.red, size: 40),
                  onPressed: () async {
                    try {
                      await _signaling.rejectCall(widget.appointmentId);
                      Navigator.pop(context);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Lỗi khi từ chối cuộc gọi: $e")),
                      );
                    }
                  },
                ),
                SizedBox(width: 50),
                // Nút chấp nhận cuộc gọi
                IconButton(
                  icon: Icon(Icons.call, color: Colors.green, size: 40),
                  onPressed: () async {
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
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
